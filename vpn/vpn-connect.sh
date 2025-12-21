#!/bin/bash
# vpn-connect.sh - Улучшенный скрипт подключения OpenVPN клиента
# Поддержка: Linux, Windows (WSL), macOS

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE=""
ACTION="connect"
MODE="split"  # По умолчанию Split Tunnel
SERVICE_NAME="openvpn-split"
LOG_DIR="$HOME/.openvpn"
LOG_FILE="$LOG_DIR/connect.log"

# Функции для вывода
error() { echo -e "${RED}[ERROR] $1${NC}"; }
success() { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${BLUE}[i] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }

# Логирование
log() {
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Проверка режима конфига
check_config_mode() {
    local config="$1"
    if grep -q "redirect-gateway" "$config"; then
        echo "full"
    elif grep -q "^route " "$config"; then
        echo "split"
    else
        echo "unknown"
    fi
}

# Преобразование конфига в Split Tunnel
ensure_split_tunnel() {
    local config="$1"
    local backup="${config}.backup.$(date +%Y%m%d_%H%M%S)"

    # Создаем бэкап
    cp "$config" "$backup"

    # Удаляем полное перенаправление трафика
    sed -i '/redirect-gateway/d' "$config"
    sed -i '/push.*redirect-gateway/d' "$config"

    # Удаляем DNS серверы интернета
    sed -i '/dhcp-option DNS 8\.8\./d' "$config"
    sed -i '/dhcp-option DNS 1\.1\./d' "$config"

    # Добавляем только маршруты к VPN сети
    if ! grep -q "^route 10.8.0.0" "$config"; then
        sed -i '/^client/a route 10.8.0.0 255.255.255.0' "$config"
    fi

    # Добавляем блокировку DNS утечек
    if ! grep -q "block-outside-dns" "$config"; then
        sed -i '/^client/a block-outside-dns' "$config"
    fi

    # Устанавливаем DNS сервер VPN
    if ! grep -q "dhcp-option DNS 10.8.0.1" "$config"; then
        sed -i '/^client/a dhcp-option DNS 10.8.0.1' "$config"
    fi

    echo "Конфиг настроен для Split Tunnel"
    echo "Бэкап: $backup"
}

# Определение ОС
detect_os() {
    case "$(uname -s)" in
        Linux*)     OS="Linux" ;;
        Darwin*)    OS="macOS" ;;
        CYGWIN*|MINGW*|MSYS*) OS="Windows" ;;
        *)          OS="Unknown" ;;
    esac
    echo "$OS"
}

# Проверка зависимостей
check_dependencies() {
    OS=$(detect_os)

    if [ "$OS" = "Linux" ]; then
        if ! command -v openvpn >/dev/null; then
            warn "OpenVPN не установлен"
            read -p "Установить OpenVPN? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                info "Установка OpenVPN..."
                sudo apt update
                sudo apt install -y openvpn openvpn-systemd-resolved resolvconf
                success "OpenVPN установлен"
            else
                error "Требуется установить OpenVPN"
                exit 1
            fi
        fi
    fi
}

# Проверка Split Tunnel
check_split_tunnel() {
    echo "=== Проверка Split Tunnel ==="

    # Проверяем интерфейсы
    echo "1. Сетевые интерфейсы:"
    if ip link show tun0 >/dev/null 2>&1; then
        VPN_IP=$(ip addr show tun0 | grep -oP 'inet \K[\d.]+')
        success "✓ VPN интерфейс: tun0 ($VPN_IP)"
    else
        error "✗ VPN интерфейс не найден"
    fi

    echo ""
    echo "2. Маршруты:"
    echo "   Через VPN (tun0):"
    ip route show | grep "tun0" || echo "   Нет маршрутов через VPN"
    echo ""
    echo "   Основной шлюз:"
    ip route show | grep "default" | head -1

    echo ""
    echo "3. Проверка трафика:"
    echo -n "   VPN сервер (10.8.0.1): "
    ping -c 1 -W 1 10.8.0.1 >/dev/null 2>&1 && echo "✓ доступен" || echo "✗ недоступен"

    echo -n "   Интернет (8.8.8.8): "
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo "✓ доступен" || echo "✗ недоступен"

    echo ""
    echo "4. Внешний IP (должен быть ваш реальный, а не VPN):"
    YOUR_IP=$(curl -s --max-time 3 ifconfig.me)
    if [ -n "$YOUR_IP" ]; then
        echo "   Ваш IP: $YOUR_IP"
        if [[ "$YOUR_IP" =~ ^10\.8\. ]]; then
            warn "   ВНИМАНИЕ: Трафик идет через VPN! Это не Split Tunnel"
        else
            success "   ✓ Трафик идет через основной интерфейс"
        fi
    else
        warn "   Не удалось определить IP"
    fi
}

