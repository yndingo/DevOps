#!/bin/sh
# выйти в корень проекта, откуда лежит .env и compose.yaml
set -eu
cd "$(dirname "$0")/.."     

#Защита от отсутствия .env 
if [ ! -f .env ]; then
    echo "ERROR: .env не найден. Скопируйте .env.example -> .env" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

# 1) drop + create через базу-«диспетчер» postgres:
docker compose exec -T db psql -X -v ON_ERROR_STOP=1 \
  -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE $POSTGRES_DB WITH (FORCE);" \
  -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"

# 2) прогон init-файлов (/db — путь ВНУТРИ контейнера):
docker compose exec -T db psql -X -v ON_ERROR_STOP=1 \
  -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -f /db/init/01_schema.sql
docker compose exec -T db psql -X -v ON_ERROR_STOP=1 \
  -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -f /db/init/02_seed.sql


# 3) финальное сообщение-подтверждение
echo "[reseed] OK: ${POSTGRES_DB} в исходном состоянии (50 клиентов, 500 заказов)"
