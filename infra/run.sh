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
      yc storage bucket create --name yustika-backup --default-storage-class cold
    fi
    yc storage bucket get --name "$BUCKET" --format json | jq -c '{name, anonymous_access_flags, default_storage_class}'
    ;;
esac