# Подключение к VPN
connect_vpn() {
    OS=$(detect_os)
    log "Подключение к VPN с конфигом: $CONFIG_FILE"

    # Проверяем и настраиваем Split Tunnel
    local current_mode=$(check_config_mode "$CONFIG_FILE")
    if [ "$current_mode" = "full" ]; then
        warn "Обнаружен Full Tunnel конфиг"
        read -p "Преобразовать в Split Tunnel? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            ensure_split_tunnel "$CONFIG_FILE"
        fi
    fi

    case "$OS" in
        Linux)
            info "Запуск OpenVPN на Linux (Split Tunnel)..."

            # Проверяем запущен ли уже VPN
            if pgrep -x "openvpn" >/dev/null; then
                warn "OpenVPN уже запущен"
                read -p "Перезапустить? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    sudo pkill openvpn 2>/dev/null || true
                    sleep 2
                else
                    info "Используйте 'sudo pkill openvpn' для остановки"
                    return
                fi
            fi

            # Запускаем в фоновом режиме
            sudo openvpn \
                --config "$CONFIG_FILE" \
                --daemon \
                --log "$LOG_DIR/openvpn.log" \
                --verb 3

            success "OpenVPN запущен"
            echo "Логи: $LOG_DIR/openvpn.log"

            # Проверяем подключение
            sleep 5
            check_split_tunnel
            ;;

        macOS)
            info "Для macOS с Split Tunnel:"
            echo ""
            echo "1. Установите Tunnelblick: https://tunnelblick.net/"
            echo "2. Откройте файл $CONFIG_FILE"
            echo "3. В настройках конфига выберите:"
            echo "   - 'Set DNS' → 'Do not set nameserver'"
            echo "   - 'Route all IPv4 traffic' → НЕ отмечено"
            ;;

        Windows)
            info "Для Windows используйте OpenVPN GUI"
            echo ""
            echo "1. Скачайте OpenVPN GUI: https://openvpn.net/community-downloads/"
            echo "2. Установите и запустите"
            echo "3. Поместите файл в: C:\\Users\\%USERNAME%\\OpenVPN\\config\\"
            echo "4. В конфиг файле УДАЛИТЬ строки:"
            echo "   - redirect-gateway def1"
            echo "   - dhcp-option DNS 8.8.8.8"
            echo "5. Добавить строки:"
            echo "   - route 10.8.0.0 255.255.255.0"
            echo "   - block-outside-dns"
            ;;

        *)
            error "Неподдерживаемая ОС: $OS"
            ;;
    esac
}

# Настройка автозапуска (только Linux)
setup_autostart() {
    OS=$(detect_os)

    if [ "$OS" != "Linux" ]; then
        error "Автозапуск поддерживается только на Linux"
        return 1
    fi

    if [ "$EUID" -ne 0 ]; then
        error "Для настройки автозапуска нужны права root"
        echo "Запустите: sudo $0 --config $CONFIG_FILE --install"
        return 1
    fi

    info "Настройка автозапуска Split Tunnel VPN..."

    # Сначала преобразуем конфиг
    ensure_split_tunnel "$CONFIG_FILE"

    # Копируем конфиг
    mkdir -p /etc/openvpn/client
    cp "$CONFIG_FILE" /etc/openvpn/client/split-tunnel.ovpn

    # Создаем systemd сервис для Split Tunnel
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=OpenVPN Split Tunnel Client
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/sbin/openvpn \\
    --daemon \\
    --config /etc/openvpn/client/split-tunnel.ovpn \\
    --log /var/log/openvpn-split.log \\
    --verb 3 \\
    --auth-nocache \\
    --connect-retry 5 60 \\
    --connect-retry-max 3
ExecStop=/usr/bin/pkill openvpn
Restart=on-failure
RestartSec=5
TimeoutStartSec=30

# Важно для Split Tunnel
Environment="OPENVPN_SPLIT_TUNNEL=1"

[Install]
WantedBy=multi-user.target
EOF

    # Создаем сервис для переподключения при смене сети
    cat > /etc/systemd/system/$SERVICE_NAME-restart.service << EOF
[Unit]
Description=Restart OpenVPN after network change
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart $SERVICE_NAME

[Install]
WantedBy=network-online.target
EOF

    # Включаем сервисы
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl enable $SERVICE_NAME-restart

    success "Сервис настроен"
    echo ""
    echo "Команды управления:"
    echo "  Запуск:        sudo systemctl start $SERVICE_NAME"
    echo "  Остановка:     sudo systemctl stop $SERVICE_NAME"
    echo "  Статус:        sudo systemctl status $SERVICE_NAME"
    echo "  Логи:          sudo journalctl -u $SERVICE_NAME -f"
    echo ""
    echo "Автозапуск включен при загрузке системы"
}

