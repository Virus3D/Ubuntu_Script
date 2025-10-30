#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции для вывода сообщений
error() { echo -e "${RED}[Ошибка] $1${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}[Инфо] $1${NC}"; }
warn() { echo -e "${YELLOW}[Предупреждение] $1${NC}"; }
debug() { echo -e "${BLUE}[Отладка] $1${NC}"; }
step() { echo -e "${PURPLE}[Шаг] $1${NC}"; }
bitrix_info() { echo -e "${CYAN}[Bitrix] $1${NC}"; }

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
        static|php|laravel|symfony|bitrix|nodejs) ;;
        *) error "Неизвестный тип проекта. Допустимые: static, php, laravel, symfony, bitrix, nodejs" ;;
    esac
}

validate_environment() {
    local env="$1"
    case "$env" in
        dev|prod) ;;
        *) error "Неизвестное окружение. Допустимые: dev, prod" ;;
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
    local project_type="$2"
    
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        error "Некорректный формат версии PHP (используйте формат: 8.1, 8.2, etc.)"
    fi
    
    # Проверка установленной версии PHP
    if ! command -v "php$version" &> /dev/null && ! command -v "php" &> /dev/null; then
        error "PHP $version не найден в системе. Установите его сначала."
    fi
    
    # Проверка минимальных требований для Bitrix
    if [ "$project_type" = "bitrix" ]; then
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        
        if [ "$major" -lt 7 ] || ([ "$major" -eq 7 ] && [ "$minor" -lt 4 ]) || [ "$major" -gt 8 ]; then
            warn "Bitrix24 рекомендует PHP 7.4-8.1. Выбрана версия: $version"
            read -p "Продолжить с PHP $version? (y/n): " continue_php
            [ "$continue_php" != "y" ] && exit 1
        fi
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

