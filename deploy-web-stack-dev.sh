#!/bin/bash

# ========================================================
# Скрипт развёртывания веб‑среды для разработки
# Ubuntu | PHP-версия через переменную + GitHub настройки + phpMyAdmin + Xdebug
# Автор: Virus3d
# Дата: 2025-10-29
# ========================================================

set -e  # Прекращать выполнение при ошибке

# --- Параметры ---
PHP_VERSION="8.5"           # Меняйте здесь: 8.2, 8.4 и т. п.
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

repo_installed() {
    grep -q "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null
}

package_available() {
    # Проверяем доступность пакета на обоих языках
    apt-cache policy "$1" | grep -q -E "Candidate|Кандидат"
}

# --- 1. Обновление системы ---
echo "🔁 Обновляем систему..."
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y
sudo apt autoremove -y && sudo apt clean

# --- 2. Базовые инструменты (если нет) ---
echo "🛠 Устанавливаем базовые утилиты..."
BASE_TOOLS=(mc curl wget git vim unzip zip htop net-tools build-essential ca-certificates gnupg software-properties-common)
for tool in "${BASE_TOOLS[@]}"; do
    if ! package_installed "$tool"; then
        sudo apt install -y "$tool"
    else
        echo "$tool уже установлен ✅"
    fi
done

# --- 3. Запрос на установку репозитория PHP ---
echo "🔄 Проверяем доступность PHP $PHP_VERSION..."

# Проверяем, доступна ли нужная версия PHP в текущих репозиториях
if ! package_available "php$PHP_VERSION-fpm"; then
    echo "❌ PHP $PHP_VERSION не найден в текущих репозиториях"
    echo "💡 Рекомендуется добавить репозиторий ondrej/php для получения актуальных версий PHP"
    echo ""
    read -p "Добавить репозиторий ondrej/php? (y/n): " add_php_repo

    if [[ $add_php_repo == "y" || $add_php_repo == "Y" ]]; then
        echo "📦 Добавляем репозиторий PHP..."
        sudo add-apt-repository -y ppa:ondrej/php
        sudo apt update
        echo "✅ Репозиторий ondrej/php добавлен"

        # Проверяем снова после добавления репозитория
        if ! package_available "php$PHP_VERSION-fpm"; then
            echo "❌ PHP $PHP_VERSION всё ещё не доступен после добавления репозитория"
            echo "Доступные версии PHP:"
            apt-cache search ^php[0-9] | grep -o 'php[0-9]\.[0-9]' | sort -u
            echo ""
            read -p "Выберите другую версию PHP (например, 8.2): " PHP_VERSION
            echo "✅ Установлена версия PHP: $PHP_VERSION"
        fi
    else
        echo "⚠️  Продолжаем без добавления репозитория. Некоторые версии PHP могут быть недоступны."
        echo "Доступные версии PHP:"
        apt-cache search ^php[0-9] | grep -o 'php[0-9]\.[0-9]' | sort -u
        echo ""
        read -p "Выберите другую версию PHP: " PHP_VERSION
        echo "✅ Установлена версия PHP: $PHP_VERSION"
    fi
elif ! repo_installed; then
    echo "ℹ️  PHP $PHP_VERSION доступен, но репозиторий ondrej/php не добавлен"
    echo "💡 Рекомендуется добавить репозиторий для получения обновлений безопасности"
    echo ""
    read -p "Добавить репозиторий ondrej/php? (y/n): " add_php_repo

    if [[ $add_php_repo == "y" || $add_php_repo == "Y" ]]; then
        echo "📦 Добавляем репозиторий PHP..."
        sudo add-apt-repository -y ppa:ondrej/php
        sudo apt update
        echo "✅ Репозиторий ondrej/php добавлен"
    else
        echo "ℹ️  Продолжаем без добавления репозитория"
    fi
else
    echo "✅ Репозиторий ondrej/php уже добавлен"
fi

# --- 4. Добавление пользователя в группу www-data ---
echo "👥 Настраиваем права доступа..."
CURRENT_USER=$(whoami)

if ! user_in_group "$CURRENT_USER" "www-data"; then
    echo "Добавляем пользователя $CURRENT_USER в группу www-data..."
    sudo usermod -a -G www-data "$CURRENT_USER"
    echo "✅ Пользователь $CURRENT_USER добавлен в группу www-data"
    echo "⚠️  Для применения изменений необходимо перелогиниться или выполнить: newgrp www-data"
else
    echo "✅ Пользователь $CURRENT_USER уже в группе www-data"
fi

# Проверяем текущие группы пользователя
echo "📋 Текущие группы пользователя $CURRENT_USER:"
groups "$CURRENT_USER"

# --- 5. Настройка безопасных директорий Git ---
echo "🔐 Настраиваем Git safe.directory..."

# Добавляем стандартные веб-директории в safe.directory
git config --global --add safe.directory /usr/share/phpmyadmin
git config --global --add safe.directory "/var/www/*"

echo "✅ Безопасные директории Git настроены"

# --- 6. Проверка и настройка Git ---
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

    echo "✅ Проверка Git завершена"
else
    echo "❌ Git не установлен!"
