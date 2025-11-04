#!/bin/bash

# Скрипт установки Beyond Compare
set -e

echo "Начало установки Beyond Compare..."

# Создаем временную директорию
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "1. Загрузка и добавление GPG ключа..."
wget -q https://www.scootersoftware.com/DEB-GPG-KEY-scootersoftware.asc
sudo cp DEB-GPG-KEY-scootersoftware.asc /etc/apt/trusted.gpg.d/
echo "✓ GPG ключ добавлен"

echo "2. Добавление репозитория..."
wget -q https://www.scootersoftware.com/scootersoftware.list
sudo cp scootersoftware.list /etc/apt/sources.list.d/
echo "✓ Репозиторий добавлен"

echo "3. Обновление списка пакетов..."
sudo apt update

echo "4. Установка Beyond Compare..."
sudo apt install -y bcompare

echo "5. Очистка временных файлов..."
cd /
rm -rf "$TEMP_DIR"

cd /usr/lib/beyondcompare/
sudo sed -i "s/keexjEP3t4Mue23hrnuPtY4TdcsqNiJL-5174TsUdLmJSIXKfG2NGPwBL6vnRPddT7tH29qpkneX63DO9ECSPE9rzY1zhThHERg8lHM9IBFT+rVuiY823aQJuqzxCKIE1bcDqM4wgW01FH6oCBP1G4ub01xmb4BGSUG6ZrjxWHJyNLyIlGvOhoY2HAYzEtzYGwxFZn2JZ66o4RONkXjX0DF9EzsdUef3UAS+JQ+fCYReLawdjEe6tXCv88GKaaPKWxCeaUL9PejICQgRQOLGOZtZQkLgAelrOtehxz5ANOOqCaJgy2mJLQVLM5SJ9Dli909c5ybvEhVmIC0dc9dWH+/N9KmiLVlKMU7RJqnE+WXEEPI1SgglmfmLc1yVH7dqBb9ehOoKG9UE+HAE1YvH1XX2XVGeEqYUY-Tsk7YBTz0WpSpoYyPgx6Iki5KLtQ5G-aKP9eysnkuOAkrvHU8bLbGtZteGwJarev03PhfCioJL4OSqsmQGEvDbHFEbNl1qJtdwEriR+VNZts9vNNLk7UGfeNwIiqpxjk4Mn09nmSd8FhM4ifvcaIbNCRoMPGl6KU12iseSe+w+1kFsLhX+OhQM8WXcWV10cGqBzQE9OqOLUcg9n0krrR3KrohstS9smTwEx9olyLYppvC0p5i7dAx2deWvM1ZxKNs0BvcXGukR+/g" BCompare


echo "=========================================="
echo "Beyond Compare успешно установлен!"
echo "Запустите программу командой: bcompare"
echo "=========================================="