check_bitrix_requirements() {
    local php_version="$1"
    bitrix_info "Проверка требований для Bitrix24..."
    
    # Проверка расширений PHP
    local required_extensions=(
        "mbstring" "xml" "json" "curl" "gd" "mysqlnd" "pdo_mysql"
        "zip" "bcmath" "iconv" "soap" "intl"
    )
    
    local missing_extensions=()
    
    for ext in "${required_extensions[@]}"; do
        if ! php -m | grep -q "$ext"; then
            missing_extensions+=("$ext")
        fi
    done
    
    if [ ${#missing_extensions[@]} -gt 0 ]; then
        warn "Отсутствуют расширения PHP: ${missing_extensions[*]}"
        read -p "Установить недостающие расширения? (y/n): " install_ext
        if [ "$install_ext" = "y" ]; then
            for ext in "${missing_extensions[@]}"; do
                bitrix_info "Установка расширения: php$php_version-$ext"
                apt-get install -y "php$php_version-$ext" 2>/dev/null || \
                apt-get install -y "php-$ext" 2>/dev/null || \
                warn "Не удалось установить расширение: $ext"
            done
            systemctl reload "php$php_version-fpm"
        fi
    fi
}

setup_git_workflow() {
    local project_type="$1"
    local environment="$2"
    local project_dir="$3"
    
    step "Настройка Git workflow для окружения $environment..."
    
    # Создание .gitignore в зависимости от типа проекта
    case "$project_type" in
        laravel|symfony|php)
            cat > "$project_dir/.gitignore" << 'EOF'
# Environment
.env
.env.prod
.env.dev
.env.local

# Logs
storage/logs/*.log
*.log

# Cache
storage/framework/cache/
storage/framework/views/
bootstrap/cache/

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Node
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Deployment
deploy.sh
*.backup
*.sql
EOF
            ;;

        bitrix)
            cat > "$project_dir/.gitignore" << 'EOF'
# Bitrix24 Git ignore

# Environment settings
/.settings.php
/dbconn.php
/bitrix/php_interface/dbconn.php
/bitrix/.settings.php

# Cache directories
/bitrix/cache/*
/bitrix/managed_cache/*
/bitrix/stack_cache/*
/bitrix/html_pages/*

# Temporary files
/bitrix/tmp/*
/bitrix/backup/*

# Upload directory (осторожно - может содержать пользовательский контент)
/upload/*

# Logs
/bitrix/modules/*/log/

# Personal configurations
/bitrix/php_interface/after_connect_d7.php
/bitrix/php_interface/after_connect.php
/bitrix/php_interface/init.php
/bitrix/php_interface/dbconn.php

# Backup files
*.backup
*.sql
*.tar
*.gz

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Deployment scripts
deploy.sh
EOF
            bitrix_info "Создан .gitignore для Bitrix24"
            
            # Создание README с инструкциями по Git workflow
            cat > "$project_dir/README.git.md" << 'EOF'
# Git Workflow для Bitrix24

## Структура веток
- `main`/prod - боевая версия
- `stage` - тестовый сервер  
- `dev` - разработка

## Что коммитить в Git:
- ✅ Изменения в /local/
- ✅ Новые модули в /bitrix/modules/
- ✅ Шаблоны в /bitrix/templates/
- ✅ Компоненты в /bitrix/components/

## Что НЕ коммитить:
- ❌ Файлы кеша
- ❌ Загруженные файлы из /upload/
- ❌ Настройки БД (.settings.php)
- ❌ Временные файлы

## Процесс разработки:
1. Разработка в ветке `dev`
2. Тестирование в `stage` 
3. Деплой на продакшен из `main`
EOF
            ;;

        nodejs)
            cat > "$project_dir/.gitignore" << 'EOF'
# Dependencies
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Environment
.env
.env.local

# Logs
logs
*.log

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Coverage directory used by tools like istanbul
coverage/

# IDE
.idea/
.vscode/

# OS
.DS_Store
Thumbs.db

# Deployment
deploy.sh
dist/
build/
EOF
            ;;
    esac

    info "Создан .gitignore для $project_type"

    # Создание скрипта для настройки окружения
    local setup_env_script="$project_dir/setup-environment.sh"
    cat > "$setup_env_script" << EOF
#!/bin/bash
# Скрипт настройки окружения для $project_name

ENV=\${1:-$environment}

echo "Настройка окружения: \$ENV"

case "\$ENV" in
    dev)
        # Настройки для разработки
        echo "DEV environment configuration"
        
        # Для PHP проектов
        if [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]]; then
            # Включаем вывод ошибок для разработки
            sed -i "s/display_errors = Off/display_errors = On/" /etc/php/$php_version/fpm/php.ini 2>/dev/null || true
            sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/$php_version/fpm/php.ini 2>/dev/null || true
            
            # Перезагрузка PHP-FPM
            systemctl reload php$php_version-fpm
        fi
        
        # Для Bitrix
        if [ "$project_type" = "bitrix" ]; then
            # Включаем режим отладки
            if [ -f "$project_dir/bitrix/.settings.php" ]; then
                sed -i "s/'debug' => false/'debug' => true/" "$project_dir/bitrix/.settings.php" 2>/dev/null || true
            fi
        fi
        ;;
        
    prod)
        # Настройки для продакшена
        echo "PROD environment configuration"
        
        # Для PHP проектов
        if [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]]; then
            # Выключаем вывод ошибок
            sed -i "s/display_errors = On/display_errors = Off/" /etc/php/$php_version/fpm/php.ini 2>/dev/null || true
            sed -i "s/error_reporting = .*/error_reporting = E_ALL \& ~E_DEPRECATED \& ~E_STRICT/" /etc/php/$php_version/fpm/php.ini 2>/dev/null || true
            
            # Перезагрузка PHP-FPM
            systemctl reload php$php_version-fpm
        fi
        
        # Для Bitrix
        if [ "$project_type" = "bitrix" ]; then
            # Выключаем режим отладки
            if [ -f "$project_dir/bitrix/.settings.php" ]; then
                sed -i "s/'debug' => true/'debug' => false/" "$project_dir/bitrix/.settings.php" 2>/dev/null || true
            fi
        fi
        ;;
