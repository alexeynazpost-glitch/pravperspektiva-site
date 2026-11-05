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
esac
