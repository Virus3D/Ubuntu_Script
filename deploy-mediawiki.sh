#!/bin/bash

# Скрипт для автоматической установки MediaWiki с Nginx на Ubuntu
# Требует запуска с правами root

set -e # Выход при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функции для вывода сообщений
critical_error() {
    echo -e "${RED}[Критическая ошибка] $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Переменные для настройки
DB_NAME="my_wiki"
DB_USER="wikiuser"
DB_PASS=$(openssl rand -base64 32)
MEDIAWIKI_VERSION="1.44.2"
WEB_DIR="/var/www"
MW_DIR="$WEB_DIR/mediawiki"
DOMAIN_NAME="wiki.localhost" # Замените на ваш домен или IP

# Версия PHP (можно изменить на нужную)
PHP_VERSION="8.4"
PHP_POOL="mediawiki"

# Параметры PHP-FPM pool
FPM_MAX_CHILDREN=20
FPM_START_SERVERS=4
FPM_MIN_SPARE_SERVERS=2
FPM_MAX_SPARE_SERVERS=8
FPM_MAX_REQUESTS=500

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    critical_error "Запустите скрипт с правами root"
fi

# Проверка домена
if [ "$DOMAIN_NAME" = "wiki.localhost" ] || [ "$DOMAIN_NAME" = "localhost" ]; then
    warning "Домен localhost не поддерживает SSL. Используйте реальный домен для SSL."
    SSL_ENABLED=false
else
    SSL_ENABLED=true
    info "SSL будет настроен для домена: $DOMAIN_NAME"
fi

echo "Начинается установка MediaWiki с Nginx..."

# Определение пакетов PHP на основе версии
PHP_PACKAGES="php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-apcu php${PHP_VERSION}-redis php${PHP_VERSION}-bcmath"

# Обновление пакетов и установка зависимостей
info "Установка системных зависимостей..."
apt update
apt upgrade -y
apt install -y $PHP_PACKAGES

# Загрузка и распаковка MediaWiki
info "Загрузка MediaWiki..."
cd /tmp
wget https://releases.wikimedia.org/mediawiki/${MEDIAWIKI_VERSION%.*}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz
tar -xzf mediawiki-${MEDIAWIKI_VERSION}.tar.gz
mkdir -p $MW_DIR
cp -r mediawiki-${MEDIAWIKI_VERSION}/* $MW_DIR/

# Настройка базы данных MariaDB/MySQL
info "Настройка базы данных..."
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRARIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Создание отдельного PHP-FPM pool для MediaWiki
info "Настройка PHP-FPM pool '${PHP_POOL}'..."
cat > /etc/php/${PHP_VERSION}/fpm/pool.d/${PHP_POOL}.conf <<EOF
[${PHP_POOL}]
user = www-data
group = www-data

listen = /var/run/php/php${PHP_VERSION}-fpm-${PHP_POOL}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = ${FPM_MAX_CHILDREN}
pm.start_servers = ${FPM_START_SERVERS}
pm.min_spare_servers = ${FPM_MIN_SPARE_SERVERS}
pm.max_spare_servers = ${FPM_MAX_SPARE_SERVERS}
pm.max_requests = ${FPM_MAX_REQUESTS}

pm.status_path = /status

; Безопасность
security.limit_extensions = .php .php3 .php4 .php5 .php7

; Настройки PHP для MediaWiki
php_admin_value[upload_max_filesize] = 100M
php_admin_value[post_max_size] = 100M
php_admin_value[memory_limit] = 256M
php_admin_value[max_execution_time] = 120
php_admin_value[max_input_time] = 120
php_admin_value[max_input_vars] = 5000

; Пути
php_admin_value[open_basedir] = $MW_DIR:/tmp:/var/tmp:/dev/urandom
php_admin_value[sys_temp_dir] = /tmp

; Логирование
catch_workers_output = yes
php_flag[display_errors] = off
php_admin_flag[log_errors] = on
EOF

# Настройка Nginx
info "Настройка Nginx..."
if [ "$SSL_ENABLED" = true ]; then
    # Конфиг с SSL
    cat > /etc/nginx/sites-available/mediawiki <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    # Перенаправление на HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME;
    root $MW_DIR;
    index index.php index.html index.htm;

    # SSL конфигурация
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";

    # Запрет доступа к скрытым файлам
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Безопасность загрузок - запрет выполнения PHP в images
    location ~* ^/images/.*\.(php|php5|phtml|pl)$ {
        deny all;
        return 403;
    }

    # Обработка статических файлов
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files \$uri \$uri/ =404;
    }

    # Главная location для MediaWiki
    location / {
        try_files \$uri \$uri/ @rewrite;
    }

    # Rewrite rules для MediaWiki
    location @rewrite {
        rewrite ^/(.*)\$ /index.php?title=\$1&\$args;
    }

    # Обработка PHP через наш FPM pool
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm-${PHP_POOL}.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        # Безопасность для MediaWiki
        fastcgi_param HTTP_PROXY "";
        fastcgi_param MEDIAWIKI_ENV "production";
    }

    # Запрет доступа к служебным файлам
    location ~ /(cache|includes|maintenance|languages|serialized|tests|vendor|composer\.json|composer\.lock|COPYING|CREDITS|INSTALL|README|RELEASE-NOTES) {
        deny all;
    }

    # Дополнительная защита для конфигурационных файлов
    location ~ /(LocalSettings|wiki\.config)\.php {
        deny all;
    }
}
EOF
else
    # Конфиг без SSL
    cat > /etc/nginx/sites-available/mediawiki <<EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    root $MW_DIR;
    index index.php index.html index.htm;

    # Запрет доступа к скрытым файлам
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~* ^/images/.*\.(php|php5|phtml|pl)$ {
        deny all;
        return 403;
    }

    # Обработка статических файлов
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files \$uri \$uri/ =404;
    }

    # Главная location для MediaWiki
    location / {
        try_files \$uri \$uri/ @rewrite;
    }

    # Rewrite rules для MediaWiki
    location @rewrite {
        rewrite ^/(.*)\$ /index.php?title=\$1&\$args;
    }

    # Обработка PHP через наш FPM pool
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm-${PHP_POOL}.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        # Безопасность для MediaWiki
        fastcgi_param HTTP_PROXY "";
        fastcgi_param MEDIAWIKI_ENV "production";
    }

    # Запрет доступа к служебным файлам
    location ~ /(cache|includes|maintenance|languages|serialized|tests|vendor|composer\.json|composer\.lock|COPYING|CREDITS|INSTALL|README|RELEASE-NOTES) {
        deny all;
    }

    # Дополнительная защита для конфигурационных файлов
    location ~ /(LocalSettings|wiki\.config)\.php {
        deny all;
    }
}
EOF
fi

# Настройка прав доступа к файлам
info "Настройка прав доступа..."
chown -R www-data:www-data $MW_DIR
chmod 755 $MW_DIR
find $MW_DIR -type d -exec chmod 755 {} \;
find $MW_DIR -type f -exec chmod 644 {} \;

# Активация сайта в Nginx
ln -sf /etc/nginx/sites-available/mediawiki /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

info "Перезапуск служб..."
systemctl restart nginx php${PHP_VERSION}-fpm

# Получение SSL сертификата
if [ "$SSL_ENABLED" = true ]; then
    info "Получение SSL сертификата от Let's Encrypt..."

    # Временно останавливаем nginx для certbot
    systemctl stop nginx

    # Получаем сертификат
    if certbot certonly --standalone -d $DOMAIN_NAME --non-interactive --agree-tos --email $EMAIL; then
        info "SSL сертификат успешно получен!"

        # Настройка автоматического обновления сертификатов
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        info "Добавлена задача автоматического обновления SSL сертификатов"
    else
        warning "Не удалось получить SSL сертификат. Продолжаем без SSL..."
        SSL_ENABLED=false
    fi

    # Запускаем nginx обратно
    systemctl start nginx
fi

# Проверка конфигурации
# Проверка конфигурации
info "Проверка конфигурации..."
nginx -t
systemctl status php${PHP_VERSION}-fpm > /dev/null && info "PHP-FPM запущен успешно" || critical_error "Ошибка PHP-FPM"

# Настройка брандмауэра (если установлен ufw)
if command -v ufw &> /dev/null; then
    if [ "$SSL_ENABLED" = true ]; then
        ufw allow 'Nginx Full'
    else
        ufw allow 'Nginx HTTP'
    fi
    info "Правила брандмауэра обновлены"
fi

echo "================================================================"
info "Установка MediaWiki с Nginx завершена!"
echo "================================================================"
echo "Данные для подключения к базе данных:"
echo "База данных: $DB_NAME"
echo "Пользователь: $DB_USER"
echo "Пароль: $DB_PASS"
echo " "

if [ "$SSL_ENABLED" = true ]; then
    echo "Ваша вики доступна по адресу:"
    echo "https://$DOMAIN_NAME/mw-config/"
    echo " "
    echo "SSL сертификат настроен и будет автоматически обновляться"
else
    echo "Ваша вики доступна по адресу:"
    echo "http://$DOMAIN_NAME/mw-config/"
    echo " "
    echo "SSL не настроен. Для продакшн-среды рекомендуется настроить SSL."
fi

echo "После завершения установки через веб-интерфейс:"
echo "1. Сохраните файл LocalSettings.php"
echo "2. Загрузите его в директорию: $MW_DIR/"
echo "3. Рекомендуется установить права: chmod 600 $MW_DIR/LocalSettings.php"
echo "================================================================"

# Дополнительные рекомендации по безопасности
info "Дополнительные рекомендации по безопасности:"
echo "1. Настройте регулярное резервное копирование базы данных и файлов"
echo "2. Установите fail2ban для защиты от bruteforce атак"
echo "3. Настройте мониторинг сервера"
echo "4. Регулярно обновляйте MediaWiki и системные пакеты"