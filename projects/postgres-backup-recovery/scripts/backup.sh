#!/bin/sh
set -eu

# обязательные переменные: если нет — умереть с понятной ошибкой
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"

BACKUP_DIR="${BACKUP_DIR:-/backups}"     # :- это дефолт, если не задано

# здесь: mkdir, mktemp-имя, финальное TARGET
BACKUP_DIR="${BACKUP_DIR:-/backups}"
mkdir -p "${BACKUP_DIR}"

TMP="$(mktemp "${BACKUP_DIR}/.dump.XXXXXX")"
RANDOM_SUFFIX="$(basename "$TMP" | sed 's/^\.dump\.//')"
TARGET="${BACKUP_DIR}/$(date +%Y%m%d_%H%M%S)_${RANDOM_SUFFIX}.dump"

# если задан PGHOST (запуск из scheduler) — нужен и PGPASSWORD
if [ -n "${PGHOST:-}" ]; then
    : "${PGPASSWORD:?PGPASSWORD is required when PGHOST is set}"
fi

echo "[backup] pg_dump ${POSTGRES_DB} -> ${TARGET}"
pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Fc -f "${TMP}"

# проверка TOC: без TABLE DATA архив не считается бэкапом
if ! pg_restore --list "${TMP}" | grep -q 'TABLE DATA'; then
    echo "[backup] ERROR: archive ${TMP} has no TABLE DATA entries" >&2
    rm -f "${TMP}"
    exit 1
fi

mv "${TMP}" "${TARGET}"
echo "[backup] OK: ${TARGET} ($(du -h "${TARGET}" | cut -f1))"
