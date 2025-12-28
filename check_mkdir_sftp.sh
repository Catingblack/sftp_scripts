#!/bin/bash

# SFTP тестер создания и удаления директории с JSON выводом
# Использование: ./sftp_create_delete_test.sh <host> <user> <password> [port] [remote_path]

HOST="${1:-sftp.example.com}"
USER="${2:-testuser}"
PASSWORD="${3:-}"
PORT="${4:-22}"
REMOTE_PATH="${5:-/tmp/test_$(date +%Y%m%d_%H%M%S)_$$}"

# Функция для JSON вывода
json_output() {
    local status="$1"
    local message="$2"
    local exit_code="$3"
    local debug_info="$4"
    local created_path="$5"
    
    debug_info_escaped=$(echo "$debug_info" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/\t/\\t/g')
    
    cat << EOF
{
  "status": "$status",
  "message": "$message",
  "host": "$HOST",
  "user": "$USER",
  "port": "$PORT",
  "remote_path": "$REMOTE_PATH",
  "created_path": "$created_path",
  "timestamp": "$(date -Iseconds)",
  "exit_code": $exit_code,
  "debug_info": "$debug_info_escaped"
}
EOF
    exit $exit_code
}

# Проверяем обязательные параметры
if [ -z "$PASSWORD" ]; then
    json_output "error" "Пароль обязателен. Использование: $0 <host> <user> <password> [port] [remote_path]" 2 "" ""
fi

if ! command -v sshpass &> /dev/null; then
    json_output "error" "sshpass не установлен" 3 "" ""
fi

SFTP_CMD="sftp -vvv -oPort=$PORT -oStrictHostKeyChecking=no -oConnectTimeout=10 -oPasswordAuthentication=yes -oIdentitiesOnly=yes"

echo "Тестирование создания и удаления директории на SFTP..." >&2

# Создаем временный файл для логов
TEMP_LOG=$(mktemp /tmp/sftp_dir_test_XXXXXX.log)

# Полный цикл: создание, проверка, удаление
SFTP_COMMANDS=$(cat << EOF
# Пытаемся создать директорию
mkdir $REMOTE_PATH

# Проверяем, что директория создана
ls -la $(dirname "$REMOTE_PATH")/ | grep "$(basename "$REMOTE_PATH")"

# Создаем тестовый файл внутри директории для проверки прав на запись
cd $REMOTE_PATH
put /etc/hostname test_file_$(date +%s).txt
ls -la

# Удаляем тестовый файл
rm test_file_*.txt

# Возвращаемся и удаляем директорию
cd /
rmdir $REMOTE_PATH
bye
EOF
)

# Выполняем команды
sshpass -p "$PASSWORD" $SFTP_CMD "${USER}@${HOST}" <<< "$SFTP_COMMANDS" > "$TEMP_LOG" 2>&1
EXIT_CODE=$?

DEBUG_OUTPUT=$(cat "$TEMP_LOG" 2>/dev/null || echo "Не удалось прочитать лог-файл")
rm -f "$TEMP_LOG"

if [ $EXIT_CODE -eq 0 ]; then
    if echo "$DEBUG_OUTPUT" | grep -q "mkdir.*$REMOTE_PATH" || echo "$DEBUG_OUTPUT" | grep -q "$(basename "$REMOTE_PATH")"; then
        json_output "success" "Директория успешно создана, проверена и удалена" 0 "$DEBUG_OUTPUT" "$REMOTE_PATH"
    else
        json_output "partial_success" "Операции выполнены, но создание директории не подтверждено" 0 "$DEBUG_OUTPUT" "$REMOTE_PATH"
    fi
else
    ERROR_MSG="Ошибка при работе с директорией"
    if echo "$DEBUG_OUTPUT" | grep -qi "Permission denied"; then
        ERROR_MSG="Нет прав на создание директории"
    elif echo "$DEBUG_OUTPUT" | grep -qi "No such file or directory"; then
        ERROR_MSG="Родительская директория не существует"
    fi
    json_output "failed" "$ERROR_MSG" 1 "$DEBUG_OUTPUT" ""
fi
