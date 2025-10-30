#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Функции для вывода сообщений
error() { echo -e "${RED}[Ошибка] $1${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}[Инфо] $1${NC}"; }
warn() { echo -e "${YELLOW}[Предупреждение] $1${NC}"; }
debug() { echo -e "${BLUE}[Отладка] $1${NC}"; }
step() { echo -e "${PURPLE}[Шаг] $1${NC}"; }

# Функции валидации
validate_project_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Имя проекта может содержать только буквы, цифры, дефисы и подчеркивания"
    fi
    if [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        error "Имя проекта должно быть от 2 до 50 символов"
    fi
}

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Некорректный формат домена"
    fi
}

validate_project_type() {
    local type="$1"
    case "$type" in
        static|php|laravel|symfony|nodejs) ;;
        *) error "Неизвестный тип проекта. Допустимые: static, php, laravel, symfony, nodejs" ;;
    esac
}

validate_git_url() {
    local url="$1"
    if [[ ! "$url" =~ ^(https?://|git@)[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/.+$ ]]; then
        error "Некорректный URL GitHub репозитория"
    fi
}

validate_php_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        error "Некорректный формат версии PHP (используйте формат: 8.1, 8.2, etc.)"
    fi
    
    # Проверка установленной версии PHP
    if ! command -v "php$version" &> /dev/null && ! command -v "php" &> /dev/null; then
        error "PHP $version не найден в системе. Установите его сначала."
    fi
}

check_existing_domain() {
    local domain="$1"
    if [ -f "/etc/nginx/sites-available/$project_name" ] || [ -f "/etc/nginx/sites-enabled/$project_name" ]; then
        error "Конфигурация Nginx для проекта $project_name уже существует"
    fi
    
    # Проверка существования домена в конфигах nginx
    if grep -r "server_name.*$domain" /etc/nginx/sites-available/ >/dev/null 2>&1; then
        error "Домен $domain уже используется в другой конфигурации Nginx"
    fi
}

detect_php_versions() {
    local versions=()
    
    # Поиск установленных версий PHP
    for version_dir in /etc/php/*; do
        if [[ -d "$version_dir/fpm" ]]; then
            version=$(basename "$version_dir")
            versions+=("$version")
        fi
    done
    
    # Если не нашли через директории, проверяем доступные команды php
    if [ ${#versions[@]} -eq 0 ]; then
        for cmd in /usr/bin/php*; do
            if [[ "$cmd" =~ /usr/bin/php[0-9]+\.[0-9]+$ ]]; then
                version=$(basename "$cmd" | sed 's/php//')
                versions+=("$version")
            fi
        done
    fi
    
    # Если все еще пусто, проверяем общую команду php
    if [ ${#versions[@]} -eq 0 ] && command -v php &> /dev/null; then
        default_version=$(php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;")
        versions+=("$default_version")
    fi
    
    echo "${versions[@]}"
}

get_default_php_version() {
    if command -v php &> /dev/null; then
        php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;"
    else
        # Поиск последней установленной версии
        local versions=($(detect_php_versions))
        if [ ${#versions[@]} -gt 0 ]; then
            echo "${versions[-1]}"
        else
            error "PHP не установлен в системе"
        fi
    fi
}

# Проверка прав root
[ "$EUID" -ne 0 ] && error "Запустите скрипт с правами root"

# Проверка зависимостей
for cmd in nginx git; do
    if ! command -v $cmd &> /dev/null; then
        warn "Команда $cmd не найдена, некоторые функции могут не работать"
    fi
done

echo "=== Настройка нового веб-проекта ==="

# Ввод данных с валидацией
while true; do
    read -p "Введите имя проекта: " project_name
    validate_project_name "$project_name"
    
    # Проверка существования директории
    if [ -d "/var/www/$project_name" ]; then
        warn "Директория /var/www/$project_name уже существует"
        read -p "Продолжить? (существующие данные могут быть перезаписаны) (y/n): " overwrite
        [ "$overwrite" = "y" ] && break
    else
        break
    fi
done

while true; do
    read -p "Домен проекта: " domain
    validate_domain "$domain"
    check_existing_domain "$domain"
    break
done

while true; do
    read -p "Тип проекта (static/php/laravel/symfony/nodejs): " project_type
    validate_project_type "$project_type"
    break
done

# Выбор версии PHP для PHP проектов
php_version=""
if [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" ]]; then
    available_versions=($(detect_php_versions))
    default_version=$(get_default_php_version)
    
    if [ ${#available_versions[@]} -eq 0 ]; then
        error "Не найдены установленные версии PHP"
    fi
    
    echo "Доступные версии PHP: ${available_versions[*]}"
    read -p "Выберите версию PHP (по умолчанию: $default_version): " selected_version
    php_version=${selected_version:-$default_version}
    validate_php_version "$php_version"
    
    info "Выбрана версия PHP: $php_version"
fi

use_git="n"
read -p "Клонировать из GitHub? (y/n): " use_git
if [ "$use_git" = "y" ]; then
    while true; do
        read -p "URL репозитория: " repo_url
        validate_git_url "$repo_url"
        break
    done
    read -p "Ветка (по умолчанию: main): " git_branch
    git_branch=${git_branch:-main}
fi

create_db="n"
if command -v mysql &> /dev/null; then
    read -p "Создать БД MySQL? (y/n): " create_db
fi

# Настройка PHP-FPM
if [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" ]]; then
    read -p "Имя PHP-FPM пула (по умолчанию: $project_name): " fpm_pool_name
    fpm_pool_name=${fpm_pool_name:-$project_name}
    
    # Валидация имени пула
    validate_project_name "$fpm_pool_name"
    
    # Проверка существования пула
    if [ -f "/etc/php/$php_version/fpm/pool.d/$fpm_pool_name.conf" ]; then
        error "PHP-FPM пул $fpm_pool_name уже существует"
    fi
fi

echo ""
info "Параметры проекта:"
echo "  Имя: $project_name"
echo "  Домен: $domain"
echo "  Тип: $project_type"
[[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" ]] && echo "  Версия PHP: $php_version"
echo "  Директория: /var/www/$project_name"
[ "$use_git" = "y" ] && echo "  GitHub: $repo_url ($git_branch)"
[ "$create_db" = "y" ] && echo "  Будет создана БД MySQL"
[[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" ]] && echo "  PHP-FPM пул: $fpm_pool_name"

read -p "Продолжить установку? (y/n): " confirm
[ "$confirm" != "y" ] && exit 0

echo ""
step "Начало установки..."

# Создание директорий
project_dir="/var/www/$project_name"
mkdir -p $project_dir
chown -R www-data:www-data $project_dir
info "Создана директория $project_dir"

# Клонирование репозитория
if [ "$use_git" = "y" ]; then
    step "Клонирование репозитория..."
    if [ -d "$project_dir/.git" ]; then
        warn "Директория уже содержит git репозиторий, пропускаем клонирование"
    else
        git clone -b $git_branch $repo_url $project_dir || error "Ошибка клонирования"
    fi
    chown -R www-data:www-data $project_dir
fi

# Создание PHP-FPM пула
if [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" ]]; then
    step "Настройка PHP-FPM пула..."
    
    fpm_pool_conf="/etc/php/$php_version/fpm/pool.d/$fpm_pool_name.conf"
    
    # Определяем параметры в зависимости от типа проекта
    case "$project_type" in
        laravel|symfony)
            pm_max_children=10
            pm_start_servers=4
            pm_min_spare_servers=2
            pm_max_spare_servers=6
            memory_limit="256M"
            max_execution_time="60"
            ;;
        *)
            pm_max_children=5
            pm_start_servers=2
            pm_min_spare_servers=1
            pm_max_spare_servers=3
            memory_limit="128M"
            max_execution_time="30"
            ;;
    esac
    
    cat > $fpm_pool_conf << EOF
[$fpm_pool_name]
user = www-data
group = www-data
listen = /run/php/php$php_version-fpm-$fpm_pool_name.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = $pm_max_children
pm.start_servers = $pm_start_servers
pm.min_spare_servers = $pm_min_spare_servers
pm.max_spare_servers = $pm_max_spare_servers

chdir = $project_dir
security.limit_extensions = .php .php3 .php4 .php5 .php7

php_admin_value[upload_max_filesize] = 32M
php_admin_value[post_max_size] = 32M
php_admin_value[max_execution_time] = $max_execution_time
php_admin_value[memory_limit] = $memory_limit
php_admin_value[opcache.memory_consumption] = 128

env[HOSTNAME] = \$HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp

; Symfony и Laravel переменные окружения
env[APP_ENV] = production
env[APP_DEBUG] = 0
EOF

    # Перезагрузка PHP-FPM
    if systemctl is-active --quiet "php$php_version-fpm"; then
        systemctl reload "php$php_version-fpm"
        info "PHP-FPM $php_version перезагружен"
    else
        warn "Служба PHP-FPM $php_version не запущена, требуется перезапуск вручную"
    fi
fi

# Настройка Nginx
step "Настройка Nginx..."
nginx_conf="/etc/nginx/sites-available/$project_name"

case $project_type in
    static)
        cat > $nginx_conf << EOF
server {
    listen 80;
    server_name $domain;
    root $project_dir;
    index index.html;

    access_log /var/log/nginx/${project_name}_access.log;
    error_log /var/log/nginx/${project_name}_error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        ;;

    php)
        cat > $nginx_conf << EOF
server {
    listen 80;
    server_name $domain;
    root $project_dir;
    index index.php index.html;

    access_log /var/log/nginx/${project_name}_access.log;
    error_log /var/log/nginx/${project_name}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
        ;;

    laravel)
        root_dir="$project_dir/public"
        
        cat > $nginx_conf << EOF
server {
    listen 80;
    server_name $domain;
    root $root_dir;
    index index.php index.html;

    access_log /var/log/nginx/${project_name}_access.log;
    error_log /var/log/nginx/${project_name}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
        ;;

    symfony)
        root_dir="$project_dir/public"
        
        cat > $nginx_conf << EOF
server {
    listen 80;
    server_name $domain;
    root $root_dir;
    index index.php index.html;

    access_log /var/log/nginx/${project_name}_access.log;
    error_log /var/log/nginx/${project_name}_error.log;

    location / {
        try_files \$uri /index.php\$is_args\$args;
    }

    location ~ ^/index\.php(/|$) {
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        internal;
    }

    location ~ \.php$ {
        return 404;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
        ;;

    nodejs)
        cat > $nginx_conf << EOF
server {
    listen 80;
    server_name $domain;
    
    access_log /var/log/nginx/${project_name}_access.log;
    error_log /var/log/nginx/${project_name}_error.log;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
        warn "Node.js проект настроен на порт 3000. Убедитесь, что приложение запущено"
        ;;
esac

# Активация сайта
ln -sf /etc/nginx/sites-available/$project_name /etc/nginx/sites-enabled/
if nginx -t; then
    systemctl reload nginx
    info "Настройка Nginx завершена"
else
    error "Ошибка конфигурации Nginx"
fi

# Создание БД
if [ "$create_db" = "y" ]; then
    step "Создание базы данных..."
    
    db_name="${project_name}_db"
    db_user="${project_name}_user"
    db_pass=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    # Валидация имени БД и пользователя
    mysql -e "SELECT 1" >/dev/null 2>&1 || error "Не удалось подключиться к MySQL"
    
    # Проверка существования БД
    if mysql -e "USE $db_name" 2>/dev/null; then
        error "База данных $db_name уже существует"
    fi
    
    mysql -e "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || error "Ошибка создания БД"
    mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" || error "Ошибка создания пользователя"
    mysql -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';" || error "Ошибка назначения прав"
    mysql -e "FLUSH PRIVILEGES;" || error "Ошибка применения привилегий"

    info "Создана БД: $db_name"
    info "Пользователь БД: $db_user"
    info "Пароль БД: $db_pass"
    
    # Создание файла с данными БД (опционально)
    db_creds_file="$project_dir/database_credentials.txt"
    cat > $db_creds_file << EOF
База данных: $db_name
Пользователь: $db_user
Пароль: $db_pass
Хост: localhost
EOF
    chmod 600 $db_creds_file
    chown www-data:www-data $db_creds_file
    warn "Данные БД сохранены в $db_creds_file"
fi

# Дополнительные настройки для фреймворков
case "$project_type" in
    laravel)
        step "Настройка Laravel..."
        
        # Проверка существования composer.json
        if [ -f "$project_dir/composer.json" ]; then
            # Установка прав для storage и bootstrap/cache
            chown -R www-data:www-data $project_dir/storage
            chown -R www-data:www-data $project_dir/bootstrap/cache
            chmod -R 775 $project_dir/storage
            chmod -R 775 $project_dir/bootstrap/cache
            
            # Копирование .env файла если его нет
            if [ ! -f "$project_dir/.env" ] && [ -f "$project_dir/.env.example" ]; then
                cp $project_dir/.env.example $project_dir/.env
                chown www-data:www-data $project_dir/.env
                
                # Обновление .env с данными БД если создавали БД
                if [ "$create_db" = "y" ]; then
                    sed -i "s/DB_DATABASE=.*/DB_DATABASE=$db_name/" $project_dir/.env
                    sed -i "s/DB_USERNAME=.*/DB_USERNAME=$db_user/" $project_dir/.env
                    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$db_pass/" $project_dir/.env
                fi
                
                warn "Создан .env файл из примера. Проверьте настройки."
            fi
        else
            warn "composer.json не найден. Laravel может требовать дополнительной настройки."
        fi
        ;;

    symfony)
        step "Настройка Symfony..."
        
        # Проверка существования composer.json
        if [ -f "$project_dir/composer.json" ]; then
            # Установка прав для var и config
            chown -R www-data:www-data $project_dir/var
            chown -R www-data:www-data $project_dir/config
            chmod -R 775 $project_dir/var
            chmod -R 775 $project_dir/config
            
            # Копирование .env файла если его нет
            if [ ! -f "$project_dir/.env" ] && [ -f "$project_dir/.env.example" ] || [ -f "$project_dir/.env.dist" ]; then
                if [ -f "$project_dir/.env.example" ]; then
                    cp $project_dir/.env.example $project_dir/.env
                elif [ -f "$project_dir/.env.dist" ]; then
                    cp $project_dir/.env.dist $project_dir/.env
                fi
                chown www-data:www-data $project_dir/.env
                
                # Обновление .env с данными БД если создавали БД
                if [ "$create_db" = "y" ]; then
                    # Symfony использует DATABASE_URL
                    database_url="mysql://$db_user:$db_pass@localhost:3306/$db_name?serverVersion=8.0&charset=utf8mb4"
                    escaped_url=$(printf '%s\n' "$database_url" | sed -e 's/[\/&]/\\&/g')
                    sed -i "s|DATABASE_URL=.*|DATABASE_URL=\"$escaped_url\"|" $project_dir/.env
                fi
                
                warn "Создан .env файл. Проверьте настройки."
            fi
            
            # Создание автоматического .env.local.php для оптимизации
            if [ -f "$project_dir/.env" ]; then
                sudo -u www-data /usr/bin/php$php_version $project_dir/bin/console --env=prod >/dev/null 2>&1 || true
            fi
        else
            warn "composer.json не найден. Symfony может требовать дополнительной настройки."
        fi
        ;;
esac

# Создание деploy скрипта для проекта
deploy_script="$project_dir/deploy.sh"
cat > $deploy_script << EOF
#!/bin/bash
# Скрипт деплоя для $project_name

cd $project_dir

# Обновление кода
if [ -d ".git" ]; then
    git pull origin $git_branch
fi

# Зависимости PHP проектов
if [[ "$project_type" == "laravel" || "$project_type" == "symfony" ]]; then
    # Установка/обновление композера
    if [ ! -f "composer.phar" ]; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=.
    fi
    
    # Установка зависимостей
    if [ "$project_type" = "laravel" ]; then
        php composer.phar install --no-dev --optimize-autoloader
        php artisan config:cache
        php artisan route:cache
        php artisan view:cache
        php artisan migrate --force
    elif [ "$project_type" = "symfony" ]; then
        php composer.phar install --no-dev --optimize-autoloader
        php bin/console cache:clear --env=prod
        php bin/console cache:warmup --env=prod
        php bin/console doctrine:migrations:migrate --no-interaction --env=prod
    fi
fi

# Права доступа
chown -R www-data:www-data $project_dir
find $project_dir -type f -exec chmod 644 {} \\;
find $project_dir -type d -exec chmod 755 {} \\;

# Особые права для фреймворков
if [ "$project_type" = "laravel" ]; then
    chmod -R 775 storage bootstrap/cache
elif [ "$project_type" = "symfony" ]; then
    chmod -R 775 var
fi

# Перезагрузка PHP-FPM
systemctl reload php$php_version-fpm

echo "Деплой проекта $project_name завершен"
EOF

chmod +x $deploy_script
info "Создан скрипт деплоя: $deploy_script"

echo ""
info "=== Проект $project_name успешно настроен! ==="
echo ""
echo "Данные проекта:"
echo "  Домен: http://$domain"
echo "  Директория: $project_dir"
[ "$create_db" = "y" ] && echo "  База данных: $db_name"
[[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" ]] && echo "  Версия PHP: $php_version"
[[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" ]] && echo "  PHP-FPM пул: $fpm_pool_name"
echo ""
echo "Следующие шаги:"
case "$project_type" in
    laravel) 
        echo "  - Выполните: cd $project_dir && php artisan key:generate"
        echo "  - Настройте .env файл если необходимо"
        ;;
    symfony)
        echo "  - Выполните: cd $project_dir && php bin/console secrets:generate-keys"
        echo "  - Настройте .env файл если необходимо"
        ;;
    nodejs)
        echo "  - Запустите Node.js приложение на порту 3000"
        ;;
esac
echo "  - Для деплоя используйте: $deploy_script"
echo "  - Настройте SSL сертификат (рекомендуется)"
echo "  - Настройте планировщик задач (cron) если необходимо"