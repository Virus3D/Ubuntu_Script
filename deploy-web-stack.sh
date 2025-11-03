#!/bin/bash

# ========================================================
# Скрипт развёртывания веб‑среды для разработки
# Ubuntu | PHP-версия через переменную + GitHub настройки
# Автор: Virus3d
# Дата: 2025-10-29
# ========================================================

set -e  # Прекращать выполнение при ошибке

# --- Параметры ---
PHP_VERSION="8.4"           # Меняйте здесь: 8.2, 8.4 и т. п.
SSH_KEY_ALGORITHM="ed25519" # Алгоритм SSH ключа: ed25519 или rsa

echo "🚀 Запуск скрипта развёртывания веб‑среды для разработки"
echo "PHP версия: $PHP_VERSION"

# --- Запрос данных GitHub ---
echo ""
echo "🔧 Настройка GitHub"
read -p "Введите ваш GitHub username: " GITHUB_USERNAME
read -p "Введите ваш GitHub email: " GITHUB_EMAIL

# --- Функции ---
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

dir_exists() {
    [ -d "$1" ]
}

file_exists() {
    [ -f "$1" ]
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

# --- 3. Настройка Git ---
echo "🔧 Настраиваем Git..."
if command -v git &> /dev/null; then
    if [ -n "$GITHUB_USERNAME" ]; then
        git config --global user.name "$GITHUB_USERNAME"
        echo "Git user.name установлен: $GITHUB_USERNAME"
    fi
    
    if [ -n "$GITHUB_EMAIL" ]; then
        git config --global user.email "$GITHUB_EMAIL"
        echo "Git user.email установлен: $GITHUB_EMAIL"
    fi
    
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.editor "vim"
    git config --global color.ui auto
    
    echo "✅ Git сконфигурирован"
    echo "   Текущая конфигурация:"
    git config --global --list | grep -E "(user.name|user.email|init.defaultBranch)"
else
    echo "❌ Git не установлен!"
fi

# --- 4. Настройка SSH ключей для GitHub ---
echo "🔑 Настраиваем SSH для GitHub..."
if [ -n "$GITHUB_EMAIL" ]; then
    SSH_DIR="$HOME/.ssh"
    SSH_KEY_FILE="$SSH_DIR/id_$SSH_KEY_ALGORITHM"
    
    # Создаем директорию .ssh если её нет
    if ! dir_exists "$SSH_DIR"; then
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        echo "Создана директория $SSH_DIR"
    fi
    
    # Генерируем SSH ключ если его нет
    if ! file_exists "$SSH_KEY_FILE"; then
        echo "Генерируем новый SSH ключ ($SSH_KEY_ALGORITHM)..."
        ssh-keygen -t "$SSH_KEY_ALGORITHM" -C "$GITHUB_EMAIL" -f "$SSH_KEY_FILE" -N ""
        chmod 600 "$SSH_KEY_FILE"
        chmod 644 "$SSH_KEY_FILE.pub"
        echo "✅ SSH ключ сгенерирован: $SSH_KEY_FILE"
    else
        echo "✅ SSH ключ уже существует: $SSH_KEY_FILE"
    fi
    
    # Добавляем ключ в SSH агент
    if command -v ssh-agent &> /dev/null; then
        eval "$(ssh-agent -s)"
        ssh-add "$SSH_KEY_FILE" 2>/dev/null || true
    fi
    
    # Показываем публичный ключ для копирования в GitHub
    if file_exists "$SSH_KEY_FILE.pub"; then
        echo ""
        echo "📋 Ваш публичный SSH ключ (скопируйте и добавьте в GitHub):"
        echo "=========================================================="
        cat "$SSH_KEY_FILE.pub"
        echo "=========================================================="
        echo ""
        echo "💡 Добавьте этот ключ в GitHub: https://github.com/settings/keys"
        echo ""
    fi
else
    echo "⚠️  Пропускаем настройку SSH: GITHUB_EMAIL не указан"
fi

# --- 5. Настройка GitHub CLI (если нужно) ---
echo "🔄 Проверяем наличие GitHub CLI..."
if ! command -v gh &> /dev/null; then
    read -p "Установить GitHub CLI? (y/n): " install_gh
    if [[ $install_gh == "y" || $install_gh == "Y" ]]; then
        echo "Устанавливаем GitHub CLI..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install -y gh
        echo "✅ GitHub CLI установлен"
    fi
else
    echo "✅ GitHub CLI уже установлен"
fi

# --- 6. Nginx (если нет) ---
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

# --- 7. MariaDB (если нет) ---
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

# --- 8. PHP и модули (с версией из переменной) ---
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

# --- 9. Composer (если нет) ---
echo "📦 Устанавливаем Composer..."
if ! command -v composer &> /dev/null; then
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
else
    echo "Composer уже установлен ✅"
fi
composer --version

# --- 10. Node.js и npm (если нет) ---
echo "🆕 Устанавливаем Node.js (LTS) и npm..."
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo "Node.js и npm уже установлены ✅"
fi

# --- 11. Финальная проверка ---
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

# Проверка версий
echo "📊 Версии установленного ПО:"
node -v
npm -v
git --version

# Проверка SSH подключения к GitHub
if [ -n "$GITHUB_EMAIL" ] && file_exists "$SSH_KEY_FILE.pub"; then
    echo "🔗 Проверяем подключение к GitHub..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        echo "✅ SSH подключение к GitHub работает"
    else
        echo "⚠️  SSH ключ сгенерирован, но не добавлен в GitHub или не настроен"
        echo "   Добавьте ключ в: https://github.com/settings/keys"
    fi
fi

echo ""
echo "🎉 Развёртывание завершено!"
echo ""
echo "📝 Что сделано:"
echo "   ✅ Обновлена система и установлены базовые утилиты"
echo "   ✅ Настроен Git (username: $GITHUB_USERNAME, email: $GITHUB_EMAIL)"
echo "   ✅ Сгенерирован SSH ключ для GitHub ($SSH_KEY_ALGORITHM)"
echo "   ✅ Установлены и настроены: Nginx, MariaDB, PHP $PHP_VERSION"
echo "   ✅ Установлены: Composer, Node.js, npm"
echo ""
echo "🚀 Дальнейшие действия:"
if [ -n "$GITHUB_EMAIL" ]; then
    echo "   1. Скопируйте SSH ключ из вывода выше и добавьте в GitHub"
    echo "   2. Проверьте подключение: ssh -T git@github.com"
    echo "   3. Настройте виртуальные хосты Nginx для ваших проектов"
    echo "   4. Создайте базы данных через MySQL"
    echo "   5. Клонируйте ваши репозитории с GitHub:"
    echo "      git clone git@github.com:username/repository.git"
else
    echo "   1. Настройте виртуальные хосты Nginx для ваших проектов"
    echo "   2. Создайте базы данных через MySQL"
    echo "   3. Для работы с GitHub настройте Git вручную:"
    echo "      git config --global user.name 'Your Name'"
    echo "      git config --global user.email 'your@email.com'"
fi
echo ""
