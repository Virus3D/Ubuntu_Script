#!/bin/bash
# Полная установка OpenVPN сервера на Ubuntu

set -e  # Прерывать при ошибках

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка прав
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

# Конфигурационные переменные
VPN_PORT="1194"
VPN_PROTO="udp"
VPN_SUBNET="10.8.0.0"
VPN_SERVER="10.8.0.1"
VPN_NETMASK="255.255.255.0"
DNS1="8.8.8.8"
DNS2="8.8.4.4"
SERVER_NAME="server"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
BACKUP_DIR="/root/vpn-backup-$(date +%Y%m%d_%H%M%S)"

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
success() { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${BLUE}[i] $1${NC}"; }

# Функция бэкапа существующей конфигурации
backup_existing() {
    if [ -d "/etc/openvpn" ] && [ "$(ls -A /etc/openvpn 2>/dev/null)" ]; then
        log "Создание бэкапа текущей конфигурации..."
        mkdir -p "$BACKUP_DIR"

        # Копируем важные файлы
        [ -d "/etc/openvpn" ] && cp -r /etc/openvpn "$BACKUP_DIR/" 2>/dev/null
        [ -f "/etc/ufw/before.rules" ] && cp /etc/ufw/before.rules "$BACKUP_DIR/"
        [ -f "/etc/sysctl.conf" ] && cp /etc/sysctl.conf "$BACKUP_DIR/"

        # Сохраняем сертификаты если есть
        if [ -d "$EASY_RSA_DIR/pki" ]; then
            tar -czf "$BACKUP_DIR/pki-backup.tar.gz" -C "$EASY_RSA_DIR" pki/
        fi

        log "Бэкап создан: $BACKUP_DIR"
    fi
}

# Функция очистки старой конфигурации
cleanup_old_config() {
    log "Очистка старой конфигурации..."

    # Останавливаем сервисы
    systemctl stop openvpn@server 2>/dev/null || true
    systemctl disable openvpn@server 2>/dev/null || true

    # Удаляем конфигурацию OpenVPN
    rm -rf /etc/openvpn/server.conf 2>/dev/null
    rm -rf /etc/openvpn/client-configs 2>/dev/null
}

# Функция установки пакетов
install_packages() {
    log "Обновление и установка пакетов..."

    # Обновляем систему
    apt update && apt upgrade -y

    # Устанавливаем основные пакеты
    apt install -y openvpn easy-rsa curl wget

    # Проверяем что OpenVPN установился
    if ! command -v openvpn >/dev/null; then
        error "Не удалось установить OpenVPN"
        exit 1
    fi
}

# Настройка Easy-RSA
setup_easy_rsa() {
    log "Настройка инфраструктуры ключей (PKI)..."

    # 1. Создаем и настраиваем директорию Easy-RSA
    mkdir -p "$EASY_RSA_DIR"

    # Копируем easy-rsa если не скопировано
    if [ ! -f "$EASY_RSA_DIR/easyrsa" ]; then
        cp -r /usr/share/easy-rsa/* "$EASY_RSA_DIR/" 2>/dev/null || true
        chmod +x "$EASY_RSA_DIR/"*.sh 2>/dev/null || true
    fi

    cd "$EASY_RSA_DIR"

    # 2. Инициализируем PKI (очищаем старое при переустановке)
    if [ -d "pki" ]; then
        warn "Обнаружена старая PKI. Очистка..."
        ./easyrsa init-pki
    else
        ./easyrsa init-pki
    fi

    # 3. Создаем и настраиваем файл 'vars' для автоматической генерации
    # Это ключевое отличие: используем встроенную команду для создания шаблона
    if [ ! -f "vars" ]; then
        ./easyrsa make-vars > vars
    fi

    # Теперь редактируем файл 'vars', задавая нужные параметры
    cat > vars << 'EOF'
set_var EASYRSA_DN             "org"
set_var EASYRSA_REQ_COUNTRY    "RU"
set_var EASYRSA_REQ_PROVINCE   "Moscow"
set_var EASYRSA_REQ_CITY       "Moscow"
set_var EASYRSA_REQ_ORG        "OpenVPN"
set_var EASYRSA_REQ_EMAIL      "admin@example.com"
set_var EASYRSA_REQ_OU         "IT"
set_var EASYRSA_KEY_SIZE       2048
set_var EASYRSA_ALGO           rsa
set_var EASYRSA_CA_EXPIRE      3650
set_var EASYRSA_CERT_EXPIRE    1080
set_var EASYRSA_DIGEST         "sha256"
EOF

    # 4. Генерируем корневой сертификат (CA) в ПАКЕТНОМ РЕЖИМЕ
    # Это решает ошибку "Illegal option -o echo". Флаг 'nopass' делает ключ без пароля.
    log "Генерация корневого сертификата CA (это может занять момент)..."
    echo -e "\n" | ./easyrsa --batch build-ca nopass > /dev/null 2>&1

    # Проверяем, что CA создался
    if [ ! -f "pki/ca.crt" ]; then
        error "Не удалось создать корневой сертификат CA. Проверьте права и наличие openssl."
        exit 1
    fi
    success "Корневой сертификат CA создан: pki/ca.crt"

    # 5. Генерируем сертификат и ключ для сервера
    log "Создание сертификата для сервера '$SERVER_NAME'..."
    ./easyrsa --batch gen-req "$SERVER_NAME" nopass
    ./easyrsa --batch sign-req server "$SERVER_NAME"

    if [ ! -f "pki/issued/$SERVER_NAME.crt" ]; then
        error "Не удалось создать сертификат сервера."
        exit 1
    fi
    success "Сертификат сервера создан: pki/issued/$SERVER_NAME.crt"

    # 6. Генерируем параметры Диффи-Хеллмана (это долгая операция)
    log "Генерация параметров Диффи-Хеллмана (DH). Это займет несколько минут..."
    ./easyrsa --batch gen-dh
    success "Параметры DH созданы: pki/dh.pem"

    # 7. Генерируем ключ TLS-auth для дополнительной безопасности
    log "Создание статического TLS-ключа..."
    openvpn --genkey tls-crypt pki/ta.key
    success "TLS-ключ создан: pki/ta.key"

    log "Генерация всех ключей и сертификатов успешно завершена."
}

# Настройка сервера OpenVPN
setup_openvpn_server() {
    log "Настройка сервера OpenVPN..."

    # Создаем директории
    mkdir -p /etc/openvpn/server
    mkdir -p /etc/openvpn/client-configs/files
    mkdir -p /etc/openvpn/client-configs/keys
    mkdir -p /var/log/openvpn

    # Копируем файлы сертификатов
    cp "$EASY_RSA_DIR/pki/ca.crt" /etc/openvpn/
    cp "$EASY_RSA_DIR/pki/issued/$SERVER_NAME.crt" /etc/openvpn/server/
    cp "$EASY_RSA_DIR/pki/private/$SERVER_NAME.key" /etc/openvpn/server/
    cp "$EASY_RSA_DIR/pki/dh.pem" /etc/openvpn/
    cp "$EASY_RSA_DIR/pki/ta.key" /etc/openvpn/

    # Создаем конфигурационный файл сервера
    cat > /etc/openvpn/server.conf << EOF
port $VPN_PORT
proto $VPN_PROTO
dev tun
ca ca.crt
cert server/$SERVER_NAME.crt
key server/$SERVER_NAME.key
dh dh.pem
server $VPN_SUBNET $VPN_NETMASK
ifconfig-pool-persist /var/log/openvpn/ipp.txt

push "route $VPN_SUBNET $VPN_NETMASK"
push "dhcp-option DNS $VPN_SERVER"  # DNS сервера VPN

keepalive 10 120
tls-auth ta.key 0
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/status.log
log-append /var/log/openvpn/openvpn.log
verb 3
explicit-exit-notify 1
client-to-client
duplicate-cn
EOF

    # Включаем IP форвардинг - ИСПРАВЛЕННЫЙ БЛОК
    log "Настройка IP форвардинга..."

    # Создаем /etc/sysctl.conf если его нет
    if [ ! -f /etc/sysctl.conf ]; then
        warn "Файл /etc/sysctl.conf не найден, создаем..."
        touch /etc/sysctl.conf
        echo "# System control parameters" > /etc/sysctl.conf
    fi

    # Убедимся что опция включена
    if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf; then
        # Разкомментируем если закомментировано
        sed -i 's/^#net.ipv4.ip_forward/net.ipv4.ip_forward/g' /etc/sysctl.conf
        # Устанавливаем значение 1
        sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
    else
        # Добавляем опцию если её нет
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi

    # Также проверяем sysctl.d
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf

    # Применяем изменения
    sysctl -p /etc/sysctl.conf 2>/dev/null || true
    sysctl -p /etc/sysctl.d/99-openvpn.conf 2>/dev/null || true

    # Проверяем что форвардинг включен
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        warn "IP форвардинг не включен, принудительно включаем..."
        echo 1 > /proc/sys/net/ipv4/ip_forward
    fi
}

# Создание утилит управления
create_management_tools() {
    log "Создание утилит управления..."

    # Скрипт добавления клиента
    cat > /usr/local/bin/vpn-add-client << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Использование: vpn-add-client ИМЯ_КЛИЕНТА"
    exit 1
fi

CLIENT_NAME="$1"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

cd "$EASY_RSA_DIR"
./easyrsa gen-req "$CLIENT_NAME" nopass
echo "yes" | ./easyrsa sign-req client "$CLIENT_NAME"

# Создаем конфиг клиента
cat > "/etc/openvpn/client-configs/files/$CLIENT_NAME.ovpn" << CLIENTEOF
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
verb 3
key-direction 1

<ca>
$(cat pki/ca.crt)
</ca>

<cert>
$(cat pki/issued/$CLIENT_NAME.crt)
</cert>

<key>
$(cat pki/private/$CLIENT_NAME.key)
</key>

<tls-auth>
$(cat pki/ta.key)
</tls-auth>
CLIENTEOF

echo "Клиент $CLIENT_NAME создан!"
echo "Конфиг: /etc/openvpn/client-configs/files/$CLIENT_NAME.ovpn"
echo "Скопируйте его на клиентскую машину"
EOF

    chmod +x /usr/local/bin/vpn-add-client

    # Скрипт проверки статуса
    cat > /usr/local/bin/vpn-status << 'EOF'
#!/bin/bash
echo "=== Статус OpenVPN сервера ==="
systemctl status openvpn@server --no-pager -l
echo ""
echo "=== Подключенные клиенты ==="
[ -f /var/log/openvpn/status.log ] && cat /var/log/openvpn/status.log || echo "Файл статуса не найден"
EOF

    chmod +x /usr/local/bin/vpn-status

    # Создаем первого клиента
    log "Создание первого клиента 'admin'..."
    /usr/local/bin/vpn-add-client admin
}

# Запуск сервисов
start_services() {
    log "Запуск сервисов..."

    # Перезагружаем демон systemd
    systemctl daemon-reload

    # Включаем и запускаем OpenVPN
    systemctl enable openvpn@server
    systemctl start openvpn@server

    # Проверяем что сервис запустился
    sleep 2
    if systemctl is-active --quiet openvpn@server; then
        log "OpenVPN сервер успешно запущен"
    else
        error "Не удалось запустить OpenVPN сервер"
        journalctl -u openvpn@server -n 20 --no-pager
    fi
}

# Основной процесс установки
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}  Установка/переустановка OpenVPN сервера ${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Бэкап старой конфигурации
    backup_existing

    # Очистка старой конфигурации
    read -p "Очистить старую конфигурацию OpenVPN? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_old_config
    else
        warn "Продолжение без очистки (может привести к конфликтам)"
    fi

    # Устанавливаем пакеты
    install_packages

    # Настраиваем Easy-RSA
    setup_easy_rsa

    # Настраиваем сервер OpenVPN
    setup_openvpn_server

    # Создаем утилиты управления
    create_management_tools

    # Запускаем сервисы
    start_services

    # Вывод итоговой информации
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Установка завершена успешно!${NC}"
    echo -e "${BLUE}Сервер OpenVPN настроен и запущен${NC}"
    echo ""
    echo -e "${YELLOW}Основные данные:${NC}"
    echo "  Порт: $VPN_PORT/$VPN_PROTO"
    echo "  Подсеть VPN: $VPN_SUBNET/24"
    echo "  Публичный IP: $(curl -s ifconfig.me || echo 'определите отдельно')"
    echo ""
    echo -e "${YELLOW}Управление:${NC}"
    echo "  Добавить клиента: vpn-add-client ИМЯ"
    echo "  Проверить статус: vpn-status"
    echo "  Перезапустить VPN: systemctl restart openvpn@server"
    echo "  Логи: journalctl -u openvpn@server -f"
    echo ""
    echo -e "${YELLOW}Первый клиент:${NC}"
    echo "  Конфиг: /etc/openvpn/client-configs/files/admin.ovpn"
    echo ""
    echo -e "${GREEN}Скопируйте .ovpn файл на клиентские устройства${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Запускаем основную функцию
main