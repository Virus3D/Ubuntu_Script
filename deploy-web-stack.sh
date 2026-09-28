#!/usr/bin/env bash
set -euo pipefail

# ========== ЦВЕТА ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ========== ПРОВЕРКА ОС ==========
if ! grep -qiE 'debian|ubuntu' /etc/os-release 2>/dev/null; then
    log_err "Скрипт поддерживает только Debian/Ubuntu"
    exit 1
fi

. /etc/os-release
OS_ID="${ID}"
OS_VERSION="${VERSION_ID%%.*}"
OS_CODENAME="${VERSION_CODENAME:-}"
log_info "Обнаружена ОС: ${PRETTY_NAME}"

# Fallback, если VERSION_CODENAME пуст (например, в некоторых сборках)
if [ -z "$OS_CODENAME" ]; then
    if command -v lsb_release &>/dev/null; then
        OS_CODENAME=$(lsb_release -sc)
    else
        # Ручной маппинг для известных версий Debian
        case "${OS_VERSION}" in
            11) OS_CODENAME="bullseye" ;;
            12) OS_CODENAME="bookworm" ;;
            13) OS_CODENAME="trixie"   ;;
            14) OS_CODENAME="forky"    ;;
            *)  OS_CODENAME="stable"   ;;
        esac
    fi
fi

log_info "Кодовое имя: ${OS_CODENAME}"

# ========== ПАРАМЕТРЫ MYSQL ==========
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-StrongPass!}"
MYSQL_ADMIN_USER="admin"
MYSQL_ADMIN_PASS="${MYSQL_ADMIN_PASS:-StrongPass!}"

# ========== ФУНКЦИИ ПРОВЕРКИ ==========
command_exists() { command -v "$1" &>/dev/null; }

