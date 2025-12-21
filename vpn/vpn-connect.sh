#!/bin/bash

CONFIG_FILE="$1"

if [ -z "$CONFIG_FILE" ]; then
    echo "Использование: ./vpn-connect.sh ФАЙЛ.ovpn"
    echo ""
    echo "Доступные конфиги:"
    ls -1 *.ovpn 2>/dev/null || echo "Нет .ovpn файлов в текущей директории"
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Ошибка: файл $CONFIG_FILE не найден"
    exit 1
fi

# Определяем ОС
OS=$(uname -s)

case "$OS" in
    Linux*)
        echo "Запуск OpenVPN на Linux..."

        # Проверяем установлен ли OpenVPN
        if ! command -v openvpn &> /dev/null; then
            echo "Установка OpenVPN..."

            # Для Ubuntu/Debian
            if command -v apt &> /dev/null; then
                sudo apt update
                sudo apt install -y openvpn resolvconf
            # Для CentOS/RHEL
            elif command -v yum &> /dev/null; then
                sudo yum install -y openvpn
            # Для Arch
            elif command -v pacman &> /dev/null; then
                sudo pacman -S openvpn
            else
                echo "Не удалось определить пакетный менеджер"
                exit 1
            fi
        fi

        # Запускаем OpenVPN
        sudo openvpn --config "$CONFIG_FILE" --daemon
        echo "OpenVPN запущен в фоновом режиме"
        echo "Логи: sudo tail -f /var/log/syslog"
        ;;

    MINGW*|MSYS*|CYGWIN*)
        echo "Windows система обнаружена"
        echo ""
        echo "Для подключения:"
        echo "1. Установите OpenVPN GUI с https://openvpn.net/"
        echo "2. Поместите файл $CONFIG_FILE в C:\\Users\\ВАШЕ_ИМЯ\\OpenVPN\\config"
        echo "3. Запустите OpenVPN GUI и подключитесь"
        ;;

    Darwin*)
        echo "macOS система обнаружена"
        echo ""
        echo "Для подключения:"
        echo "1. Установите Tunnelblick с https://tunnelblick.net/"
        echo "2. Двойной клик по файлу $CONFIG_FILE"
        echo "3. Нажмите 'Connect' в Tunnelblick"
        ;;

    *)
        echo "Неизвестная операционная система: $OS"
        echo "Ручная установка OpenVPN: https://openvpn.net/"
        ;;
esac

# Проверка подключения
check_connection() {
    echo "Проверка подключения..."
    sleep 5

    if ping -c 1 -W 2 10.8.0.1 &> /dev/null; then
        echo "✓ Подключение к VPN установлено"
        echo "Ваш IP в VPN: $(ip addr show tun0 2>/dev/null | grep 'inet ' | awk '{print $2}' || echo 'не определен')"
    else
        echo "✗ Не удалось подключиться к VPN"
        echo "Проверьте:"
        echo "1. Файл конфигурации"
        echo "2. Доступность порта на сервере"
        echo "3. Правила firewall"
    fi
}

# Запускаем проверку для Linux
if [ "$OS" = "Linux" ]; then
    check_connection
fi