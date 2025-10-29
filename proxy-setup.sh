#!/bin/bash

# Проверка прав суперпользователя
if [ "$UID" -ne 0 ]; then
    echo "Ошибка: запустите скрипт с sudo."
    exit 1
fi

# Проверка количества аргументов
if [ $# -ne 2 ]; then
    echo "Использование: sudo $0 <адрес_прокси> <порт>"
    echo "Пример: sudo $0 192.168.1.100 8080"
    echo "Отключение прокси: sudo $0 reset"
    exit 1
fi

if [ "$1" = "reset" ]; then
    echo "Отключаем прокси..."
    gsettings set org.gnome.system.proxy mode 'none'
    sed -i '/proxy/d' /etc/environment
    rm -f /etc/apt/apt.conf.d/95proxies
    echo "Прокси отключён."
    exit 0
fi

PROXY_HOST="$1"
PROXY_PORT="$2"

# Проверка корректности порта (число от 1 до 65535)
if ! [[ "$PROXY_PORT" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$PROXY_PORT" -gt 65535 ]; then
    echo "Ошибка: порт должен быть числом от 1 до 65535."
    exit 1
fi

echo "Настраиваем прокси: $PROXY_HOST:$PROXY_PORT"

# 1. Настройка через gsettings (для GNOME/рабочего стола)
echo "→ Устанавливаем прокси через gsettings..."
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.http host "$PROXY_HOST"
gsettings set org.gnome.system.proxy.http port "$PROXY_PORT"
gsettings set org.gnome.system.proxy.https host "$PROXY_HOST"
gsettings set org.gnome.system.proxy.https port "$PROXY_PORT"
gsettings set org.gnome.system.proxy.ftp host "$PROXY_HOST"
gsettings set org.gnome.system.proxy.ftp port "$PROXY_PORT"
gsettings set org.gnome.system.proxy.socks host "$PROXY_HOST"
gsettings set org.gnome.system.proxy.socks port "$PROXY_PORT"

# 2. Настройка переменных окружения (/etc/environment)
echo "→ Добавляем переменные окружения в /etc/environment..."
cat << EOF >> /etc/environment
http_proxy="http://$PROXY_HOST:$PROXY_PORT/"
https_proxy="http://$PROXY_HOST:$PROXY_PORT/"
ftp_proxy="http://$PROXY_HOST:$PROXY_PORT/"
no_proxy="localhost,127.0.0.1,localaddress,.localdomain.com"
HTTP_PROXY="http://$PROXY_HOST:$PROXY_PORT/"
HTTPS_PROXY="http://$PROXY_HOST:$PROXY_PORT/"
FTP_PROXY="http://$PROXY_HOST:$PROXY_PORT/"
NO_PROXY="localhost,127.0.0.1,localaddress,.localdomain.com"
EOF

# 3. Настройка apt (/etc/apt/apt.conf.d/95proxies)
echo "→ Настраиваем apt..."
cat << EOF > /etc/apt/apt.conf.d/95proxies
Acquire::http::proxy "http://$PROXY_HOST:$PROXY_PORT/";
Acquire::https::proxy "http://$PROXY_HOST:$PROXY_PORT/";
Acquire::ftp::proxy "http::$PROXY_HOST:$PROXY_PORT/";
EOF

echo "Готово! Прокси настроен."
echo ""
echo "Примечания:"
echo "- Для применения переменных окружения перезагрузите систему или выполните: source /etc/environment"
echo "- Для немедленного применения настроек GNOME перезапустите сеанс входа."
echo "- Чтобы отключить прокси: sudo $0 reset"
