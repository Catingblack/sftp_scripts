#!/bin/bash

# SFTP тестер с JSON выводом (только парольная аутентификация)
# Использование: ./sftp_check.sh <host> <user> <password> [port]
set -x

HOST="${1:-sftp.example.com}"
USER="${2:-testuser}"
PASSWORD="${3:-}"
PORT="${4:-22}"

# Функция для JSON вывода
json_output() {
    local status="$1"
    local message="$2"
    local exit_code="$3"
    
    cat << EOF
{
  "status": "$status",
  "message": "$message",
  "host": "$HOST",
  "user": "$USER",
  "port": "$PORT",
  "timestamp": "$(date -Iseconds)",
  "exit_code": $exit_code
}
EOF
    exit $exit_code
}

# Проверяем обязательные параметры
if [ -z "$PASSWORD" ]; then
    json_output "error" "Пароль обязателен. Использование: $0 <host> <user> <password> [port]" 2
fi

# Проверяем зависимость sshpass
if ! command -v sshpass &> /dev/null; then
    json_output "error" "sshpass не установлен. Установите: sudo apt-get install sshpass (Ubuntu/Debian) или sudo yum install sshpass (RHEL/CentOS)" 3
fi

# Базовая команда SFTP
TEST_CMD="sftp -oPort=$PORT -oStrictHostKeyChecking=no -oConnectTimeout=10 -oStrictHostKeyChecking=no -oPasswordAuthentication=yes -oIdentitiesOnly=yes"

echo "Проверка SFTP подключения к $HOST:$PORT пользователь $USER..." >&2

# Выполняем тест с паролем
if sshpass -p "$PASSWORD" $TEST_CMD "${USER}@${HOST}" <<< "bye" >/dev/null 2>&1; then
    json_output "success" "SFTP connection successful" 0
else
    json_output "failed" "SFTP connection failed. Возможные причины: 1) Неправильный пароль, 2) Хост недоступен, 3) Порт $PORT закрыт, 4) Пользователь не существует" 1
fi