esac

echo "Окружение \$ENV настроено"
EOF

    chmod +x "$setup_env_script"
    info "Создан скрипт настройки окружения: $setup_env_script"
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
    read -p "Тип проекта (static/php/laravel/symfony/bitrix/nodejs): " project_type
    validate_project_type "$project_type"
    break
done

# Выбор окружения
read -p "Окружение (dev/prod, по умолчанию: dev): " environment
environment=${environment:-dev}
validate_environment "$environment"

info "Выбрано окружение: $environment"

# Выбор версии PHP для PHP проектов
php_version=""
BITRIX_PHP_OPTIMIZED=0
if [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]]; then
    available_versions=($(detect_php_versions))
    default_version=$(get_default_php_version)
    
    if [ ${#available_versions[@]} -eq 0 ]; then
        error "Не найдены установленные версии PHP"
    fi
    
    echo "Доступные версии PHP: ${available_versions[*]}"
    
    # Рекомендуемая версия для Bitrix
    if [ "$project_type" = "bitrix" ]; then
        default_version="8.1"
        bitrix_info "Рекомендуемая версия PHP для Bitrix24: 7.4-8.1"
    fi
    
    read -p "Выберите версию PHP (по умолчанию: $default_version): " selected_version
    php_version=${selected_version:-$default_version}
    validate_php_version "$php_version" "$project_type"
    
    # Проверка требований для Bitrix
    if [ "$project_type" = "bitrix" ]; then
        check_bitrix_requirements "$php_version"
    fi
    
    info "Выбрана версия PHP: $php_version"
fi

use_git="n"
if [ "$project_type" != "bitrix" ]; then
    read -p "Клонировать из GitHub? (y/n): " use_git
fi

# Особые варианты для Bitrix
bitrix_install_method=""
if [ "$project_type" = "bitrix" ]; then
    bitrix_info "Выберите способ установки Bitrix24:"
    echo "  1) Клонировать из GitHub (официальный репозиторий)"
    echo "  2) Скачать готовый дистрибутив"
    echo "  3) Установить Bitrix24 Virtual Appliance (VM)"
    echo "  4) Ручная установка (файлы уже в директории)"
    read -p "Выберите вариант (1-4): " bitrix_install_method
    
    case "$bitrix_install_method" in
        1)
            repo_url="https://github.com/bitrix-docker/bitrix-docker.git"
            use_git="y"
            git_branch="master"
            ;;
        2)
            bitrix_info "Будет скачан готовый дистрибутив Bitrix24"
            ;;
        3)
            warn "Bitrix24 Virtual Appliance требует дополнительной настройки VMware/VirtualBox"
            ;;
        4)
            info "Ручная установка - подготовьте файлы в директории /var/www/$project_name"
            ;;
        *)
            error "Неверный выбор"
            ;;
    esac
else
    if [ "$use_git" = "y" ]; then
        while true; do
            read -p "URL репозитория: " repo_url
            validate_git_url "$repo_url"
            break
        done
        read -p "Ветка (по умолчанию: main): " git_branch
        git_branch=${git_branch:-main}
    fi
fi

create_db="n"
if command -v mysql &> /dev/null; then
    read -p "Создать БД MySQL? (y/n): " create_db
fi

# Настройка PHP-FPM
if [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]]; then
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
echo "  Окружение: $environment"
[[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]] && echo "  Версия PHP: $php_version"
echo "  Директория: /var/www/$project_name"
[ "$use_git" = "y" ] && echo "  GitHub: $repo_url ($git_branch)"
[ "$project_type" = "bitrix" ] && echo "  Способ установки Bitrix: $bitrix_install_method"
[ "$create_db" = "y" ] && echo "  Будет создана БД MySQL"
[[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]] && echo "  PHP-FPM пул: $fpm_pool_name"