fi

# --- 7. Опциональная генерация SSH ключей для GitHub ---
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

# --- 8. Опциональная установка GitHub CLI ---
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

# --- 9. Nginx (если нет) ---
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

# --- 10. MySQL (если нет) ---
echo "🗄 Устанавливаем MySQL..."
if ! package_installed "mysql-server"; then
    sudo apt install -y mysql-server
    sudo systemctl enable mysql
    sudo systemctl start mysql
else
    echo "MySQL уже установлена ✅"
fi

# Автоматическая настройка безопасности MySQL
echo "🔒 Настраиваем безопасность MySQL..."
sudo mysql -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
sudo mysql -e "DROP DATABASE IF EXISTS test;"
sudo mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
sudo mysql -e "FLUSH PRIVILEGES;"
echo "Базовая безопасность MySQL настроена ✅"

# --- 11. PHP и модули (с версией из переменной) ---
echo "⚙️ Устанавливаем PHP $PHP_VERSION и модули..."

PHP_PACKAGES=(
    "php$PHP_VERSION-fpm" "php$PHP_VERSION-cli" "php$PHP_VERSION-common"
    "php$PHP_VERSION-mysql" "php$PHP_VERSION-gd" "php$PHP_VERSION-xml"
    "php$PHP_VERSION-mbstring" "php$PHP_VERSION-curl" "php$PHP_VERSION-zip"
    "php$PHP_VERSION-bcmath" "php$PHP_VERSION-intl" "php$PHP_VERSION-opcache"
)

# Проверяем доступность пакетов
AVAILABLE_PACKAGES=()
for pkg in "${PHP_PACKAGES[@]}"; do
    if package_available "$pkg"; then
        AVAILABLE_PACKAGES+=("$pkg")
    else
        echo "⚠️  Пакет $pkg недоступен, пропускаем"
    fi
done

# Устанавливаем доступные пакеты
for pkg in "${AVAILABLE_PACKAGES[@]}"; do
    if ! package_installed "$pkg"; then
        echo "Устанавливаем $pkg..."
        sudo apt install -y "$pkg"
    else
        echo "$pkg уже установлен ✅"
    fi
done

sudo systemctl enable "php$PHP_VERSION-fpm"
sudo systemctl start "php$PHP_VERSION-fpm"
echo "Версия PHP: $(php -v | head -n1)"

# --- 12. Установка и настройка Xdebug через репозиторий ---
echo "🐛 Устанавливаем и настраиваем Xdebug..."

# Проверяем, установлен ли уже Xdebug
if ! php -m | grep -q xdebug; then
    echo "Проверяем доступность Xdebug..."

    # Проверяем доступность пакета Xdebug
    if package_available "php$PHP_VERSION-xdebug"; then
        echo "Устанавливаем Xdebug из репозитория..."

        if ! package_installed "php$PHP_VERSION-xdebug"; then
            sudo apt install -y php$PHP_VERSION-xdebug
            echo "✅ Xdebug установлен из репозитория"
        else
            echo "✅ Xdebug уже установлен"
        fi

        # Создаем конфигурационный файл для Xdebug
        XDEBUG_INI="/etc/php/$PHP_VERSION/mods-available/xdebug.ini"

        # Проверяем, существует ли уже конфиг
        if [ ! -f "$XDEBUG_INI" ] || ! grep -q "xdebug.mode" "$XDEBUG_INI"; then
            sudo tee "$XDEBUG_INI" > /dev/null <<EOF
; Xdebug configuration
zend_extension=xdebug.so

; Основные настройки
xdebug.mode=develop,debug,profile
xdebug.start_with_request=yes
xdebug.client_port=9003
xdebug.client_host=127.0.0.1
xdebug.idekey=VSCODE
xdebug.log=/var/log/xdebug.log
xdebug.log_level=1

; Настройки для отладки
xdebug.discover_client_host=0
xdebug.start_upon_error=yes

; Настройки профилирования
xdebug.output_dir=/tmp

; Улучшенная отладка
xdebug.show_local_vars=1
xdebug.max_nesting_level=512

; Оптимизация производительности
xdebug.remote_log_level=0
xdebug.remote_autostart=0
EOF
            echo "✅ Конфигурационный файл Xdebug создан"
        else
            echo "✅ Конфигурационный файл Xdebug уже существует"
        fi

        # Включаем Xdebug
        sudo phpenmod xdebug

        # Создаем лог-файл и настраиваем права
        sudo touch /var/log/xdebug.log
        sudo chown www-data:www-data /var/log/xdebug.log
        sudo chmod 666 /var/log/xdebug.log

        echo "✅ Xdebug настроен и активирован"
    else
        echo "❌ Xdebug недоступен в репозиториях для PHP $PHP_VERSION"
        echo "💡 Попробуйте добавить репозиторий ondrej/php или использовать другую версию PHP"
    fi
else
    echo "✅ Xdebug уже установлен и активирован"
fi

# --- 13. Composer (если нет) ---
echo "📦 Устанавливаем Composer..."
if ! command -v composer &> /dev/null; then
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
else
    echo "Composer уже установлен ✅"
