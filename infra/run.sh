#!/usr/bin/env bash
# Шаги настройки Яндекс Облака. Запускается из workflow «Настройка Облака».
set -euo pipefail
# ВНИМАНИЕ: никогда не печатать yc config list — там приватный ключ.
STEP="${1:-check}"
BUCKET=yustika.ru
echo "== Шаг: $STEP"
case "$STEP" in
  check)
    echo "== Каталог:"; yc resource-manager folder get "$YC_FOLDER_ID" --format json | jq -c '{id, name, status}'
    echo "== Бакеты:"; yc storage bucket list
    ;;
  bucket)
    if ! yc storage bucket get --name "$BUCKET" >/dev/null 2>&1; then
      yc storage bucket create --name "$BUCKET" --default-storage-class standard --public-read
    fi
    yc storage bucket update --name "$BUCKET" --public-read \
      --website-settings '{"index":"index.html","error":"404.html"}'
    if ! yc storage bucket get --name yustika-backup >/dev/null 2>&1; then
      yc storage bucket create --name yustika-backup --default-storage-class cold || true
    fi
    yc storage bucket get --name "$BUCKET" --format json | jq -c '{name, anonymous_access_flags, default_storage_class}'
    ;;
  dns-plan)
    # Показать текущие записи домена у Рег.ру (они будут перенесены в Cloud DNS)
    for t in MX TXT A; do echo "-- $t @"; dig +short "$t" yustika.ru @ns1.reg.ru; done
    echo "-- TXT mail._domainkey"; dig +short TXT mail._domainkey.yustika.ru @ns1.reg.ru
    ;;
  dns)
    ZONE=yustika-ru
    if ! yc dns zone get --name "$ZONE" >/dev/null 2>&1; then
      yc dns zone create --name "$ZONE" --zone yustika.ru. --public-visibility
    fi
    # Сайт: корень — на бакет через ANAME, www — на бакет-переадресацию
    if ! yc storage bucket get --name www.yustika.ru >/dev/null 2>&1; then
      yc storage bucket create --name www.yustika.ru --public-read || true
    fi
    yc storage bucket update --name www.yustika.ru \
      --website-settings '{"redirect_all_requests":{"protocol":"PROTOCOL_HTTPS","hostname":"yustika.ru"}}'
    MX=$(dig +short MX yustika.ru @ns1.reg.ru | head -1)
    DKIM=$(dig +short TXT mail._domainkey.yustika.ru @ns1.reg.ru | sed 's/" "//g; s/^"//; s/"$//')
    SPF=$(dig +short TXT yustika.ru @ns1.reg.ru | grep -o 'v=spf1[^"]*')
    VER=$(dig +short TXT yustika.ru @ns1.reg.ru | grep -o 'yandex-verification[^"]*')
    [ -n "$MX" ] && [ -n "$DKIM" ] && [ -n "$SPF" ] || { echo "Не удалось прочитать записи почты у Рег.ру"; exit 1; }
    yc dns zone replace-records --name "$ZONE" \
      --record "yustika.ru. 600 ANAME yustika.ru.website.yandexcloud.net." \
      --record "www.yustika.ru. 600 CNAME www.yustika.ru.website.yandexcloud.net." \
      --record "yustika.ru. 3600 MX $MX" \
      --record "yustika.ru. 3600 TXT \"$SPF\"" \
      --record "yustika.ru. 3600 TXT \"$VER\"" \
      --record "mail._domainkey.yustika.ru. 3600 TXT \"$DKIM\""
    yc dns zone list-records --name "$ZONE" | cut -c1-160
    ;;
  dns-check)
    for t in MX TXT ANAME; do echo "-- $t @ (Cloud DNS)"; dig +short "$t" yustika.ru @ns1.yandexcloud.net | cut -c1-80; done
    echo "-- A @ (Cloud DNS)"; dig +short A yustika.ru @ns1.yandexcloud.net
    echo "-- DKIM (Cloud DNS)"; dig +short TXT mail._domainkey.yustika.ru @ns1.yandexcloud.net | cut -c1-60
    echo "-- NS у реестра .ru"; dig +short NS yustika.ru @a.dns.ripn.net
    echo "-- Сайт через бакет:"; curl -sS -o /dev/null -w "%{http_code}\n" http://yustika.ru.website.yandexcloud.net/
    ;;
  cert)
    NAME=yustika-ru
    if ! yc certificate-manager certificate get --name "$NAME" >/dev/null 2>&1; then
      yc certificate-manager certificate request --name "$NAME" --domains yustika.ru,www.yustika.ru --challenge dns
    fi
    yc certificate-manager certificate get --name "$NAME" --full --format json > cert.json
    jq -c '{status, domains}' cert.json
    jq -r '.challenges[] | select(.dns_challenge and .dns_challenge.type == "CNAME") | "\(.dns_challenge.name) \(.dns_challenge.type) \(.dns_challenge.value)"' cert.json | while read -r n t v; do
      echo "challenge: $n $t $v"
      if [ "$t" = TXT ]; then v="\"$v\""; fi
      yc dns zone add-records --name yustika-ru --record "$n 600 $t $v" || true
    done
    rm cert.json
    ;;
  https)
    CERT=$(yc certificate-manager certificate get --name yustika-ru --format json | jq -r '.id + " " + .status')
    echo "Сертификат: $CERT"
    case "$CERT" in *ISSUED*)
      for b in yustika.ru www.yustika.ru; do
        yc storage bucket set-https --name "$b" --certificate-id "${CERT%% *}" && echo "HTTPS включён для $b"
      done;;
    *) echo "Сертификат ещё не выпущен — повторите позже";;   postbox)
    TOKEN=$(yc iam create-token)
    if curl -sSf -o /dev/null https://postbox.cloud.yandex.net/v2/email/identities/yustika.ru -H "X-YaCloud-SubjectToken: $TOKEN"; then
      echo "Адрес yustika.ru в Postbox уже есть"
    else
      openssl genrsa -out pb.pem 1024 2>/dev/null
      PRIV=$(grep -v '^-----' pb.pem | tr -d '\n')
      PUB=$(openssl rsa -in pb.pem -pubout 2>/dev/null | grep -v '^-----' | tr -d '\n')
      rm -f pb.pem
      jq -n --arg k "$PRIV" '{EmailIdentity:"yustika.ru", DkimSigningAttributes:{DomainSigningSelector:"postbox", DomainSigningPrivateKey:$k}}' > req.json
      unset PRIV
      curl -sS -X POST https://postbox.cloud.yandex.net/v2/email/identities \
        -H "X-YaCloud-SubjectToken: $TOKEN" -H 'Content-Type: application/json' --data @req.json | jq -c '{IdentityType, VerifiedForSendingStatus, Dkim: .DkimAttributes.Status, Error: .message}'
      rm -f req.json
      yc dns zone add-records --name yustika-ru --record "postbox._domainkey.yustika.ru. 3600 TXT \"v=DKIM1; k=rsa; p=$PUB\""
    fi
    curl -sS https://postbox.cloud.yandex.net/v2/email/identities/yustika.ru -H "X-YaCloud-SubjectToken: $TOKEN" | jq -c '{VerifiedForSendingStatus, Dkim: .DkimAttributes.Status}'
    ;;
  leads)
    yc storage bucket get --name yustika-leads >/dev/null 2>&1 || yc storage bucket create --name yustika-leads --default-storage-class standard
    aws s3api put-bucket-lifecycle-configuration --endpoint-url=https://storage.yandexcloud.net --bucket yustika-leads \
      --lifecycle-configuration '{"Rules":[{"ID":"delete-after-1-year","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":365}}]}' \
      && echo "Заявки хранятся 1 год, потом удаляются автоматически" || echo "lifecycle: не удалось"
    SA_ID=$(yc iam service-account get --name github-deploy --format json | jq -r .id)
    yc serverless function get --name leads >/dev/null 2>&1 || yc serverless function create --name leads >/dev/null
    curl -sSL -o infra/leads/ru-ca.pem https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt
    yc serverless function version create --function-name leads --runtime nodejs22 --entrypoint index.handler \
      --memory 128m --execution-timeout 15s --source-path infra/leads --service-account-id "$SA_ID" \
      --environment LEADS_BUCKET=yustika-leads --environment MAIL_FROM=zayavki@yustika.ru --environment MAIL_TO=info@yustika.ru \
      --environment MAX_USER_ID=84181430 --environment "MAX_BOT_TOKEN=$MAX_BOT_TOKEN" \
      --environment NODE_EXTRA_CA_CERTS=/function/code/ru-ca.pem >/dev/null && echo "Версия функции создана"
    yc serverless function allow-unauthenticated-invoke --name leads >/dev/null 2>&1 && echo "Функция открыта для вызова с сайта" || echo "Нужно вручную сделать функцию публичной (нужны права администратора)"
    echo "Адрес: https://functions.yandexcloud.net/$(yc serverless function get --name leads --format json | jq -r .id)"
    ;;
  site-check)
    for u in http://yustika.ru/ https://yustika.ru/ http://www.yustika.ru/ https://www.yustika.ru/kontakty/; do
      echo "-- $u"; curl -sS -o /dev/null -D - --max-redirs 0 "$u" | grep -i "^HTTP\|^location" || true
    done
    echo "-- Сертификат:"; echo | openssl s_client -connect yustika.ru:443 -servername yustika.ru 2>/dev/null | openssl x509 -noout -subject -issuer -dates
    ;;
  leads-ls)
    aws s3 ls --endpoint-url=https://storage.yandexcloud.net s3://yustika-leads/leads/ --recursive | tail -5 | awk '{print $1, $2, $3, "bytes"}'
    ;;
  fn-logs)
    yc serverless function logs leads --since "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" 2>&1 | tail -15 | cut -c1-300 || true
    ;;
  lead-test)
    URL="https://functions.yandexcloud.net/$(yc serverless function get --name leads --format json | jq -r .id)"
    curl -sS -X POST "$URL" -H 'Origin: https://yustika.ru' -H 'Content-Type: application/json' \
      -d '{"form":"callback","contact":"ТЕСТ — проверка приёма заявок","when":"Как можно скорее","page":"/test/"}' -w "\nHTTP %{http_code}\n"
    sleep 5
    yc serverless function logs leads --since "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" 2>&1 | grep -i "partial\|error\|lead" | tail -8 | cut -c1-300 || true
    ;;
