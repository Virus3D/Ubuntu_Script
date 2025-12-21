## Установка сервера:

``` bash
# 1. Скачать скрипт
wget https://example.com/vpn-server-setup.sh

# 2. Сделать исполняемым
chmod +x vpn-server-setup.sh

# 3. Запустить
sudo ./vpn-server-setup.sh
```

## Управление клиентами:

```bash
# Запустить менеджер
sudo vpn-manager

# Или использовать команды напрямую
sudo vpn-add-client user1
sudo vpn-add-client user2
sudo vpn-revoke-client user1  # отозвать доступ
```

## На клиентской машине:

```bash
# 1. Скачать .ovpn файл с сервера
scp user@server:/etc/openvpn/client-configs/files/user1.ovpn .

# 2. Подключиться
./vpn-connect.sh user1.ovpn
```