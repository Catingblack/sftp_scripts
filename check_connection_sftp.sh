#!/bin/bash

# SFTP тестер с JSON выводом (только парольная аутентификация)
# Использование: ./sftp_check.sh <host> <user> <password> [port]
# set -x  # Комментируем для продакшена, чтобы не выводить отладку

HOST="${1:-sftp.example.com}"
USER="${2:-testuser}"
PASSWORD="${3:-}"
PORT="${4:-22}"

# Функция для JSON вывода с поддержкой многострочного debug_info
json_output() {
    local status="$1"
    local message="$2"
    local exit_code="$3"
    local debug_info="$4"
    
    # Экранируем специальные символы для JSON
    debug_info_escaped=$(echo "$debug_info" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/\t/\\t/g')
    
    cat << EOF
{
  "status": "$status",
  "message": "$message",
  "host": "$HOST",
  "user": "$USER",
  "port": "$PORT",
  "timestamp": "$(date -Iseconds)",
  "exit_code": $exit_code,
  "debug_info": "$debug_info_escaped"
}
EOF
    exit $exit_code
}

# Проверяем обязательные параметры
if [ -z "$PASSWORD" ]; then
    json_output "error" "Пароль обязателен. Использование: $0 <host> <user> <password> [port]" 2 ""
fi

# Проверяем зависимость sshpass
if ! command -v sshpass &> /dev/null; then
    json_output "error" "sshpass не установлен. Установите: sudo apt-get install sshpass (Ubuntu/Debian) или sudo yum install sshpass (RHEL/CentOS)" 3 ""
fi

# Базовая команда SFTP - исправляем дублирование
TEST_CMD="sftp -v -oPort=$PORT -oStrictHostKeyChecking=no -oConnectTimeout=10 -oPasswordAuthentication=yes -oIdentitiesOnly=yes"

echo "Проверка SFTP подключения к $HOST:$PORT пользователь $USER..." >&2

# Создаем временный файл для логов
TEMP_LOG=$(mktemp /tmp/sftp_debug_XXXXXX.log)

# Выполняем тест с паролем и записываем ВЕСЬ вывод в лог
sshpass -p "$PASSWORD" $TEST_CMD "${USER}@${HOST}" <<< "bye" > "$TEMP_LOG" 2>&1
EXIT_CODE=$?

# Получаем содержимое лога
DEBUG_OUTPUT=$(cat "$TEMP_LOG" 2>/dev/null || echo "Не удалось прочитать лог-файл")

# Удаляем временный файл
rm -f "$TEMP_LOG"

# Обрабатываем результат
if [ $EXIT_CODE -eq 0 ]; then
    json_output "success" "SFTP connection successful" 0 ""
else
    # Формируем подробное сообщение об ошибке
    ERROR_MSG="SFTP connection failed. Возможные причины: 1) Неправильный пароль, 2) Хост недоступен, 3) Порт $PORT закрыт, 4) Пользователь не существует"
    json_output "failed" "$ERROR_MSG" 1 "$DEBUG_OUTPUT"
fi
