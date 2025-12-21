#!/bin/bash

echo "Быстрая установка OpenVPN сервера"
echo "================================="

# Скачиваем основной скрипт
wget -O vpn-server-setup.sh https://raw.githubusercontent.com/your-repo/vpn-server-setup.sh 2>/dev/null || \
curl -o vpn-server-setup.sh https://raw.githubusercontent.com/your-repo/vpn-server-setup.sh

if [ ! -f "vpn-server-setup.sh" ]; then
    echo "Создание локального скрипта..."
    # Здесь должен быть полный скрипт установки
    # Временно копируем из текущего файла
    cp $0 vpn-server-setup.sh
fi

# Делаем исполняемым и запускаем
chmod +x vpn-server-setup.sh
sudo ./vpn-server-setup.sh

# После установки скачиваем менеджер клиентов
echo "Установка менеджера клиентов..."
sudo wget -O /usr/local/bin/vpn-manager https://raw.githubusercontent.com/your-repo/vpn-client-manager.sh
sudo chmod +x /usr/local/bin/vpn-manager

echo "Установка завершена!"
echo "Используйте команды:"
echo "  sudo vpn-manager - меню управления клиентами"
echo "  sudo vpn-add-client ИМЯ - добавить клиента"
echo "  sudo systemctl status openvpn@server - статус сервера"