get_nginx_version()      { command_exists nginx    && nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+' || true; }
get_php_version()        { command_exists php      && php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true; }
get_mysql_version()      { command_exists mysql    && mysql --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || true; }
get_composer_version()   { command_exists composer && composer --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || true; }
get_npm_version()        { command_exists npm      && npm --version 2>/dev/null || true; }
get_phpmyadmin_version() {
    if dpkg -s phpmyadmin &>/dev/null; then
        dpkg-query -W -f='${Version}' phpmyadmin 2>/dev/null | sed -E 's/^[0-9]+://; s/[-+~].*$//'
    fi
}

# ========== СБОР ТЕКУЩИХ ВЕРСИЙ ==========
CURRENT_NGINX=$(get_nginx_version)
CURRENT_PHP=$(get_php_version)
CURRENT_MYSQL=$(get_mysql_version)
CURRENT_COMPOSER=$(get_composer_version)
CURRENT_NPM=$(get_npm_version)
CURRENT_PHPMYADMIN=$(get_phpmyadmin_version)

log_info "Текущие версии:"
[ -n "$CURRENT_NGINX" ]      && log_ok "Nginx:      $CURRENT_NGINX"      || log_warn "Nginx:      не установлен"
[ -n "$CURRENT_PHP" ]        && log_ok "PHP:        $CURRENT_PHP"        || log_warn "PHP:        не установлен"
[ -n "$CURRENT_MYSQL" ]      && log_ok "MySQL:      $CURRENT_MYSQL"      || log_warn "MySQL:      не установлен"
[ -n "$CURRENT_COMPOSER" ]   && log_ok "Composer:   $CURRENT_COMPOSER"   || log_warn "Composer:   не установлен"
[ -n "$CURRENT_NPM" ]        && log_ok "npm:        $CURRENT_NPM"        || log_warn "npm:        не установлен"
[ -n "$CURRENT_PHPMYADMIN" ] && log_ok "phpMyAdmin: $CURRENT_PHPMYADMIN" || log_warn "phpMyAdmin: не установлен"

# ========== ОБНОВЛЕНИЕ ПАКЕТОВ ==========
log_info "Обновление списка пакетов..."
sudo apt-get update -qq

# ========== NGINX ==========
if [ -z "$CURRENT_NGINX" ]; then
    log_info "Установка Nginx..."
    sudo apt-get install -y nginx
    sudo systemctl enable --now nginx
    log_ok "Nginx установлен: $(get_nginx_version)"
else
    log_ok "Nginx уже установлен: $CURRENT_NGINX"
fi

# ========== PHP-FPM ==========
if [ -z "$CURRENT_PHP" ]; then
    log_info "Установка PHP-FPM и расширений..."
    sudo apt-get install -y \
        php-fpm php-mysql php-xml php-mbstring php-curl \
        php-zip php-gd php-bcmath php-cli php-intl
    sudo systemctl enable --now php*-fpm
    log_ok "PHP установлен: $(get_php_version)"
else
    log_ok "PHP уже установлен: $CURRENT_PHP"
fi

# ========== MYSQL (Oracle, с fallback) ==========
if [ -z "$CURRENT_MYSQL" ]; then
    log_info "Установка MySQL..."

    # Проверяем, есть ли РЕАЛЬНЫЙ кандидат на установку
    MYSQL_CANDIDATE=$(apt-cache policy mysql-server 2>/dev/null \
        | awk '/Candidate:/{print $2; exit}')

    if [ -n "$MYSQL_CANDIDATE" ] && [ "$MYSQL_CANDIDATE" != "(none)" ]; then
        log_ok "Пакет mysql-server доступен в ${OS_ID}: кандидат ${MYSQL_CANDIDATE}"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
    else
        log_warn "Пакет mysql-server отсутствует в ${OS_ID} ${OS_VERSION} — подключаю репозиторий Oracle"

        # --- Установка вспомогательных утилит ---
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wget gnupg lsb-release curl

        # --- Удаляем старые ключи и источники ---
        log_info "Удаление старых ключей MySQL..."
        sudo rm -f /etc/apt/trusted.gpg.d/mysql2023.gpg
        sudo rm -f /usr/share/keyrings/mysql-apt-config.gpg
        sudo rm -f /usr/share/keyrings/mysql-apt-config.asc
        sudo rm -f /etc/apt/sources.list.d/mysql.list

        # --- Скачиваем ASCII-armored ключ НАПРЯМУЮ (без gpg --dearmor) ---
        log_info "Загрузка актуального GPG-ключа MySQL (ASCII-armored)..."
        sudo curl -fsSL \
            "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0xB7B3B788A8D3785C" \
            -o /usr/share/keyrings/mysql-apt-config.asc
        sudo chmod +r /usr/share/keyrings/mysql-apt-config.asc

        # --- Добавляем репозиторий Oracle с ASCII-ключом ---
        log_info "Добавление репозитория MySQL 8.4 LTS для ${OS_CODENAME}..."
        echo "deb [signed-by=/usr/share/keyrings/mysql-apt-config.asc] http://repo.mysql.com/apt/debian/ ${OS_CODENAME} mysql-8.4-lts" \
            | sudo tee /etc/apt/sources.list.d/mysql.list > /dev/null

        # --- Обновляем индекс ---
        log_info "Обновление индекса пакетов..."
        sudo apt-get update -qq
        # Чистим устаревший pkgcache.bin, из-за которого apt-cache policy молчит
        sudo rm -f /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin

        # --- Проверяем ДОСТУПНОСТЬ через симуляцию установки ---
        log_info "Проверка доступности mysql-community-server..."
        if sudo apt-get install -y --dry-run mysql-community-server &>/dev/null; then
            log_ok "Пакет mysql-community-server доступен для установки"
        else
            log_warn "Пакет не найден для ${OS_CODENAME} — переключаюсь на bookworm"
            sudo sed -i "s|/debian/ ${OS_CODENAME} |/debian/ bookworm |" /etc/apt/sources.list.d/mysql.list
            sudo apt-get update -qq
            sudo rm -f /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin

            if ! sudo apt-get install -y --dry-run mysql-community-server &>/dev/null; then
                log_err "Не удалось подключить репозиторий MySQL"
                log_info "Проверьте вручную:"
                log_info "  cat /etc/apt/sources.list.d/mysql.list"
                log_info "  sudo apt-get install mysql-community-server"
                exit 1
            fi
        fi

        # --- Пресеты для неинтерактивной установки ---
        sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password ${MYSQL_ROOT_PASS}"
        sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password ${MYSQL_ROOT_PASS}"
        sudo debconf-set-selections <<< "mysql-community-server mysql-server/default-auth-override select Use Strong Password Encryption (RECOMMENDED)"

        log_info "Установка mysql-community-server (Oracle)..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-community-server
    fi

    sudo systemctl enable --now mysql 2>/dev/null || sudo systemctl enable --now mysqld 2>/dev/null || true
    log_ok "MySQL установлен: $(get_mysql_version)"
else
    log_ok "MySQL уже установлен: $CURRENT_MYSQL"
fi

# ========== COMPOSER ==========
if [ -z "$CURRENT_COMPOSER" ]; then
    log_info "Установка Composer..."
    EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        log_err "Ошибка проверки подписи Composer"
        rm composer-setup.php
        exit 1
    fi
    php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    log_ok "Composer установлен: $(get_composer_version)"
else
    log_ok "Composer уже установлен: $CURRENT_COMPOSER"
fi

# ========== NODE.JS / NPM ==========
if ! command_exists node || ! command_exists npm; then
    log_info "Установка Node.js и npm..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    log_ok "Node.js установлен: $(node --version)"
    log_ok "npm установлен: $(get_npm_version)"
else
    log_ok "Node.js уже установлен: $(node --version)"
    log_ok "npm уже установлен: $CURRENT_NPM"
fi

# ========== PHPMYADMIN ==========
if [ -z "$CURRENT_PHPMYADMIN" ]; then
    log_info "Установка phpMyAdmin (без интерактива)..."

    # Отключаем авто-настройку web-сервера через debconf:
    # конфиг Nginx мы добавим сами.
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean false"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password"

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin

    log_ok "phpMyAdmin установлен: $(get_phpmyadmin_version)"
else
    log_ok "phpMyAdmin уже установлен: $CURRENT_PHPMYADMIN"
fi

# Гарантируем наличие blowfish_secret (нужен для cookie-аутентификации)
PHPMYADMIN_CONF="/etc/phpmyadmin/config.inc.php"
if [ -f "$PHPMYADMIN_CONF" ]; then
    if ! grep -q "blowfish_secret'\] = '[^']" "$PHPMYADMIN_CONF"; then
        SECRET=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)
        sudo sed -i "s|\$cfg\['blowfish_secret'\] = '';|\$cfg['blowfish_secret'] = '${SECRET}';|" "$PHPMYADMIN_CONF" || \
        echo "\$cfg['blowfish_secret'] = '${SECRET}';" | sudo tee -a "$PHPMYADMIN_CONF" >/dev/null
        log_ok "Сгенерирован blowfish_secret для phpMyAdmin"
    fi