read -p "Продолжить установку? (y/n): " confirm
[ "$confirm" != "y" ] && exit 0

echo ""
step "Начало установки..."

# Создание директорий
project_dir="/var/www/$project_name"
mkdir -p $project_dir
chown -R www-data:www-data $project_dir
info "Создана директория $project_dir"

# Установка Bitrix24
if [ "$project_type" = "bitrix" ]; then
    step "Установка Bitrix24..."
    
    case "$bitrix_install_method" in
        1)
            # Клонирование из GitHub
            git clone -b $git_branch $repo_url $project_dir || error "Ошибка клонирования Bitrix24"
            ;;
        2)
            # Скачивание дистрибутива
            bitrix_info "Скачивание дистрибутива Bitrix24..."
            wget -O /tmp/bitrix.tar.gz "https://www.1c-bitrix.ru/download/scripts/bitrix_server_test.php" || error "Ошибка скачивания Bitrix24"
            tar -xzf /tmp/bitrix.tar.gz -C $project_dir --strip-components=1 || error "Ошибка распаковки Bitrix24"
            rm /tmp/bitrix.tar.gz
            ;;
        3)
            bitrix_info "Установка Bitrix24 Virtual Appliance..."
            warn "Этот метод требует ручной установки. Подготовьте VM образ."
            ;;
        4)
            info "Ручная установка - убедитесь что файлы Bitrix24 находятся в $project_dir"
            ;;
    esac
    
    # Создание необходимых директорий для Bitrix
    mkdir -p $project_dir/upload
    mkdir -p $project_dir/bitrix/cache
    mkdir -p $project_dir/bitrix/managed_cache
    mkdir -p $project_dir/bitrix/stack_cache
    mkdir -p $project_dir/bitrix/html_pages
    
    # Права доступа для Bitrix
    chown -R www-data:www-data $project_dir
    find $project_dir -type f -exec chmod 644 {} \;
    find $project_dir -type d -exec chmod 755 {} \;
    chmod -R 775 $project_dir/upload
    chmod -R 775 $project_dir/bitrix/cache
    chmod -R 775 $project_dir/bitrix/managed_cache
    chmod -R 775 $project_dir/bitrix/stack_cache
    chmod -R 775 $project_dir/bitrix/html_pages
    
    bitrix_info "Созданы директории и установлены права доступа"
fi

# Клонирование репозитория для других проектов
if [ "$use_git" = "y" ] && [ "$project_type" != "bitrix" ]; then
    step "Клонирование репозитория..."
    if [ -d "$project_dir/.git" ]; then
        warn "Директория уже содержит git репозиторий, пропускаем клонирование"
    else
        git clone -b $git_branch $repo_url $project_dir || error "Ошибка клонирования"
    fi
    chown -R www-data:www-data $project_dir
fi

# Настройка Git workflow
setup_git_workflow "$project_type" "$environment" "$project_dir"