fi
composer --version

# --- 14. Node.js и npm (если нет) ---
echo "🆕 Устанавливаем Node.js (LTS) и npm..."
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo "Node.js и npm уже установлены ✅"
fi

# --- 15. Установка phpMyAdmin ---
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

# --- 16. Настройка Nginx для phpMyAdmin ---
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

# --- 17. Создание пользователя MySQL для phpMyAdmin (опционально) ---
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

# --- 18. Настройка прав для веб-директорий ---
echo "📁 Настраиваем права доступа для веб-директорий..."

# Настраиваем права для директории Nginx (если нужно)
NGINX_WEB_ROOT="/var/www"
if [ -d "$NGINX_WEB_ROOT" ]; then
    sudo chown -R "$CURRENT_USER":www-data "$NGINX_WEB_ROOT"
    # Устанавливаем правильные права: директории 775, файлы 664
    sudo find "$NGINX_WEB_ROOT" -type d -exec chmod 775 {} \;
    sudo find "$NGINX_WEB_ROOT" -type f -exec chmod 664 {} \;

    echo "✅ Права доступа настроены для $NGINX_WEB_ROOT (владелец: $CURRENT_USER, директории: 775, файлы: 664)"
fi

# --- 19. Финальная проверка и перезапуск сервисов ---
echo "🔍 Проверяем конфигурацию..."

# Перезапускаем PHP-FPM для применения настроек Xdebug
echo "🔄 Перезапускаем PHP-FPM..."
sudo systemctl restart "php$PHP_VERSION-fpm"

# Проверка сервисов
SERVICES=("nginx" "mysql" "php$PHP_VERSION-fpm")
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

# Проверка установленных PHP модулей
echo "🔧 Проверяем PHP модули..."
php -m | grep -E "(xdebug|opcache|json|mbstring)"

# Проверка Xdebug
if php -m | grep -q xdebug; then
    echo "✅ Xdebug активен"
    echo "🐛 Информация о Xdebug:"
    php -r "echo 'Версия Xdebug: ' . phpversion('xdebug') . \"\n\";"
else
    echo "❌ Xdebug не активирован"
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
echo "   ✅ Настроен репозиторий PHP (по выбору)"
echo "   ✅ Пользователь $CURRENT_USER добавлен в группу www-data"
echo "   ✅ Настроены безопасные директории Git"
echo "   ✅ Проверены/настроены настройки Git"
if [[ $generate_ssh == "y" || $generate_ssh == "Y" ]]; then
    echo "   ✅ Сгенерированы SSH ключи для GitHub"
fi
if [[ $install_gh == "y" || $install_gh == "Y" ]]; then
    echo "   ✅ Установлен GitHub CLI"
fi
echo "   ✅ Установлены и настроены: Nginx, MySQL, PHP $PHP_VERSION"
echo "   ✅ Установлен и настроен Xdebug"
echo "   ✅ Установлены: Composer, Node.js, npm"
echo "   ✅ Установлен и настроен phpMyAdmin $PHPMYADMIN_VERSION"
echo "   ✅ Настроены права доступа для веб-директорий"
echo "   ✅ Настроены права доступа для веб-директорий"
echo ""
echo "🚀 Дальнейшие действия:"
echo "   1. phpMyAdmin доступен по адресу: http://localhost:8080"
echo "   2. Для входа в phpMyAdmin используйте учетные данные MySQL"
echo "   3. Xdebug настроен на порт 9003 для отладки"
echo "   4. Для применения групповых прав может потребоваться: newgrp www-data"
if [[ $generate_ssh == "y" || $generate_ssh == "Y" ]]; then
    echo "   5. Добавьте SSH ключ в GitHub: https://github.com/settings/keys"
fi
echo ""
echo "🐛 Настройка отладки с Xdebug:"
echo "   - Порт отладки: 9003"
echo "   - IDE Key: VSCODE"
echo "   - Хост: 127.0.0.1"
echo "   - Логи: /var/log/xdebug.log"
echo "   - Режимы: develop, debug, profile"
echo ""
echo "🔧 Команды для управления сервисами:"
echo "   sudo systemctl restart nginx"
echo "   sudo systemctl restart mysql"
echo "   sudo systemctl restart php$PHP_VERSION-fpm"
echo ""
echo "⚡ Быстрые команды для отладки:"
echo "   Включить Xdebug: sudo phpenmod xdebug && sudo systemctl restart php$PHP_VERSION-fpm"
echo "   Выключить Xdebug: sudo phpdismod xdebug && sudo systemctl restart php$PHP_VERSION-fpm"
echo "   Проверить статус Xdebug: php -m | grep xdebug"
echo ""
echo "⚠️  Важно:"
echo "   - phpMyAdmin доступен на порту 8080 для безопасности"
echo "   - Настройте брандмауэр если необходимо открыть доступ к phpMyAdmin"
echo "   - Для продакшн-среды настройте HTTPS и аутентификацию для phpMyAdmin"
echo "   - Для продакшн-среды отключите Xdebug: sudo phpdismod xdebug"
echo "   - Группа www-data дает права на запись в веб-директории"
echo ""