fi

# ========== НАСТРОЙКА PHP-FPM ==========
PHP_VERSION=$(get_php_version)
if [ -n "$PHP_VERSION" ]; then
    PHP_FPM_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
    if [ -f "$PHP_FPM_INI" ]; then
        log_info "Настройка PHP-FPM..."
        sudo sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' "$PHP_FPM_INI"
        sudo sed -i 's/^;date.timezone.*/date.timezone = Europe\/Moscow/' "$PHP_FPM_INI"
        sudo systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
        log_ok "PHP-FPM настроен"
    fi
fi

# ========== НАСТРОЙКА NGINX (+ phpMyAdmin) ==========
if [ -n "$PHP_VERSION" ]; then
    log_info "Настройка Nginx (PHP-FPM + phpMyAdmin)..."
    sudo tee /etc/nginx/sites-available/default > /dev/null <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;
    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # --- phpMyAdmin (обязательно ДО общего PHP-блока) ---
    location ~ ^/phpmyadmin/(.+\.php)\$ {
        try_files \$uri =404;
        root /usr/share/;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
        root /usr/share/;
    }

    location ^~ /phpmyadmin {
        root /usr/share/;
        index index.php index.html index.htm;
        try_files \$uri \$uri/ =404;
    }

    # --- Общая обработка PHP ---
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    sudo nginx -t && sudo systemctl reload nginx
    log_ok "Nginx настроен: PHP-FPM + phpMyAdmin на /phpmyadmin"
fi

# ========== ПРОВЕРКА ОБНОВЛЕНИЙ ==========
log_info "Проверка доступных обновлений..."

UPDATES=$(apt list --upgradable 2>/dev/null | grep -E 'nginx|php|mysql|nodejs|phpmyadmin' | wc -l || true)
if [ "$UPDATES" -gt 0 ]; then
    log_warn "Доступны обновления для $UPDATES пакетов:"
    apt list --upgradable 2>/dev/null | grep -E 'nginx|php|mysql|nodejs|phpmyadmin' | head -20
else
    log_ok "Критических обновлений не найдено"
fi

if command_exists composer; then
    COMPOSER_LATEST=$(curl -s https://getcomposer.org/versions \
        | php -r '$d=json_decode(stream_get_contents(STDIN),true); echo $d["stable"][0]["version"] ?? "";' 2>/dev/null || true)
    if [ -n "$COMPOSER_LATEST" ] && [ "$CURRENT_COMPOSER" != "$COMPOSER_LATEST" ]; then
        log_warn "Composer: установлен $CURRENT_COMPOSER, доступен $COMPOSER_LATEST → composer self-update"
    fi
fi