# Создание PHP-FPM пула
if [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]]; then
    step "Настройка PHP-FPM пула..."
    
    fpm_pool_conf="/etc/php/$php_version/fpm/pool.d/$fpm_pool_name.conf"
    
    # Определяем параметры в зависимости от типа проекта и окружения
    case "$environment" in
        dev)
            # Настройки для разработки
            case "$project_type" in
                laravel|symfony)
                    pm_max_children=8
                    pm_start_servers=3
                    pm_min_spare_servers=2
                    pm_max_spare_servers=4
                    memory_limit="256M"
                    max_execution_time="120"
                    display_errors="On"
                    error_reporting="E_ALL"
                    ;;
                bitrix)
                    pm_max_children=15
                    pm_start_servers=6
                    pm_min_spare_servers=3
                    pm_max_spare_servers=8
                    memory_limit="512M"
                    max_execution_time="120"
                    display_errors="On"
                    error_reporting="E_ALL"
                    ;;
                *)
                    pm_max_children=5
                    pm_start_servers=2
                    pm_min_spare_servers=1
                    pm_max_spare_servers=3
                    memory_limit="256M"
                    max_execution_time="60"
                    display_errors="On"
                    error_reporting="E_ALL"
                    ;;
            esac
            ;;
        prod)
            # Настройки для продакшена
            case "$project_type" in
                laravel|symfony)
                    pm_max_children=20
                    pm_start_servers=8
                    pm_min_spare_servers=4
                    pm_max_spare_servers=12
                    memory_limit="512M"
                    max_execution_time="60"
                    display_errors="Off"
                    error_reporting="E_ALL & ~E_DEPRECATED"
                    ;;
                bitrix)
                    pm_max_children=30
                    pm_start_servers=12
                    pm_min_spare_servers=6
                    pm_max_spare_servers=18
                    memory_limit="768M"
                    max_execution_time="120"
                    display_errors="Off"
                    error_reporting="E_ALL & ~E_DEPRECATED"
                    ;;
                *)
                    pm_max_children=10
                    pm_start_servers=4
                    pm_min_spare_servers=2
                    pm_max_spare_servers=6
                    memory_limit="256M"
                    max_execution_time="30"
                    display_errors="Off"
                    error_reporting="E_ALL & ~E_DEPRECATED"
                    ;;
            esac
            ;;
    esac
    
    # Оптимизация для Bitrix
    if [ "$project_type" = "bitrix" ] && [ "$BITRIX_PHP_OPTIMIZED" -eq 1 ]; then
        upload_max_filesize="128M"
        post_max_size="128M"
    else
        upload_max_filesize="64M"
        post_max_size="64M"
    fi
    
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
pm.max_requests = 500

chdir = $project_dir
security.limit_extensions = .php .php3 .php4 .php5 .php7

php_admin_value[upload_max_filesize] = $upload_max_filesize
php_admin_value[post_max_size] = $post_max_size
php_admin_value[max_execution_time] = $max_execution_time
php_admin_value[memory_limit] = $memory_limit
php_admin_value[display_errors] = $display_errors
php_admin_value[error_reporting] = $error_reporting
php_admin_value[opcache.memory_consumption] = 256
php_admin_value[opcache.max_accelerated_files] = 20000
php_admin_value[opcache.revalidate_freq] = 2

; Отключение ограничений для Bitrix
php_admin_value[disable_functions] = 
php_admin_value[safe_mode] = off

env[HOSTNAME] = \$HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp

; Переменные окружения
env[APP_ENV] = $environment
env[APP_DEBUG] = $([ "$environment" = "dev" ] && echo "true" || echo "false")
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

# Общие настройки в зависимости от окружения
if [ "$environment" = "dev" ]; then
    # Для разработки - более детальное логирование
    access_log="access_log /var/log/nginx/${project_name}_access.log main buffer=64k flush=1m;"
    error_log="error_log /var/log/nginx/${project_name}_error.log debug;"
else
    # Для продакшена - оптимизированное логирование
    access_log="access_log /var/log/nginx/${project_name}_access.log main buffer=256k flush=5m;"
    error_log="error_log /var/log/nginx/${project_name}_error.log warn;"
fi

case $project_type in
    static)
        cat > $nginx_conf << EOF
server {
    listen 80;
    server_name $domain;
    root $project_dir;
    index index.html;

    $access_log
    $error_log

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

    $access_log
    $error_log

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

    $access_log
    $error_log

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

    $access_log
    $error_log

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

    bitrix)
        cat > $nginx_conf << EOF
