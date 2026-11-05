#!/usr/bin/env bash
set -Eeuo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PGPORT="${PGPORT:-5434}"
SOURCE_DB="${SOURCE_DB:-bsbd}"
TARGET_DB="bsbd2"
ADMIN_DB="${ADMIN_DB:-postgres}"

command -v psql >/dev/null || { echo "Ошибка: не найден psql" >&2; exit 1; }
command -v createdb >/dev/null || { echo "Ошибка: не найден createdb" >&2; exit 1; }

if ! psql -X -v ON_ERROR_STOP=1 -d "$ADMIN_DB" -Atqc \
    "SELECT 1 FROM pg_database WHERE datname = '$SOURCE_DB'" | grep -qx 1; then
    echo "Ошибка: исходная БД $SOURCE_DB не найдена. Сначала разверните ЛР1." >&2
    exit 1
fi

if psql -X -v ON_ERROR_STOP=1 -d "$ADMIN_DB" -Atqc \
    "SELECT 1 FROM pg_database WHERE datname = '$TARGET_DB'" | grep -qx 1; then
    echo "База $TARGET_DB уже существует. Данные не удаляются."
else
    echo "Создаю $TARGET_DB как копию $SOURCE_DB ..."
    createdb --template "$SOURCE_DB" "$TARGET_DB" || {
        echo "Копирование не удалось. Закройте подключения к $SOURCE_DB и повторите запуск." >&2
        exit 1
    }
fi

for file in 00_setup.sql 01_security_definer.sql 03_check_trigger.sql; do
    echo "Выполняю $file ..."
    psql -X -v ON_ERROR_STOP=1 -d "$TARGET_DB" -f "$HERE/$file"
done

echo "Проверяю созданные SECURITY DEFINER-функции"
psql -X -v ON_ERROR_STOP=1 -d "$TARGET_DB" -c \
    "SELECT p.proname, pg_get_userbyid(p.proowner) AS owner, p.prosecdef AS security_definer FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='app' AND p.proname IN ('enroll_student','assign_grade','update_student_status') ORDER BY p.proname;"

echo "Развёртывание завершено. Тесты: psql -X -v ON_ERROR_STOP=1 -d bsbd2 -f '$HERE/02_tests.sql'"
echo "Замеры: psql -X -v ON_ERROR_STOP=1 -d bsbd2 -f '$HERE/03_benchmark.sql'"