# Проверка статуса
check_status() {
    OS=$(detect_os)

    case "$OS" in
        Linux)
            if systemctl is-active $SERVICE_NAME >/dev/null 2>&1; then
                success "Split Tunnel сервис запущен"
                check_split_tunnel
            elif pgrep -x "openvpn" >/dev/null; then
                info "OpenVPN запущен вручную"
                check_split_tunnel
            else
                error "OpenVPN не запущен"
            fi
            ;;

        macOS|Windows)
            info "Проверьте подключение через GUI приложение"
            ;;
    esac
}

# Отключение VPN
disconnect_vpn() {
    OS=$(detect_os)

    case "$OS" in
        Linux)
            if systemctl is-active $SERVICE_NAME >/dev/null 2>&1; then
                info "Останавливаем Split Tunnel сервис..."
                sudo systemctl stop $SERVICE_NAME
                sudo systemctl disable $SERVICE_NAME 2>/dev/null || true
            fi

            info "Завершаем все процессы OpenVPN..."
            sudo pkill openvpn 2>/dev/null || true

            # Удаляем tun интерфейс
            sudo ip link delete tun0 2>/dev/null || true

            success "VPN отключен"
            echo "Интерфейс tun0 удален"
            ;;

        macOS|Windows)
            info "Отключите VPN через GUI приложение"
            ;;
    esac
}

# Показ справки
show_help() {
    echo -e "${CYAN}Использование: $0 [ОПЦИИ]${NC}"
    echo ""
    echo "Режим по умолчанию: Split Tunnel (только внутренние сети через VPN)"
    echo "Интернет остается на основном интерфейсе"
    echo ""
    echo "Опции:"
    echo "  -c, --config FILE    Конфигурационный файл .ovpn"
    echo "  -a, --action ACTION  Действие: connect, install, status, disconnect"
    echo "  -h, --help           Показать справку"
    echo ""
    echo "Примеры:"
    echo "  $0 client.ovpn                   # Подключиться с Split Tunnel"
    echo "  $0 -c client.ovpn -a install      # Настроить автозапуск (Linux)"
    echo "  $0 -c client.ovpn -a status       # Проверить статус"
    echo "  $0 -c client.ovpn -a disconnect   # Отключиться"
    echo ""
    echo "Быстрый запуск:"
    echo "  $0 client.ovpn                    # Подключиться с конфигом"
    echo ""
    echo "Логи: $LOG_DIR/"
}

# Парсинг аргументов
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -a|--action)
                ACTION="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                # Если первый аргумент без флага - это конфиг
                if [[ -z "$CONFIG_FILE" && "$1" == *.ovpn ]]; then
                    CONFIG_FILE="$1"
                else
                    error "Неизвестный аргумент: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Если не указан конфиг, ищем .ovpn файлы
    if [[ -z "$CONFIG_FILE" ]]; then
        OVPN_FILES=(*.ovpn)
        if [ ${#OVPN_FILES[@]} -eq 1 ] && [ -f "${OVPN_FILES[0]}" ]; then
            CONFIG_FILE="${OVPN_FILES[0]}"
        elif [ ${#OVPN_FILES[@]} -gt 1 ]; then
            error "Найдено несколько .ovpn файлов. Укажите явно:"
            ls -1 *.ovpn
            exit 1
        else
            error "Не указан конфигурационный файл .ovpn"
            show_help
            exit 1
        fi
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Файл не найден: $CONFIG_FILE"
        exit 1
    fi
}

# Основная функция
main() {
    parse_args "$@"

    echo -e "${CYAN}=== OpenVPN Split Tunnel Client ===${NC}"
    echo "ОС: $(detect_os)"
    echo "Конфиг: $CONFIG_FILE"
    echo "Действие: $ACTION"
    echo "Режим: Split Tunnel (интернет через основной интерфейс)"
    echo ""

    check_dependencies

    case "$ACTION" in
        connect)
            connect_vpn
            ;;
        install)
            setup_autostart
            ;;
        status)
            check_status
            ;;
        disconnect)
            disconnect_vpn
            ;;
        *)
            error "Неизвестное действие: $ACTION"
            show_help
            exit 1
            ;;
    esac

    log "Выполнено: $ACTION с конфигом $CONFIG_FILE"
}

# Запуск основной функции
main "$@"