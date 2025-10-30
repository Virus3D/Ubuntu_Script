#!/bin/bash

# ========================================================
# Скрипт развёртывания веб‑среды для разработки
# Ubuntu 25.10 | PHP-версия через переменную
# Автор: Ваш Имя
# Дата: 2025-10-29
# ========================================================

set -e  # Прекращать выполнение при ошибке

# --- Параметры ---
PHP_VERSION="8.4"           # Меняйте здесь: 8.2, 8.4 и т. п.

echo "🚀 Запуск скрипта развёртывания веб‑среды для разработки"
echo "PHP версия: $PHP_VERSION"

# --- Функции ---
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

dir_exists() {
    [ -d "$1" ]
}

# --- 1. Обновление системы ---
echo "🔁 Обновляем систему..."
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y
sudo apt autoremove -y && sudo apt clean

# --- 2. Базовые инструменты (если нет) ---
echo "🛠 Устанавливаем базовые утилиты..."
BASE_TOOLS=(mc curl wget git vim unzip zip htop net-tools build-essential ca-certificates gnupg)
for tool in "${BASE_TOOLS[@]}"; do
    if ! package_installed "$tool"; then
        sudo apt install -y "$tool"
    else
        echo "$tool уже установлен ✅"
    fi
done

# --- 3. Nginx (если нет) ---
echo "🌐 Устанавливаем Nginx..."
if ! package_installed "nginx"; then
    sudo apt install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
else
    echo "Nginx уже установлен ✅"
fi
sudo systemctl restart nginx

if sudo systemctl is-active --quiet nginx; then
    echo "Nginx запущен ✅"
else
    echo "Ошибка запуска Nginx! ❌"
    exit 1
fi

# --- 4. MariaDB (если нет) ---
echo "🗄 Устанавливаем MariaDB..."
if ! package_installed "mariadb-server"; then
    sudo apt install -y mariadb-server
    sudo systemctl enable mariadb
    sudo systemctl start mariadb
else
    echo "MariaDB уже установлена ✅"
fi

# Автоматическая настройка безопасности MariaDB
echo "🔒 Настраиваем безопасность MariaDB..."
sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
sudo mysql -e "DROP DATABASE IF EXISTS test;"
sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -e "FLUSH PRIVILEGES;"
echo "Базовая безопасность MariaDB настроена ✅"

# --- 5. PHP и модули (с версией из переменной) ---
echo "⚙️ Устанавливаем PHP $PHP_VERSION и модули..."

# Добавляем репозиторий PHP если нужно
if ! apt-cache policy php$PHP_VERSION-fpm | grep -q "Candidate"; then
    echo "Добавляем репозиторий PHP..."
    sudo apt install -y software-properties-common
    sudo add-apt-repository -y ppa:ondrej/php
    sudo apt update
fi

PHP_PACKAGES=(
    "php$PHP_VERSION-fpm" "php$PHP_VERSION-cli" "php$PHP_VERSION-mysql"
    "php$PHP_VERSION-gd" "php$PHP_VERSION-xml" "php$PHP_VERSION-mbstring"
    "php$PHP_VERSION-curl" "php$PHP_VERSION-zip" "php$PHP_VERSION-bcmath"
    "php$PHP_VERSION-intl" "php$PHP_VERSION-opcache"
    "php$PHP_VERSION-simplexml" "php$PHP_VERSION-dom" "php$PHP_VERSION-fileinfo"
)
for pkg in "${PHP_PACKAGES[@]}"; do
    if ! package_installed "$pkg"; then
        sudo apt install -y "$pkg"
    else
        echo "$pkg уже установлен ✅"
    fi
done

sudo systemctl enable "php$PHP_VERSION-fpm"
sudo systemctl start "php$PHP_VERSION-fpm"
echo "Версия PHP: $(php -v | head -n1)"

# --- 6. Composer (если нет) ---
echo "📦 Устанавливаем Composer..."
if ! command -v composer &> /dev/null; then
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
else
    echo "Composer уже установлен ✅"
fi
composer --version

# --- 7. Node.js и npm (если нет) ---
echo "🆕 Устанавливаем Node.js (LTS) и npm..."
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo "Node.js и npm уже установлены ✅"
fi

# --- 8. Финальная проверка ---
echo "🔍 Проверяем конфигурацию..."

# Проверка сервисов
SERVICES=("nginx" "mariadb" "php$PHP_VERSION-fpm")
for service in "${SERVICES[@]}"; do
    if sudo systemctl is-active --quiet "$service"; then
        echo "✅ $service работает"
    else
        echo "❌ $service не запущен"
    fi
done

# Проверка конфигурации Nginx
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "✅ Конфигурация Nginx корректна"
else
    echo "❌ Ошибка конфигурации Nginx"
    exit 1
fi
node -v
npm -v

echo "✅ Развёртывание завершено!"
