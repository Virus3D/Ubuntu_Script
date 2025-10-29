#!/bin/bash

# ========================================================
# Скрипт развёртывания веб‑среды для Symfony и Bitrix24
# Ubuntu 25.10 | Поддомены localhost | PHP-версия через переменную
# Автор: Ваш Имя
# Дата: 2025-10-29
# ========================================================

set -e  # Прекращать выполнение при ошибке

# --- Параметры ---
PHP_VERSION="8.4"           # Меняйте здесь: 8.2, 8.4 и т. п.
WEB_ROOT="/var/www"            # Корень веб‑проектов
NGINX_CONF="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

echo "🚀 Запуск скрипта развёртывания веб‑среды для Symfony/Bitrix24..."
echo "PHP версия: $PHP_VERSION | Веб‑корень: $WEB_ROOT"

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
BASE_TOOLS=(mc curl wget git vim unzip zip htop net-tools)
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
echo "Запустите 'sudo mysql_secure_installation' для безопасности."

# --- 5. PHP и модули (с версией из переменной) ---
echo "⚙️ Устанавливаем PHP $PHP_VERSION и модули..."
PHP_PACKAGES=(
    "php$PHP_VERSION-fpm" "php$PHP_VERSION-cli" "php$PHP_VERSION-mysql"
    "php$PHP_VERSION-gd" "php$PHP_VERSION-xml" "php$PHP_VERSION-mbstring"
    "php$PHP_VERSION-curl" "php$PHP_VERSION-zip" "php$PHP_VERSION-bcmath"
    "php$PHP_VERSION-intl" "php$PHP_VERSION-opcache"
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
php -v

# --- 6. Настройка динамического Nginx ---
echo "🔧 Настраиваем динамические поддомены *.localhost..."

# 6.1. Добавляем включение всех *.conf из sites-enabled
NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
if ! grep -q "include sites-enabled/\*.conf;" "$NGINX_MAIN_CONF"; then
    sudo sed -i '/http {/a \    include sites-enabled/*.conf;' "$NGINX_MAIN_CONF"
    echo "Добавлена директива include в nginx.conf ✅"
fi

# 6.2. Создаём шаблон конфига
cat > "$NGINX_TEMPLATE" << 'EOF'
server {
    listen 80;
    server_name $PROJECT_NAME.localhost;

    root $PROJECT_ROOT;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ ^/index\.php(/|$) {
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        internal;
    }

    location ~ \.php$ {
        return 404;
    }

    location ~ /\.ht {
        deny all;
    }

    error_log /var/log/nginx/$PROJECT_NAME.error.log;
    access_log /var/log/nginx/$PROJECT_NAME.access.log;
}
EOF

# 6.3. Создаём скрипт для быстрого добавления проектов
CREATE_SCRIPT="/usr/local/bin/create-web-project"
cat > "$CREATE_SCRIPT" << 'EOF'
#!/bin/bash

PROJECT_NAME="$1"
PROJECT_TYPE="$2"  # symfony | bitrix

if [ -z "$PROJECT_NAME" ]; then
    echo "Ошибка: укажите имя проекта. Пример: create-web-project mysite symfony"
    exit 1
fi

WEB_ROOT="/var/www"
PROJECT_DIR="$WEB_ROOT/$PROJECT_NAME"
CONF_FILE="/etc/nginx/sites-available/$PROJECT_NAME.conf"
LINK_FILE="/etc/nginx/sites-enabled/$PROJECT_NAME.conf"

# Создаём директорию
sudo mkdir -p "$PROJECT_DIR"
sudo chown -R www-data:www-data "$PROJECT_DIR"
sudo chmod -R 755 "$PROJECT_DIR"

# Выбираем шаблон в зависимости от типа
if [ "$PROJECT_TYPE" == "bitrix" ]; then
    cat > "$CONF_FILE" << EOF2
server {
    listen 80;
    server_name $PROJECT_NAME.localhost;

    root $PROJECT_DIR;
    index index.php;

    location / {
        try_files \$uri \$uri/ /bitrix/urlrewrite.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        fastcgi_read_timeout 300;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }

    error_log /var/log/nginx/$PROJECT_NAME.error.log;
    access_log /var/log/nginx/$PROJECT_NAME.access.log;
}
EOF2
else  # Symfony или общий шаблон
    cp /etc/nginx/sites-available/template.conf "$CONF_FILE"
    sed -i "s/\$PROJECT_NAME/$PROJECT_NAME/g" "$CONF_FILE"
    sed -i "s/\$PROJECT_ROOT/$PROJECT_DIR/g" "$CONF_FILE"
    sed -i "s/\$PHP_VERSION/8.3/g" "$CONF_FILE"
fi

# Активируем конфиг (создаём симлинк)
sudo ln -sf "$CONF_FILE" "$LINK_FILE"

# Проверяем конфигурацию и перезагружаем Nginx
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "Проект $PROJECT_NAME создан! Доступ: http://$PROJECT_NAME.localhost"
else
    echo "Ошибка конфигурации Nginx! Проверьте файл $CONF_FILE"
    exit 1
fi
EOF

# Даём права на выполнение
sudo chmod +x /usr/local/bin/create-web-project

# --- 7. Composer (если нет) ---
echo "📦 Устанавливаем Composer..."
if ! command -v composer &> /dev/null; then
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
else
    echo "Composer уже установлен ✅"
fi
composer --version

# --- 8. Node.js и npm (если нет) ---
echo "🆕 Устанавливаем Node.js (LTS) и npm..."
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo "Node.js и npm уже установлены ✅"
fi
node -v
npm -v

# Проверка и перезагрузка Nginx
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "Конфигурации Nginx активированы ✅"
else
    echo "Ошибка конфигурации Nginx! ❌"
    exit 1
fi

# --- 7. Composer (если нет) ---
echo "📦 Устанавливаем Composer..."
if ! command -v composer &> /dev/null; then
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
else
    echo "Composer уже установлен ✅"
fi
composer --version

# --- 8. Node.js и npm (если нет) ---
echo "🆕 Устанавливаем Node.js (LTS) и npm..."
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo "Node.js и npm уже установлены ✅"
fi
node -v
npm -v

echo "✅ Развёртывание завершено!"
echo "Проверьте работу: откройте в браузере http://ваш-сервер/info.php"
echo "Для безопасности удалите info.php после проверки: sudo rm /var/www/html/info.php"