esac
    ;;
  postbox)
    TOKEN=$(yc iam create-token)
    if curl -sSf -o /dev/null https://postbox.cloud.yandex.net/v2/email/identities/yustika.ru -H "X-YaCloud-SubjectToken: $TOKEN"; then
      echo "Адрес yustika.ru в Postbox уже есть"
    else
      openssl genrsa -out pb.pem 1024 2>/dev/null
      PRIV=$(grep -v '^-----' pb.pem | tr -d '\n')
      PUB=$(openssl rsa -in pb.pem -pubout 2>/dev/null | grep -v '^-----' | tr -d '\n')
      rm -f pb.pem
      jq -n --arg k "$PRIV" '{EmailIdentity:"yustika.ru", DkimSigningAttributes:{DomainSigningSelector:"postbox", DomainSigningPrivateKey:$k}}' > req.json
      unset PRIV
      curl -sS -X POST https://postbox.cloud.yandex.net/v2/email/identities \
        -H "X-YaCloud-SubjectToken: $TOKEN" -H 'Content-Type: application/json' --data @req.json | jq -c '{IdentityType, VerifiedForSendingStatus, Dkim: .DkimAttributes.Status, Error: .message}'
      rm -f req.json
      yc dns zone add-records --name yustika-ru --record "postbox._domainkey.yustika.ru. 3600 TXT \"v=DKIM1; k=rsa; p=$PUB\""
    fi
    curl -sS https://postbox.cloud.yandex.net/v2/email/identities/yustika.ru -H "X-YaCloud-SubjectToken: $TOKEN" | jq -c '{VerifiedForSendingStatus, Dkim: .DkimAttributes.Status}'
    ;;
  leads)
    yc storage bucket get --name yustika-leads >/dev/null 2>&1 || yc storage bucket create --name yustika-leads --default-storage-class standard
    aws s3api put-bucket-lifecycle-configuration --endpoint-url=https://storage.yandexcloud.net --bucket yustika-leads \
      --lifecycle-configuration '{"Rules":[{"ID":"delete-after-1-year","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":365}}]}' \
      && echo "Заявки хранятся 1 год, потом удаляются автоматически" || echo "lifecycle: не удалось"
    SA_ID=$(yc iam service-account get --name github-deploy --format json | jq -r .id)
    yc serverless function get --name leads >/dev/null 2>&1 || yc serverless function create --name leads >/dev/null
    curl -sSL -o infra/leads/ru-ca.pem https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt
    yc serverless function version create --function-name leads --runtime nodejs22 --entrypoint index.handler \
      --memory 128m --execution-timeout 15s --source-path infra/leads --service-account-id "$SA_ID" \
      --environment LEADS_BUCKET=yustika-leads --environment MAIL_FROM=zayavki@yustika.ru --environment MAIL_TO=info@yustika.ru \
      --environment MAX_USER_ID=84181430 --environment "MAX_BOT_TOKEN=$MAX_BOT_TOKEN" \
      --environment NODE_EXTRA_CA_CERTS=/function/code/ru-ca.pem >/dev/null && echo "Версия функции создана"
    yc serverless function allow-unauthenticated-invoke --name leads >/dev/null 2>&1 && echo "Функция открыта для вызова с сайта" || echo "Нужно вручную сделать функцию публичной (нужны права администратора)"
    echo "Адрес: https://functions.yandexcloud.net/$(yc serverless function get --name leads --format json | jq -r .id)"
    ;;
  site-check)
    for u in http://yustika.ru/ https://yustika.ru/ http://www.yustika.ru/ https://www.yustika.ru/kontakty/; do
      echo "-- $u"; curl -sS -o /dev/null -D - --max-redirs 0 "$u" | grep -i "^HTTP\|^location" || true
    done
    echo "-- Сертификат:"; echo | openssl s_client -connect yustika.ru:443 -servername yustika.ru 2>/dev/null | openssl x509 -noout -subject -issuer -dates
    ;;
  leads-ls)
    aws s3 ls --endpoint-url=https://storage.yandexcloud.net s3://yustika-leads/leads/ --recursive | tail -5 | awk '{print $1, $2, $3, "bytes"}'
    ;;
  fn-logs)
    yc serverless function logs leads --since "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" 2>&1 | tail -15 | cut -c1-300 || true
    ;;
  lead-test)
    URL="https://functions.yandexcloud.net/$(yc serverless function get --name leads --format json | jq -r .id)"
    curl -sS -X POST "$URL" -H 'Origin: https://yustika.ru' -H 'Content-Type: application/json' \
      -d '{"form":"callback","contact":"ТЕСТ — проверка приёма заявок","when":"Как можно скорее","page":"/test/"}' -w "\nHTTP %{http_code}\n"
    sleep 5
    yc serverless function logs leads --since "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" 2>&1 | grep -i "partial\|error\|lead" | tail -8 | cut -c1-300 || true
    ;;
esac
