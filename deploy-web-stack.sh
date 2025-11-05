#!/bin/bash

# ========================================================
# Скрипт развёртывания веб‑среды для разработки
# Ubuntu | PHP-версия через переменную + GitHub настройки + phpMyAdmin
# Автор: Virus3d
# Дата: 2025-10-29
# ========================================================

set -e  # Прекращать выполнение при ошибке

# --- Параметры ---
PHP_VERSION="8.4"           # Меняйте здесь: 8.2, 8.4 и т. п.
SSH_KEY_ALGORITHM="ed25519" # Алгоритм SSH ключа: ed25519 или rsa
PHPMYADMIN_VERSION="5.2.1"  # Версия phpMyAdmin
PHPMYADMIN_LANGUAGE="ru"    # Язык phpMyAdmin (ru, en и т.д.)

echo "🚀 Запуск скрипта развёртывания веб‑среды для разработки"
echo "PHP версия: $PHP_VERSION"
echo "phpMyAdmin версия: $PHPMYADMIN_VERSION"

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

user_in_group() {
    groups "$1" | grep -q "\b$2\b"
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

# --- 3. Добавление пользователя в группу www-data ---
echo "👥 Настраиваем права доступа..."
CURRENT_USER=$(whoami)

if ! user_in_group "$CURRENT_USER" "www-data"; then
    echo "Добавляем пользователя $CURRENT_USER в группу www-data..."
    sudo usermod -a -G www-data "$CURRENT_USER"
    echo "✅ Пользователь $CURRENT_USER добавлен в группу www-data"
    echo "⚠️  Для применения изменений可能需要 перелогиниться или выполнить: newgrp www-data"
else
    echo "✅ Пользователь $CURRENT_USER уже в группе www-data"
fi

# Проверяем текущие группы пользователя
echo "📋 Текущие группы пользователя $CURRENT_USER:"
groups "$CURRENT_USER"

# --- 4. Проверка и настройка Git ---
echo "🔧 Проверяем настройки Git..."
if command -v git &> /dev/null; then
    CURRENT_GIT_NAME=$(git config --global user.name || echo "Не установлено")
    CURRENT_GIT_EMAIL=$(git config --global user.email || echo "Не установлено")
    
    echo "Текущие настройки Git:"
    echo "  user.name: $CURRENT_GIT_NAME"
    echo "  user.email: $CURRENT_GIT_EMAIL"
    echo ""
    
    if [[ "$CURRENT_GIT_NAME" == "Не установлено" || "$CURRENT_GIT_EMAIL" == "Не установлено" ]]; then
        echo "⚠️  Настройки Git неполные. Хотите настроить сейчас?"
        read -p "Настроить Git? (y/n): " configure_git
        
        if [[ $configure_git == "y" || $configure_git == "Y" ]]; then
            read -p "Введите ваш GitHub username: " GITHUB_USERNAME
            read -p "Введите ваш GitHub email: " GITHUB_EMAIL
            
            if [ -n "$GITHUB_USERNAME" ]; then
                git config --global user.name "$GITHUB_USERNAME"
                echo "Git user.name установлен: $GITHUB_USERNAME"
            fi
            
            if [ -n "$GITHUB_EMAIL" ]; then
                git config --global user.email "$GITHUB_EMAIL"
                echo "Git user.email установлен: $GITHUB_EMAIL"
            fi
        fi
    else
        echo "✅ Настройки Git уже выполнены"
    fi
    
    # Базовые настройки Git (без перезаписи существующих)
    git config --global init.defaultBranch main || true
    git config --global pull.rebase false || true
    git config --global core.editor "vim" || true
    git config --global color.ui auto || true
    git config --global --add safe.directory "/var/www/*"
    
    echo "✅ Проверка Git завершена"
else
    echo "❌ Git не установлен!"
fi

# --- 5. Опциональная генерация SSH ключей для GitHub ---
echo ""
read -p "🔑 Сгенерировать SSH ключи для GitHub? (y/n): " generate_ssh
if [[ $generate_ssh == "y" || $generate_ssh == "Y" ]]; then
    echo "🔑 Настраиваем SSH для GitHub..."
    
    # Запрашиваем email для SSH ключа если не указан ранее
    if [ -z "$GITHUB_EMAIL" ]; then
        read -p "Введите ваш email для SSH ключа: " GITHUB_EMAIL
    fi
    
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
        echo "❌ Пропускаем генерацию SSH: email не указан"
    fi
else
    echo "ℹ️  Пропускаем генерацию SSH ключей"
fi

# --- 6. Опциональная установка GitHub CLI ---
echo ""
read -p "🔄 Установить GitHub CLI? (y/n): " install_gh
if [[ $install_gh == "y" || $install_gh == "Y" ]]; then
    echo "🔄 Устанавливаем GitHub CLI..."
    if ! command -v gh &> /dev/null; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install -y gh
        echo "✅ GitHub CLI установлен"
        
        # Предлагаем аутентификацию
        echo ""
        read -p "🔐 Выполнить аутентификацию GitHub CLI? (y/n): " auth_gh
        if [[ $auth_gh == "y" || $auth_gh == "Y" ]]; then
            echo "Открываем браузер для аутентификации..."
            gh auth login
        fi
    else
        echo "✅ GitHub CLI уже установлен"
    fi
else
    echo "ℹ️  Пропускаем установку GitHub CLI"
fi

# --- 7. Nginx (если нет) ---
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

# --- 8. MariaDB (если нет) ---
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

# --- 9. PHP и модули (с версией из переменной) ---
echo "⚙️ Устанавливаем PHP $PHP_VERSION и модули..."

# Добавляем репозиторий PHP если нужно
# if ! apt-cache policy php$PHP_VERSION-fpm | grep -q "Candidate"; then
#     echo "Добавляем репозиторий PHP..."
#     sudo apt install -y software-properties-common
#     sudo add-apt-repository -y ppa:ondrej/php
#     sudo apt update
# fi

PHP_PACKAGES=(
    "php$PHP_VERSION-fpm" "php$PHP_VERSION-cli" "php$PHP_VERSION-common"
    "php$PHP_VERSION-mysql" "php$PHP_VERSION-gd" "php$PHP_VERSION-xml"
    "php$PHP_VERSION-mbstring" "php$PHP_VERSION-curl" "php$PHP_VERSION-zip"
    "php$PHP_VERSION-bcmath" "php$PHP_VERSION-intl" "php$PHP_VERSION-opcache"
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

# --- 10. Composer (если нет) ---
echo "📦 Устанавливаем Composer..."
if ! command -v composer &> /dev/null; then
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
else
    echo "Composer уже установлен ✅"
fi
composer --version

# --- 11. Node.js и npm (если нет) ---
echo "🆕 Устанавливаем Node.js (LTS) и npm..."
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo "Node.js и npm уже установлены ✅"
fi

# --- 12. Установка phpMyAdmin ---
echo "🗃 Устанавливаем phpMyAdmin $PHPMYADMIN_VERSION..."

# Создаем директорию для phpMyAdmin
PHPMYADMIN_DIR="/usr/share/phpmyadmin"
if dir_exists "$PHPMYADMIN_DIR"; then
    echo "⚠️  phpMyAdmin уже установлен в $PHPMYADMIN_DIR"
    read -p "Переустановить phpMyAdmin? (y/n): " reinstall_pma
    if [[ $reinstall_pma == "y" || $reinstall_pma == "Y" ]]; then
        sudo rm -rf "$PHPMYADMIN_DIR"
    else
        echo "Пропускаем установку phpMyAdmin"
    fi
fi

if ! dir_exists "$PHPMYADMIN_DIR"; then
    # Скачиваем и распаковываем phpMyAdmin
    cd /tmp
    wget -O phpmyadmin.zip "https://files.phpmyadmin.net/phpMyAdmin/$PHPMYADMIN_VERSION/phpMyAdmin-$PHPMYADMIN_VERSION-all-languages.zip"
    
    if file_exists "phpmyadmin.zip"; then
        sudo unzip -q phpmyadmin.zip -d /usr/share/
        sudo mv "/usr/share/phpMyAdmin-$PHPMYADMIN_VERSION-all-languages" "$PHPMYADMIN_DIR"
        sudo rm -f phpmyadmin.zip
        
        # Создаем конфигурационный файл
        sudo cp "$PHPMYADMIN_DIR/config.sample.inc.php" "$PHPMYADMIN_DIR/config.inc.php"
        
        # Генерируем случайный ключ для blowfish
        BLOWFISH_SECRET=$(openssl rand -base64 32)
        sudo sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg\['blowfish_secret'\] = '$BLOWFISH_SECRET';/" "$PHPMYADMIN_DIR/config.inc.php"
        
        # Устанавливаем язык
        sudo sed -i "s/\$cfg\['DefaultLang'\] = 'en';/\$cfg\['DefaultLang'\] = '$PHPMYADMIN_LANGUAGE';/" "$PHPMYADMIN_DIR/config.inc.php"
        
        # Настраиваем права доступа
        sudo chown -R www-data:www-data "$PHPMYADMIN_DIR"
        sudo chmod -R 755 "$PHPMYADMIN_DIR"
        sudo chmod 644 "$PHPMYADMIN_DIR/config.inc.php"
        
        echo "✅ phpMyAdmin установлен в $PHPMYADMIN_DIR"
    else
        echo "❌ Ошибка загрузки phpMyAdmin"
    fi
else
    echo "✅ phpMyAdmin уже установлен"
fi

# --- 13. Настройка Nginx для phpMyAdmin ---
echo "🔧 Настраиваем Nginx для phpMyAdmin..."

# Создаем конфиг для phpMyAdmin
PHPMYADMIN_NGINX_CONFIG="/etc/nginx/sites-available/phpmyadmin"

# Проверяем, не существует ли уже такой конфиг
if [ ! -f "$PHPMYADMIN_NGINX_CONFIG" ]; then
    sudo tee "$PHPMYADMIN_NGINX_CONFIG" > /dev/null <<EOF
server {
    listen 8080;
    server_name localhost;
    
    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;
    
    access_log /var/log/nginx/phpmyadmin_access.log;
    error_log /var/log/nginx/phpmyadmin_error.log;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ ^/(doc|sql|setup)/ {
        deny all;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF
    echo "✅ Конфиг Nginx для phpMyAdmin создан"
else
    echo "✅ Конфиг Nginx для phpMyAdmin уже существует"
fi

# Активируем конфиг если еще не активирован
if [ ! -f "/etc/nginx/sites-enabled/phpmyadmin" ]; then
    sudo ln -s "$PHPMYADMIN_NGINX_CONFIG" "/etc/nginx/sites-enabled/"
    echo "✅ Конфиг phpMyAdmin активирован в Nginx"
else
    echo "✅ Конфиг phpMyAdmin уже активирован в Nginx"
fi

# --- 14. Создание пользователя MySQL для phpMyAdmin (опционально) ---
echo "🔐 Настраиваем пользователя MySQL для phpMyAdmin..."
read -p "Создать отдельного пользователя MySQL для phpMyAdmin? (y/n): " create_mysql_user

if [[ $create_mysql_user == "y" || $create_mysql_user == "Y" ]]; then
    read -p "Введите имя пользователя для phpMyAdmin: " MYSQL_PMA_USER
    read -s -p "Введите пароль для пользователя $MYSQL_PMA_USER: " MYSQL_PMA_PASSWORD
    echo ""
    
    # Создаем пользователя и даем права
    sudo mysql -e "CREATE USER IF NOT EXISTS '$MYSQL_PMA_USER'@'localhost' IDENTIFIED BY '$MYSQL_PMA_PASSWORD';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_PMA_USER'@'localhost' WITH GRANT OPTION;"
    sudo mysql -e "FLUSH PRIVILEGES;"
    
    echo "✅ Пользователь MySQL '$MYSQL_PMA_USER' создан"
else
    echo "ℹ️  Используйте существующие учетные данные MySQL для доступа к phpMyAdmin"
fi

# --- 15. Настройка прав для веб-директорий ---
echo "📁 Настраиваем права доступа для веб-директорий..."

# Настраиваем права для директории Nginx (если нужно)
NGINX_WEB_ROOT="/var/www"
if [ -d "$NGINX_WEB_ROOT" ]; then
    sudo chown -R www-data:www-data "$NGINX_WEB_ROOT"
    sudo chmod -R 755 "$NGINX_WEB_ROOT"
    # Даем пользователю права на запись
    sudo chmod g+w "$NGINX_WEB_ROOT"
    echo "✅ Права доступа настроены для $NGINX_WEB_ROOT"
fi

# --- 16. Финальная проверка ---
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

# Проверка членства в группе www-data
echo "👥 Проверяем членство в группах..."
if user_in_group "$CURRENT_USER" "www-data"; then
    echo "✅ Пользователь $CURRENT_USER в группе www-data"
else
    echo "⚠️  Пользователь $CURRENT_USER не в группе www-data"
    echo "   Выполните команду: newgrp www-data"
fi

# Проверка версий
echo "📊 Версии установленного ПО:"
echo "PHP: $(php -v | head -n1)"
echo "Node.js: $(node -v)"
echo "npm: $(npm -v)"
echo "Git: $(git --version)"
if command -v composer &> /dev/null; then
    echo "Composer: $(composer --version)"
fi
if command -v gh &> /dev/null; then
    echo "GitHub CLI: $(gh --version | head -n1)"
fi

echo ""
echo "🎉 Развёртывание завершено!"
echo ""
echo "📝 Что сделано:"
echo "   ✅ Обновлена система и установлены базовые утилиты"
echo "   ✅ Пользователь $CURRENT_USER добавлен в группу www-data"
echo "   ✅ Проверены/настроены настройки Git"
if [[ $generate_ssh == "y" || $generate_ssh == "Y" ]]; then
    echo "   ✅ Сгенерированы SSH ключи для GitHub"
fi
if [[ $install_gh == "y" || $install_gh == "Y" ]]; then
    echo "   ✅ Установлен GitHub CLI"
fi
echo "   ✅ Установлены и настроены: Nginx, MariaDB, PHP $PHP_VERSION"
echo "   ✅ Установлены: Composer, Node.js, npm"
echo "   ✅ Установлен и настроен phpMyAdmin $PHPMYADMIN_VERSION"
echo "   ✅ Настроены права доступа для веб-директорий"
echo ""
echo "🚀 Дальнейшие действия:"
echo "   1. phpMyAdmin доступен по адресу: http://localhost:8080"
echo "   2. Для входа в phpMyAdmin используйте учетные данные MySQL"
if [[ $generate_ssh == "y" || $generate_ssh == "Y" ]]; then
    echo "   3. Добавьте SSH ключ в GitHub: https://github.com/settings/keys"
fi
echo "   4. Настройте виртуальные хосты Nginx для ваших проектов"
echo "   5. Создайте базы данных через MySQL"
echo ""
echo "🔧 Команды для управления сервисами:"
echo "   sudo systemctl restart nginx"
echo "   sudo systemctl restart mariadb"
echo "   sudo systemctl restart php$PHP_VERSION-fpm"
echo ""
echo "⚠️  Важно:"
echo "   - phpMyAdmin доступен на порту 8080 для безопасности"
echo "   - Настройте брандмауэр если необходимо открыть доступ к phpMyAdmin"
echo "   - Для продакшн-среды настройте HTTPS и аутентификацию для phpMyAdmin"
echo "   - Группа www-data дает права на запись в веб-директории"
echo ""