#!/usr/bin/env bash
# Шаги настройки Яндекс Облака. Запускается из workflow «Настройка Облака».
set -euo pipefail
STEP="${1:-check}"
BUCKET=yustika.ru
echo "== Шаг: $STEP"
case "$STEP" in
  check)
    yc config list | grep -v -i key || true
    echo "== Облака и каталоги:"; yc resource-manager cloud list; yc resource-manager folder list
    echo "== Бакеты:"; yc storage bucket list
    ;;
  bucket)
    if ! yc storage bucket get --name "$BUCKET" >/dev/null 2>&1; then
      yc storage bucket create --name "$BUCKET" --default-storage-class standard --public-read
    fi
    yc storage bucket update --name "$BUCKET" --public-read \
      --website-settings '{"index":"index.html","error":"404.html"}'
    yc storage bucket get --name "$BUCKET" --full | grep -v -i secret
    ;;
esac
