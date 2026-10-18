#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "ERROR: .env не найден. Скопируйте .env.example -> .env" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

DB_USER="${POSTGRES_USER:-devops}"
DB_NAME="${POSTGRES_DB:-devops}"
DRILL_DIR="drill/$(date +%Y%m%d_%H%M%S)"
mkdir -p "${DRILL_DIR}"

PSQL="docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U ${DB_USER}"
PSQL_MAINT="docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U ${DB_USER} -d postgres"

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
ms_to_sec() { awk "BEGIN{printf \"%.1f\", $1/1000}"; }

step() { printf '\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m[OK]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 0. Preflight -------------------------------------------------
step "0. Preflight: контейнер db должен быть запущен"
docker compose exec -T db true || die "контейнер db не запущен: docker compose up -d db"
if [ -n "$(docker compose ps -q backup-scheduler 2>/dev/null)" ]; then
    die "работает backup-scheduler — остановите: docker compose --profile scheduler stop backup-scheduler"
fi
${PSQL} -d "${DB_NAME}" -tAc "SELECT 1" >/dev/null || die "нет соединения с БД ${DB_NAME}"
ok "БД доступна"

# --- 1. Подпись ДО бэкапа -----------------------------------------
step "1. Подпись данных ДО бэкапа"
${PSQL} -d "${DB_NAME}" -f /db/signature.sql | tee "${DRILL_DIR}/signature_before.txt"
grep -q " 50 |" "${DRILL_DIR}/signature_before.txt" \
    || die "в customers ожидалось 50 строк — БД не в исходном состоянии: ./scripts/reseed.sh"

# --- 2. Бэкап -----------------------------------------------------
step "2. Бэкап: pg_dump -Fc -> volume backups"
BACKUP_START=$(now_ms)
docker compose exec -T db /scripts/backup.sh | tee "${DRILL_DIR}/backup.log"
BACKUP_END=$(now_ms)
DUMP_FILE=$(grep -o '/backups/[^ ]*\.dump' "${DRILL_DIR}/backup.log" | head -1)
[ -n "${DUMP_FILE}" ] || die "не удалось определить имя файла бэкапа"
DUMP_SIZE=$(docker compose exec -T db sh -c "du -h '${DUMP_FILE}' | cut -f1")
ok "архив: ${DUMP_FILE} (${DUMP_SIZE})"

# --- 3. Записи ПОСЛЕ бэкапа (демонстрация RPO) -------------------
step "3. Имитация приложения: +25 строк ПОСЛЕ бэкапа"
${PSQL} -d "${DB_NAME}" -f /db/insert_batch.sql >/dev/null
ROWS=$(${PSQL} -d "${DB_NAME}" -tAc "SELECT count(*) FROM orders")
[ "${ROWS}" -eq 525 ] || die "ожидалось 525 строк в orders, получено ${ROWS}"
ok "orders: ${ROWS} строк (25 — «пост-бэкапных»)"

# --- 4. СБОЙ ------------------------------------------------------
step "4. СИМУЛЯЦИЯ СБОЯ: DROP DATABASE ${DB_NAME}"
FAILURE_TS=$(now_ms)
${PSQL_MAINT} -c "DROP DATABASE ${DB_NAME} WITH (FORCE);" \
              -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"
TABLES=$(${PSQL} -d "${DB_NAME}" -tAc \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
[ "${TABLES}" -eq 0 ] || die "БД не пустая после пересоздания — сбой не доказан"
ok "БД пересоздана с нуля, таблиц: ${TABLES}"

# --- 5. Восстановление --------------------------------------------
step "5. Восстановление: pg_restore из ${DUMP_FILE}"
RESTORE_START=$(now_ms)
docker compose exec -T db pg_restore --exit-on-error -U "${DB_USER}" -d "${DB_NAME}" "${DUMP_FILE}"
RESTORE_END=$(now_ms)
ok "pg_restore завершён без ошибок"

# --- 6. Подпись ПОСЛЕ + вердикт ------------------------------------
step "6. Проверка: подпись данных ПОСЛЕ восстановления"
${PSQL} -d "${DB_NAME}" -f /db/signature.sql | tee "${DRILL_DIR}/signature_after.txt"
diff -u "${DRILL_DIR}/signature_before.txt" "${DRILL_DIR}/signature_after.txt" \
    > "${DRILL_DIR}/signature.diff" \
    || { cat "${DRILL_DIR}/signature.diff"; die "ПОДПИСИ НЕ СОВПАЛИ"; }
ok "Подписи совпали: количество строк и контрольные суммы идентичны"

ROWS_RESTORED=$(${PSQL} -d "${DB_NAME}" -tAc "SELECT count(*) FROM orders")
[ "${ROWS_RESTORED}" -eq 500 ] || die "ожидалось 500 строк после восстановления, получено ${ROWS_RESTORED}"
ok "orders после восстановления: ${ROWS_RESTORED} — 25 «пост-бэкапных» потеряны (демонстрация RPO)"

# --- 7. Метрики и отчёт --------------------------------------------
step "7. Метрики"
VERIFY_TS=$(now_ms)
RTO_MS=$((VERIFY_TS - FAILURE_TS))
RESTORE_MS=$((RESTORE_END - RESTORE_START))
RPO_MS=$((FAILURE_TS - BACKUP_START))

cat > "${DRILL_DIR}/report.md" <<EOF
# Recovery drill report

- Дата: $(date -Is)
- БД: ${DB_NAME}, пользователь: ${DB_USER}
- Архив: ${DUMP_FILE} (${DUMP_SIZE})
- Дамп: pg_dump -Fc, занял ~$(ms_to_sec $((BACKUP_END - BACKUP_START))) c

## RTO (Recovery Time Objective)
- Момент сбоя: $(date -d "@$((FAILURE_TS/1000))" -Is)
- Подтверждённое восстановление: $(date -d "@$((VERIFY_TS/1000))" -Is)
- **Фактический RTO: $(ms_to_sec ${RTO_MS}) c** (drop + recreate + pg_restore + проверка подписи)
- в том числе сам pg_restore: ~$(ms_to_sec ${RESTORE_MS}) c

## RPO (Recovery Point Objective)
- Точка восстановления = начало снимка pg_dump: $(date -d "@$((BACKUP_START/1000))" -Is)
- Сбой: $(date -d "@$((FAILURE_TS/1000))" -Is)
- **Возраст точки восстановления в момент сбоя: $(ms_to_sec ${RPO_MS}) c** — 25 «пост-бэкапных» строк потеряны
- При периодических бэкапах возраст точки достигает интервала между запусками ПЛЮС длительности дампа

## Результат
- Подписи до/после: СОВПАДАЮТ
- Строки: customers=50, orders=500 (исходное состояние)
EOF

echo
echo "============================================"
echo " DRILL ПРОЙДЕН УСПЕШНО"
echo " RTO: $(ms_to_sec ${RTO_MS}) c | RPO: $(ms_to_sec ${RPO_MS}) c | архив: ${DUMP_SIZE}"
echo " Отчёт: ${DRILL_DIR}/report.md"
echo "============================================"
