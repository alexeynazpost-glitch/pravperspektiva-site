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
    *) echo "Сертификат ещё не выпущен — повторите позже";;
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
  live-check)
    echo "-- robots.txt"; curl -sS https://fedeta.ru/robots.txt
    echo "-- sitemap: страниц"; curl -sS https://fedeta.ru/sitemap-0.xml | grep -o "<loc>" | wc -l
    echo "-- noindex на главной:"; curl -sS https://fedeta.ru/ | grep -o '<meta name="robots"[^>]*>' || echo "нет (индексация открыта)"
    echo "-- реквизиты:"; curl -sS https://fedeta.ru/politika/ | grep -o "Оператор персональных данных[^<]*\|Редакция от[^<]*" | head -3
    echo "-- метрика:"; curl -sS https://fedeta.ru/ | grep -o "mc.yandex.ru/[a-z/.]*[0-9]*\|ym(Number([^)]*)\|ymId[^,;]*\|webvisor:[a-z]*" | sort -u
    echo "-- tag.js доступен:"; curl -sS -o /dev/null -w "%{http_code}\n" https://mc.yandex.ru/metrika/tag.js
    ;;
  # ===== Новый домен fedeta.ru (переезд с yustika.ru) =====
  nd-setup)
    D=fedeta.ru; Z=fedeta-ru
    for b in $D www.$D; do yc storage bucket get --name "$b" >/dev/null 2>&1 || yc storage bucket create --name "$b" --default-storage-class standard --public-read; done
    yc storage bucket update --name $D --public-read --website-settings '{"index":"index.html","error":"404.html"}' >/dev/null
    yc storage bucket update --name www.$D --public-read --website-settings "{\"redirect_all_requests\":{\"protocol\":\"PROTOCOL_HTTPS\",\"hostname\":\"$D\"}}" >/dev/null
    yc dns zone get --name $Z >/dev/null 2>&1 || yc dns zone create --name $Z --zone $D. --public-visibility >/dev/null
    yc dns zone add-records --name $Z --record "$D. 600 ANAME $D.website.yandexcloud.net." --record "www.$D. 600 CNAME www.$D.website.yandexcloud.net." >/dev/null 2>&1 || true
    yc certificate-manager certificate get --name $Z >/dev/null 2>&1 || yc certificate-manager certificate request --name $Z --domains $D,www.$D --challenge dns >/dev/null
    yc certificate-manager certificate get --name $Z --full --format json > cert.json
    jq -r '.challenges[] | select(.dns_challenge and .dns_challenge.type == "CNAME") | "\(.dns_challenge.name) \(.dns_challenge.value)"' cert.json | while read -r n v; do
      yc dns zone add-records --name $Z --record "$n 600 CNAME $v" >/dev/null 2>&1 || true; done
    rm cert.json
    echo "== Записи зоны:"; yc dns zone list-records --name $Z | cut -c1-150
    echo "== Сертификат:"; yc certificate-manager certificate get --name $Z --format json | jq -c '{status, domains}'
    echo "== NS для Рег.ру: ns1.yandexcloud.net, ns2.yandexcloud.net"
    ;;
  nd-check)
    D=fedeta.ru
    echo "-- NS у реестра .ru"; dig NS $D @a.dns.ripn.net +noall +authority; echo "-- NS (8.8.8.8)"; dig +short NS $D @8.8.8.8; echo "-- федета.рф"; dig NS xn--80ahcb9di.xn--p1ai @a.dns.ripn.net +noall +authority; whois $D 2>/dev/null | grep -i "state\|nserver\|created" || true
    echo "-- Сертификат:"; yc certificate-manager certificate get --name fedeta-ru --format json | jq -c '{status}'
    echo "-- Бакет:"; curl -sS -o /dev/null -w "%{http_code}\n" http://$D.website.yandexcloud.net/
    for u in http://$D/ https://$D/ https://www.$D/ "https://yustika.ru/konsultaciya/?utm_source=yandex&yclid=123" http://xn--80ahcb9di.xn--p1ai/; do echo "-- $u"; curl -sS -o /dev/null -D - --max-redirs 0 "$u" 2>&1 | grep -i "^HTTP\|^location\|curl" || true; done
    echo "-- Заголовок главной:"; curl -sS https://$D/ | grep -o "<title>[^<]*" | head -1
    ;;
  nd-https)
    CERT=$(yc certificate-manager certificate get --name fedeta-ru --format json | jq -r '.id + " " + .status'); echo "Сертификат: $CERT"
    case "$CERT" in *ISSUED*) for b in fedeta.ru www.fedeta.ru; do yc storage bucket set-https --name "$b" --certificate-id "${CERT%% *}" >/dev/null && echo "HTTPS включён для $b"; done;;
    *) echo "Сертификат ещё не выпущен — повторите позже";; esac
    ;;
  nd-redirect)
    # Старый домен: все страницы yustika.ru → те же адреса на fedeta.ru (301)
    for b in yustika.ru www.yustika.ru; do
      yc storage bucket update --name "$b" --website-settings '{"redirect_all_requests":{"protocol":"PROTOCOL_HTTPS","hostname":"fedeta.ru"}}' >/dev/null && echo "Перенаправление включено: $b → fedeta.ru"
    done
    ;;
  nd-rf)
    # федета.рф → https://fedeta.ru (перенаправление всех адресов)
    D=xn--80ahcb9di.xn--p1ai; Z=fedeta-rf
    for b in $D www.$D; do yc storage bucket get --name "$b" >/dev/null 2>&1 || yc storage bucket create --name "$b" --public-read >/dev/null; \
      yc storage bucket update --name "$b" --public-read --website-settings '{"redirect_all_requests":{"protocol":"PROTOCOL_HTTPS","hostname":"fedeta.ru"}}' >/dev/null; done
    yc dns zone get --name $Z >/dev/null 2>&1 || yc dns zone create --name $Z --zone $D. --public-visibility >/dev/null
    yc dns zone add-records --name $Z --record "$D. 600 ANAME $D.website.yandexcloud.net." --record "www.$D. 600 CNAME www.$D.website.yandexcloud.net." >/dev/null 2>&1 || true
    yc dns zone list-records --name $Z | cut -c1-150
    echo "-- NS у реестра .рф"; dig +short NS $D @a.dns.ripn.net
    ;;
  nd-verify)
    yc dns zone add-records --name fedeta-ru --record 'fedeta.ru. 600 TXT "yandex-verification: e49f8cdfca37aa58"' >/dev/null 2>&1 || true
    sleep 20; echo "-- TXT fedeta.ru"; dig +short TXT fedeta.ru @ns1.yandexcloud.net
    ;;
  ym-test)
    mkdir -p /tmp/ymt && cd /tmp/ymt && npm init -y >/dev/null && npm i playwright@1.49.1 >/dev/null 2>&1 && npx playwright install --with-deps chromium >/dev/null 2>&1
    cat > t.js <<'JS'
const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();
p.on('request',r=>{if(/mc\.yandex/.test(r.url()))console.log('REQ',r.url().slice(0,160))});
p.on('response',r=>{if(/mc\.yandex/.test(r.url()))console.log('RES',r.status(),r.url().slice(0,90))});
p.on('pageerror',e=>console.log('PAGEERR',e.message));
await p.goto('https://fedeta.ru/?utm_source=test',{waitUntil:'load'});await p.waitForTimeout(8000);
console.log('ym:',await p.evaluate(()=>typeof window.ym+' id='+window.__ymId));await b.close()})();
JS
    node t.js
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