# ========== ИТОГОВЫЙ ОТЧЁТ ==========
echo ""
echo "=============================================="
echo "         РЕЗУЛЬТАТ РАЗВЁРТЫВАНИЯ"
echo "=============================================="
printf "%-14s %-14s %-10s\n" "Компонент" "Версия" "Статус"
echo "----------------------------------------------"
printf "%-14s %-14s %-10s\n" "Nginx"      "$(get_nginx_version || echo '—')"      "$([ -n "$(get_nginx_version)" ] && echo 'OK' || echo 'MISSING')"
printf "%-14s %-14s %-10s\n" "PHP"        "$(get_php_version || echo '—')"        "$([ -n "$(get_php_version)" ] && echo 'OK' || echo 'MISSING')"
printf "%-14s %-14s %-10s\n" "MySQL"      "$(get_mysql_version || echo '—')"      "$([ -n "$(get_mysql_version)" ] && echo 'OK' || echo 'MISSING')"
printf "%-14s %-14s %-10s\n" "Composer"   "$(get_composer_version || echo '—')"   "$([ -n "$(get_composer_version)" ] && echo 'OK' || echo 'MISSING')"
printf "%-14s %-14s %-10s\n" "npm"        "$(get_npm_version || echo '—')"        "$([ -n "$(get_npm_version)" ] && echo 'OK' || echo 'MISSING')"
printf "%-14s %-14s %-10s\n" "phpMyAdmin" "$(get_phpmyadmin_version || echo '—')" "$([ -n "$(get_phpmyadmin_version)" ] && echo 'OK' || echo 'MISSING')"
echo "----------------------------------------------"
echo ""
log_ok "Развёртывание завершено!"
SERVER_IP=$(hostname -I | awk '{print $1}')
log_info "phpMyAdmin доступен по адресу: http://${SERVER_IP}/phpmyadmin"
log_info "Для входа используйте логин/пароль от MySQL"
log_warn "РЕКОМЕНДУЕТСЯ ограничить доступ к /phpmyadmin по IP или basic-auth"
log_info "Пример basic-auth: sudo apt install apache2-utils && sudo htpasswd -c /etc/nginx/.htpasswd admin"
log_info "Затем добавьте в location ^~ /phpmyadmin: auth_basic \"Restricted\"; auth_basic_user_file /etc/nginx/.htpasswd;"

# ========== СОЗДАНИЕ MYSQL-АДМИНИСТРАТОРА ==========
ADMIN_USER="admin"
ADMIN_PASS="${MYSQL_ADMIN_PASS:-StrongPass!}"

echo ""
echo "=============================================="
echo "         MYSQL: СОЗДАНИЕ АДМИНА"
echo "=============================================="
echo ""
log_info "SQL-инструкция для создания администратора MySQL:"
echo ""
echo "  sudo mysql -u root -p"
echo ""
echo "  CREATE USER 'admin'@'localhost' IDENTIFIED BY 'StrongPass!';"
echo "  GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;"
echo "  FLUSH PRIVILEGES;"
echo "  EXIT;"
echo ""
echo ""
echo ""
echo "  CREATE USER 'app'@'localhost' IDENTIFIED BY 'AppPass!';"
echo "  CREATE DATABASE appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
echo "  GRANT ALL PRIVILEGES ON appdb.* TO 'app'@'localhost';"
echo "  FLUSH PRIVILEGES;"
echo "  EXIT;"
echo ""

# Опциональное автосоздание
if [ -z "${MYSQL_ADMIN_PASS:-}" ]; then
    read -p "Создать пользователя '${MYSQL_ADMIN_USER}' автоматически с паролем '${MYSQL_ADMIN_PASS}'? [y/N] " -n 1 -r
    echo
else
    REPLY="y"
    log_info "Переменная MYSQL_ADMIN_PASS задана — создаю пользователя автоматически"
fi

if [[ "${REPLY:-N}" =~ ^[Yy]$ ]]; then
    # Пытаемся подключиться: сначала без пароля (auth_socket / свежий MySQL),
    # затем с паролем root (mysql-community-server из Oracle)
    if sudo mysql -uroot -p"${MYSQL_ROOT_PASS}" <<SQL 2>/dev/null || \
       sudo mysql <<SQL 2>/dev/null
CREATE USER IF NOT EXISTS '${MYSQL_ADMIN_USER}'@'localhost' IDENTIFIED BY '${MYSQL_ADMIN_PASS}';
ALTER USER '${MYSQL_ADMIN_USER}'@'localhost' IDENTIFIED BY '${MYSQL_ADMIN_PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_ADMIN_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    then
        log_ok "Пользователь '${MYSQL_ADMIN_USER}'@'localhost' создан"
        log_info "  Пароль: ${MYSQL_ADMIN_PASS}"
        log_info "  Вход в phpMyAdmin: http://${SERVER_IP}/phpmyadmin"
        log_warn "Смените пароль сразу после первого входа!"
    else
        log_err "Не удалось создать пользователя. Проверьте: sudo mysql -u root -p"
    fi
else
    log_info "Пропущено. Выполните SQL-инструкцию выше вручную позже."
fi

echo ""
log_ok "Готово. Не забудьте выполнить: sudo mysql_secure_installation"