server {
    listen 80;
    server_name $domain;
    root $project_dir;
    index index.php index.html;

    $access_log
    $error_log

    # Основные настройки для Bitrix
    client_max_body_size 128M;
    fastcgi_read_timeout 600;

    # Статические файлы
    location ~* \.(?:css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # Bitrix URL rewriting
    location / {
        try_files \$uri \$uri/ /bitrix/urlrewrite.php;
    }

    # Обработка PHP
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        
        # Дополнительные параметры для Bitrix
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    # Запрет доступа к системным файлам
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ /(upload|bitrix/modules|bitrix/php_interface|bitrix/templates|bitrix/wizards)/.*\.php$ {
        deny all;
    }

    # Особые правила для Bitrix
    location = /bitrix/urlrewrite.php {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
    }

    location ~* /\.ht {
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
    
    $access_log
    $error_log

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
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
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
    
    # Добавляем префикс окружения к имени БД
    if [ "$environment" = "prod" ]; then
        db_name="${project_name}_prod"
    else
        db_name="${project_name}_dev"
    fi
    
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
    
    # Создание файла с данными БД
    db_creds_file="$project_dir/database_credentials.txt"
    cat > $db_creds_file << EOF
Окружение: $environment
База данных: $db_name
Пользователь: $db_user
Пароль: $db_pass
Хост: localhost
EOF
    chmod 600 $db_creds_file
    chown www-data:www-data $db_creds_file
    warn "Данные БД сохранены в $db_creds_file"
    
    # Для Bitrix создаем дополнительный файл с настройками
    if [ "$project_type" = "bitrix" ]; then
        bitrix_db_file="$project_dir/bitrix/.settings.php"
        if [ ! -f "$bitrix_db_file" ]; then
            mkdir -p "$project_dir/bitrix"
            cat > "$bitrix_db_file" << 'EOF'
<?php
return array(
  'connections' => array(
    'value' => array(
      'default' => array(
        'className' => '\\Bitrix\\Main\\DB\\MysqliConnection',
        'host' => 'localhost',
        'database' => 'DB_NAME',
        'login' => 'DB_USER',
        'password' => 'DB_PASSWORD',
        'options' => 2,
      ),
    ),
    'readonly' => true,
  ),
);
EOF
            # Заменяем плейсхолдеры на реальные значения
            sed -i "s/DB_NAME/$db_name/g" "$bitrix_db_file"
            sed -i "s/DB_USER/$db_user/g" "$bitrix_db_file"
            sed -i "s/DB_PASSWORD/$db_pass/g" "$bitrix_db_file"
            chown www-data:www-data "$bitrix_db_file"
        fi
    fi
fi

# Дополнительные настройки для фреймворков с учетом окружения
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
            
            # Создание .env файла
            if [ ! -f "$project_dir/.env" ]; then
                if [ -f "$project_dir/.env.example" ]; then
                    cp $project_dir/.env.example $project_dir/.env
                else
                    # Создаем базовый .env
                    cat > "$project_dir/.env" << EOF
APP_NAME="$project_name"
APP_ENV=$environment
APP_KEY=
APP_DEBUG=$([ "$environment" = "dev" ] && echo "true" || echo "false")
APP_URL=http://$domain

LOG_CHANNEL=stack
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=$db_name
DB_USERNAME=$db_user
DB_PASSWORD=$db_pass

BROADCAST_DRIVER=log
CACHE_DRIVER=file
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS=null
MAIL_FROM_NAME="\${APP_NAME}"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=

PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_APP_CLUSTER=mt1

MIX_PUSHER_APP_KEY="\${PUSHER_APP_KEY}"
MIX_PUSHER_APP_CLUSTER="\${PUSHER_APP_CLUSTER}"
EOF
                fi
                chown www-data:www-data $project_dir/.env
                
                # Генерируем ключ приложения
                (cd $project_dir && sudo -u www-data /usr/bin/php$php_version artisan key:generate)
                
                warn "Создан .env файл для окружения $environment"
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
            if [ ! -f "$project_dir/.env" ] && { [ -f "$project_dir/.env.example" ] || [ -f "$project_dir/.env.dist" ]; }; then
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
                
                # Устанавливаем окружение
                sed -i "s|APP_ENV=.*|APP_ENV=$environment|" $project_dir/.env
                sed -i "s|APP_DEBUG=.*|APP_DEBUG=$([ "$environment" = "dev" ] && echo "1" || echo "0")|" $project_dir/.env
                
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

    bitrix)
        step "Дополнительная настройка Bitrix24..."
        
        # Проверяем наличие необходимых файлов
        if [ ! -f "$project_dir/bitrix/urlrewrite.php" ]; then
            warn "Файл urlrewrite.php не найден. Bitrix24 может требовать дополнительной настройки."
        fi
        
        # Создаем php.ini для Bitrix если нужно
        if [ "$BITRIX_PHP_OPTIMIZED" -eq 1 ]; then
            bitrix_php_ini="/etc/php/$php_version/fpm/conf.d/99-bitrix-$project_name.ini"
            cat > "$bitrix_php_ini" << EOF
; Настройки PHP для Bitrix24 - $project_name
memory_limit = 512M
upload_max_filesize = 128M
post_max_size = 128M
max_execution_time = 120
max_input_time = 60
max_input_vars = 10000
date.timezone = Europe/Moscow

; Настройки в зависимости от окружения
display_errors = $([ "$environment" = "dev" ] && echo "On" || echo "Off")
error_reporting = $([ "$environment" = "dev" ] && echo "E_ALL" || echo "E_ALL & ~E_DEPRECATED")

; Настройки OPcache для Bitrix
opcache.memory_consumption = 256
opcache.max_accelerated_files = 20000
opcache.revalidate_freq = 2
opcache.enable_cli = 1

; Отключение ограничений для Bitrix
disable_functions =
safe_mode = Off
EOF
            systemctl reload "php$php_version-fpm"
            bitrix_info "Создан оптимизированный php.ini для Bitrix24"
        fi
        
        # Создаем cron задания для Bitrix
        bitrix_cron="/etc/cron.d/bitrix-$project_name"
        cat > "$bitrix_cron" << EOF
# Cron задания для Bitrix24 - $project_name
*/5 * * * * www-data /usr/bin/php$php_version $project_dir/bitrix/modules/main/tools/cron_events.php
*/10 * * * * www-data /usr/bin/php$php_version $project_dir/bitrix/php_interface/include/catalog_export/cron_frame.php
0 */2 * * * www-data /usr/bin/php$php_version $project_dir/bitrix/php_interface/include/catalog_export/cron_run.php

# Очистка кеша для dev окружения
$([ "$environment" = "dev" ] && echo "*/15 * * * * www-data rm -rf $project_dir/bitrix/cache/* $project_dir/bitrix/managed_cache/*")
EOF
        chmod 644 "$bitrix_cron"
        bitrix_info "Добавлены cron задания для Bitrix24"
        
        # Создаем конфигурационный файл для разных окружений
        bitrix_env_config="$project_dir/bitrix/configuration.php"
        if [ ! -f "$bitrix_env_config" ]; then
            cat > "$bitrix_env_config" << EOF
<?php
// Конфигурация окружения Bitrix24
define('BX_DEBUG', $([ "$environment" = "dev" ] && echo "true" || echo "false"));
define('BX_COMPRESSION_DISABLED', $([ "$environment" = "dev" ] && echo "true" || echo "false"));

// Настройки кеширования в зависимости от окружения
if (BX_DEBUG) {
    // Для разработки - кеш на короткое время
    define('BX_CACHE_SID', 'dev');
    define('BX_CACHE_TYPE', 'files');
    define('BX_CACHE_TIME', 60);
} else {
    // Для продакшена - длительное кеширование
    define('BX_CACHE_SID', 'prod');
    define('BX_CACHE_TYPE', 'files');
    define('BX_CACHE_TIME', 3600);
}
EOF
            chown www-data:www-data "$bitrix_env_config"
        fi
        ;;
esac

# Создание деploy скрипта для проекта
deploy_script="$project_dir/deploy.sh"
cat > $deploy_script << EOF
#!/bin/bash
# Скрипт деплоя для $project_name

ENV=\${1:-$environment}
cd $project_dir

echo "Деплой проекта $project_name в окружении: \$ENV"

# Обновление кода
if [ -d ".git" ]; then
    git fetch origin
    git reset --hard origin/\$([ "\$ENV" = "prod" ] && echo "main" || echo "dev")
fi

# Зависимости PHP проектов
case "$project_type" in
    laravel|symfony)
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
            php bin/console cache:clear --env=\$ENV
            php bin/console cache:warmup --env=\$ENV
            php bin/console doctrine:migrations:migrate --no-interaction --env=\$ENV
        fi
        ;;
        
    bitrix)
        # Обновление Bitrix
        if [ -f "bitrix/updates/update.php" ]; then
            bitrix_info "Проверка обновлений Bitrix24..."
            /usr/bin/php$php_version bitrix/updates/update.php
        fi
        
        # Очистка кеша Bitrix
        if [ -d "bitrix/cache" ]; then
            rm -rf bitrix/cache/*
            rm -rf bitrix/managed_cache/*
            rm -rf bitrix/stack_cache/*
            rm -rf bitrix/html_pages/*
        fi
        ;;
esac

# Права доступа
chown -R www-data:www-data $project_dir
find $project_dir -type f -exec chmod 644 {} \\;
find $project_dir -type d -exec chmod 755 {} \\;

# Особые права для фреймворков
case "$project_type" in
    laravel)
        chmod -R 775 storage bootstrap/cache
        ;;
    symfony)
        chmod -R 775 var
        ;;
    bitrix)
        chmod -R 775 upload
        chmod -R 775 bitrix/cache
        chmod -R 775 bitrix/managed_cache
        chmod -R 775 bitrix/stack_cache
        chmod -R 775 bitrix/html_pages
        ;;
esac

# Настройка окружения
$project_dir/setup-environment.sh \$ENV

# Перезагрузка PHP-FPM
systemctl reload php$php_version-fpm

echo "Деплой проекта $project_name в окружении \$ENV завершен"
EOF

chmod +x $deploy_script
info "Создан скрипт деплоя: $deploy_script"

echo ""
info "=== Проект $project_name успешно настроен! ==="
echo ""
echo "Данные проекта:"
echo "  Домен: http://$domain"
echo "  Окружение: $environment"
echo "  Директория: $project_dir"
[ "$create_db" = "y" ] && echo "  База данных: $db_name"
[[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]] && echo "  Версия PHP: $php_version"
[[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]] && echo "  PHP-FPM пул: $fpm_pool_name"
echo ""
echo "Git workflow:"
echo "  - Создан .gitignore для $project_type"
echo "  - Используйте ветку '$([ "$environment" = "prod" ] && echo "main" || echo "dev")' для этого окружения"
echo ""
echo "Следующие шаги:"
case "$project_type" in
    laravel) 
        echo "  - Ключ приложения уже сгенерирован"
        echo "  - Настройте .env файл если необходимо"
        echo "  - Для деплоя: $deploy_script $environment"
        ;;
    symfony)
        echo "  - Выполните: cd $project_dir && php bin/console secrets:generate-keys"
        echo "  - Настройте .env файл если необходимо"
        echo "  - Для деплоя: $deploy_script $environment"
        ;;
    bitrix)
        echo "  - Откройте http://$domain в браузере для завершения установки Bitrix24"
        echo "  - Настройте административную панель Bitrix"
        echo "  - Для деплоя: $deploy_script $environment"
        ;;
    nodejs)
        echo "  - Запустите Node.js приложение на порту 3000"
        echo "  - Для деплоя: $deploy_script $environment"
        ;;
esac
echo ""
echo "Управление окружением:"
echo "  - Смена окружения: $project_dir/setup-environment.sh [dev|prod]"
echo "  - Деплой: $deploy_script [dev|prod]"
echo ""
[ "$environment" = "prod" ] && warn "ВНИМАНИЕ: Настроено PROD окружение! Убедитесь что debug режим выключен."
[ "$environment" = "dev" ] && info "Режим разработки активирован. Debug информация будет отображаться."
