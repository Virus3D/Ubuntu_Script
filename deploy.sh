#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
ORANGE='\033[0;33m'
NC='\033[0m'

# Функции для вывода сообщений
error() {
    echo -e "${RED}[Ошибка] $1${NC}" >&2
    return 1
}
critical_error() {
    echo -e "${RED}[Критическая ошибка] $1${NC}" >&2
    exit 1
}
info() { echo -e "${GREEN}[Инфо] $1${NC}"; }
warn() { echo -e "${YELLOW}[Предупреждение] $1${NC}"; }
debug() { echo -e "${BLUE}[Отладка] $1${NC}"; }
step() { echo -e "${PURPLE}[Шаг] $1${NC}"; }
bitrix_info() { echo -e "${CYAN}[Bitrix] $1${NC}"; }
rebuild_info() { echo -e "${ORANGE}[Пересборка] $1${NC}"; }

# Глобальные переменные для обработки ошибок
ERROR_OCCURRED=0
ERROR_MESSAGES=()
CURRENT_STEP=""
SKIP_STEP=0

# Определение владельца файлов в зависимости от окружения
if [ "$environment" = "dev" ]; then
    FILE_OWNER="$SUDO_USER:www-data"
else
    FILE_OWNER="www-data:www-data"
fi

# Функции обработки ошибок
set_current_step() {
    CURRENT_STEP="$1"
    info "Текущий шаг: $1"
}

handle_error() {
    local error_msg="$1"
    local step_name="${2:-$CURRENT_STEP}"
    local critical="${3:-0}"

    ERROR_OCCURRED=1
    ERROR_MESSAGES+=("$step_name: $error_msg")

    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                        ОШИБКА                                ║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║ Шаг: $step_name${NC}"
    echo -e "${RED}║ Ошибка: $error_msg${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"

    if [ "$critical" -eq 1 ]; then
        echo ""
        read -p "Критическая ошибка! Продолжить установку? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            show_error_summary
            critical_error "Установка прервана пользователем"
        else
            warn "Продолжаем установку несмотря на критическую ошибку..."
            SKIP_STEP=1
        fi
    else
        echo ""
        read -p "Пропустить этот шаг и продолжить установку? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            show_error_summary
            critical_error "Установка прервана пользователем"
        else
            warn "Пропускаем шаг '$step_name' и продолжаем..."
            SKIP_STEP=1
        fi
    fi
}

show_error_summary() {
    if [ $ERROR_OCCURRED -eq 1 ]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                 СВОДКА ОШИБОК УСТАНОВКИ                     ║${NC}"
        echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
        for error in "${ERROR_MESSAGES[@]}"; do
            echo -e "${RED}║ • $error${NC}"
        done
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        warn "Некоторые шаги установки завершились с ошибками."
        warn "Проект может работать неполноценно."
    fi
}

safe_execute() {
    local command="$1"
    local step_name="$2"
    local critical="${3:-0}"

    SKIP_STEP=0

    # Пропускаем выполнение если предыдущий шаг был пропущен из-за ошибки
    if [ $ERROR_OCCURRED -eq 1 ] && [ $SKIP_STEP -eq 1 ]; then
        warn "Пропускаем выполнение: $step_name"
        return 0
    fi

    set_current_step "$step_name"

    # Выполняем команду с перехватом ошибок
    if eval "$command"; then
        info "✓ $step_name выполнен успешно"
        return 0
    else
        local error_code=$?
        handle_error "Команда завершилась с кодом $error_code: $command" "$step_name" "$critical"
        return $error_code
    fi
}

safe_mkdir() {
    local dir="$1"
    local step_name="${2:-Создание директории $dir}"

    safe_execute "mkdir -p '$dir'" "$step_name" 0
    if [ $? -eq 0 ] && [ $SKIP_STEP -eq 0 ]; then
        safe_execute "chown -R $FILE_OWNER '$dir'" "Настройка прав для $dir" 0
    fi
}

safe_chown() {
    local path="$1"
    local step_name="${2:-Настройка прав для $path}"

    safe_execute "chown -R $FILE_OWNER '$path'" "$step_name" 0
}

safe_chmod() {
    local path="$1"
    local mode="$2"
    local step_name="${3:-Настройка прав доступа для $path}"

    safe_execute "chmod -R $mode '$path'" "$step_name" 0
}

safe_systemctl() {
    local action="$1"
    local service="$2"
    local step_name="${3:-Системная служба $service}"

    safe_execute "systemctl $action '$service'" "$step_name" 0
}

safe_nginx_test() {
    safe_execute "nginx -t" "Проверка конфигурации Nginx" 1
}

# Функции валидации
validate_project_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Имя проекта может содержать только буквы, цифры, дефисы и подчеркивания"
        return 1
    fi
    if [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        error "Имя проекта должно быть от 2 до 50 символов"
        return 1
    fi
    return 0
}

validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-_]+\.[a-zA-Z]{2,}$ ]]; then
        error "Некорректный формат домена"
        return 1
    fi
    return 0
}

validate_project_type() {
    local type="$1"
    case "$type" in
        static|php|laravel|symfony|bitrix|nodejs) ;;
        *)
            error "Неизвестный тип проекта. Допустимые: static, php, laravel, symfony, bitrix, nodejs"
            return 1
            ;;
    esac
    return 0
}

validate_environment() {
    local env="$1"
    case "$env" in
        dev|prod) ;;
        *)
            error "Неизвестное окружение. Допустимые: dev, prod"
            return 1
            ;;
    esac
    return 0
}

validate_git_url() {
    local url="$1"
    if [[ ! "$url" =~ ^(https?://|git@)[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/.+$ ]]; then
        error "Некорректный URL GitHub репозитория"
        return 1
    fi
    return 0
}

validate_php_version() {
    local version="$1"
    local project_type="$2"

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        error "Некорректный формат версии PHP (используйте формат: 8.1, 8.2, etc.)"
        return 1
    fi

    # Проверка установленной версии PHP
    if ! command -v "php$version" &> /dev/null && ! command -v "php" &> /dev/null; then
        error "PHP $version не найден в системе. Установите его сначала."
        return 1
    fi

    # Проверка минимальных требований для Bitrix
    if [ "$project_type" = "bitrix" ]; then
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)

        if [ "$major" -lt 7 ] || ([ "$major" -eq 7 ] && [ "$minor" -lt 4 ]) || [ "$major" -gt 8 ]; then
            warn "Bitrix24 рекомендует PHP 7.4-8.1. Выбрана версия: $version"
            read -p "Продолжить с PHP $version? (y/n): " continue_php
            if [[ ! $continue_php =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi

    return 0
}

check_existing_domain() {
    local domain="$1"
    local exclude_project="$2"

    if [ -f "/etc/nginx/sites-available/$project_name" ] || [ -f "/etc/nginx/sites-enabled/$project_name" ]; then
        if [ "$mode" != "rebuild" ] || [ "$project_name" != "$exclude_project" ]; then
            warn "Конфигурация Nginx для проекта $project_name уже существует"
            # Предлагаем варианты действий
            echo ""
            echo "Выберите действие:"
            echo "  1) Обновить конфигурацию (удалить старую и создать новую)"
            echo "  2) Переименовать проект"
            echo "  3) Прервать установку"

            while true; do
                read -p "Введите номер варианта (1-3): " action_choice
                case "$action_choice" in
                    1)
                        info "Обновление конфигурации проекта '$project_name'..."

                        # Удаляем старые конфиги
                        safe_execute "rm -f '/etc/nginx/sites-available/$project_name'" "Удаление конфига sites-available" 0
                        safe_execute "rm -f '/etc/nginx/sites-enabled/$project_name'" "Удаление конфига sites-enabled" 0

                        # Перезагружаем службы
                        safe_systemctl "reload" "nginx" "Перезагрузка Nginx"

                        info "Старая конфигурация удалена. Продолжаем установку..."
                        break
                        ;;
                    2)
                        read -p "Введите новое имя проекта: " new_project_name
                        if validate_project_name "$new_project_name"; then
                            project_name="$new_project_name"
                            info "Проект переименован в: $project_name"

                            # Обновляем связанные переменные
                            project_dir="/var/www/$project_name"
                            if is_php; then
                                fpm_pool_name=${fpm_pool_name:-$project_name}
                            fi
                            break
                        else
                            warn "Некорректное имя проекта, попробуйте снова"
                        fi
                        ;;
                    3)
                        error "Установка прервана пользователем"
                        return 1
                        ;;
                    *)
                        warn "Неверный выбор. Попробуйте снова."
                        ;;
                esac
            done
        fi
    fi

    # Проверка существования домена в конфигах nginx
    if grep -r "server_name.*$domain" /etc/nginx/sites-available/ >/dev/null 2>&1; then
        if [ "$mode" != "rebuild" ] || [ "$project_name" != "$exclude_project" ]; then
            error "Домен $domain уже используется в другой конфигурации Nginx"
            return 1
        fi
    fi

    return 0
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
            return 1
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
                safe_execute "apt-get install -y 'php$php_version-$ext'" "Установка расширения PHP: $ext" 0
            done
            safe_systemctl "reload" "php$php_version-fpm"
        fi
    fi
}

# Функция для сохранения конфигурации проекта
save_project_config() {
    local project_dir="$1"
    local config_file="$project_dir/.deploy-config"

    safe_execute "cat > '$config_file' << EOF
# Конфигурация проекта $project_name
PROJECT_NAME=$project_name
DOMAIN=$domain
PROJECT_TYPE=$project_type
ENVIRONMENT=$environment
PHP_VERSION=$php_version
FPM_POOL_NAME=$fpm_pool_name
DB_NAME=$db_name
DB_USER=$db_user
CREATED_AT=\$(date +\"%Y-%m-%d %H:%M:%S\")
UPDATED_AT=\$(date +\"%Y-%m-%d %H:%M:%S\")
INSTALLATION_STATUS=$([ \$ERROR_OCCURRED -eq 0 ] && echo "COMPLETED" || echo "PARTIAL")
ERRORS=${#ERROR_MESSAGES[@]}
EOF" "Сохранение конфигурации проекта" 0

    if [ $? -eq 0 ]; then
        safe_chmod "$config_file" "600"
        safe_chown "$config_file"
    fi
}

# Функция для загрузки конфигурации проекта
load_project_config() {
    local project_dir="$1"
    local config_file="$project_dir/.deploy-config"

    if [ -f "$config_file" ]; then
        source "$config_file"
        info "Загружена конфигурация проекта из $config_file"
        return 0
    else
        return 1
    fi
}

# Функция пересборки проекта
rebuild_project() {
    rebuild_info "=== ПЕРЕСБИЛД ПРОЕКТА ==="

    # Поиск проектов в /var/www
    local projects=()
    for dir in /var/www/*; do
        if [ -d "$dir" ] && [ -f "$dir/.deploy-config" ]; then
            projects+=("$(basename "$dir")")
        fi
    done

    if [ ${#projects[@]} -eq 0 ]; then
        critical_error "Не найдено проектов с конфигурацией для пересборки"
    fi

    echo "Доступные проекты:"
    for i in "${!projects[@]}"; do
        echo "  $((i+1))) ${projects[$i]}"
    done

    read -p "Выберите проект для пересборки (1-${#projects[@]}): " project_choice
    local selected_project="${projects[$((project_choice-1))]}"

    if [ -z "$selected_project" ]; then
        critical_error "Неверный выбор проекта"
    fi

    local project_dir="/var/www/$selected_project"
    if ! load_project_config "$project_dir"; then
        critical_error "Не удалось загрузить конфигурацию проекта"
    fi

    rebuild_info "Пересборка проекта: $selected_project"
    echo "Текущая конфигурация:"
    echo "  Домен: $DOMAIN"
    echo "  Тип: $PROJECT_TYPE"
    echo "  Окружение: $ENVIRONMENT"
    echo "  PHP: $PHP_VERSION"

    # Предлагаем изменить параметры
    read -p "Изменить конфигурацию? (y/n): " change_config
    if [ "$change_config" = "y" ]; then
        # Сохраняем старые значения для подсказок
        local old_domain="$DOMAIN"
        local old_environment="$ENVIRONMENT"
        local old_php_version="$PHP_VERSION"

        # Запрашиваем новые значения
        read -p "Домен [$old_domain]: " new_domain
        domain="${new_domain:-$old_domain}"
        if ! validate_domain "$domain"; then
            critical_error "Некорректный домен"
        fi
        if ! check_existing_domain "$domain" "$selected_project"; then
            critical_error "Домен уже используется"
        fi

        read -p "Окружение (dev/prod) [$old_environment]: " new_environment
        environment="${new_environment:-$old_environment}"
        if ! validate_environment "$environment"; then
            critical_error "Некорректное окружение"
        fi

        if [[ "$PROJECT_TYPE" == "php" || "$PROJECT_TYPE" == "laravel" || "$PROJECT_TYPE" == "symfony" || "$PROJECT_TYPE" == "bitrix" ]]; then
            read -p "Версия PHP [$old_php_version]: " new_php_version
            php_version="${new_php_version:-$old_php_version}"
            if ! validate_php_version "$php_version" "$PROJECT_TYPE"; then
                critical_error "Некорректная версия PHP"
            fi
        fi

        # Обновляем переменные
        project_name="$selected_project"
        project_type="$PROJECT_TYPE"
        fpm_pool_name="$FPM_POOL_NAME"

        rebuild_info "Новая конфигурация:"
        echo "  Домен: $domain"
        echo "  Окружение: $environment"
        echo "  PHP: $php_version"
    else
        # Используем существующие значения
        project_name="$selected_project"
        domain="$DOMAIN"
        project_type="$PROJECT_TYPE"
        environment="$ENVIRONMENT"
        php_version="$PHP_VERSION"
        fpm_pool_name="$FPM_POOL_NAME"
        db_name="$DB_NAME"
        db_user="$DB_USER"
    fi

    # Удаляем старые конфиги
    rebuild_info "Удаление старых конфигураций..."

    # Удаляем конфиг nginx
    if [ -f "/etc/nginx/sites-available/$project_name" ]; then
        safe_execute "rm -f '/etc/nginx/sites-available/$project_name'" "Удаление старого конфига nginx" 0
    fi

    if [ -f "/etc/nginx/sites-enabled/$project_name" ]; then
        safe_execute "rm -f '/etc/nginx/sites-enabled/$project_name'" "Удаление ссылки nginx" 0
    fi

    # Удаляем старый PHP-FPM пул
    if [ -n "$php_version" ] && [ -f "/etc/php/$php_version/fpm/pool.d/$fpm_pool_name.conf" ]; then
        safe_execute "rm -f '/etc/php/$php_version/fpm/pool.d/$fpm_pool_name.conf'" "Удаление старого PHP-FPM пула" 0
    fi

    # Перезагружаем службы
    safe_systemctl "reload" "nginx"
    if [ -n "$php_version" ]; then
        safe_systemctl "reload" "php$php_version-fpm"
    fi

    rebuild_info "Старые конфигурации удалены"

    # Устанавливаем режим пересборки
    mode="rebuild"
}

setup_git_workflow() {
    local project_type="$1"
    local environment="$2"
    local project_dir="$3"

    step "Настройка Git workflow для окружения $environment..."

    # Проверяем, существует ли уже .gitignore
    local gitignore_file="$project_dir/.gitignore"
    if [ -f "$gitignore_file" ]; then
        info "Файл .gitignore уже существует, пропускаем создание"
        return 0
    fi

    # Создание .gitignore в зависимости от типа проекта
    case "$project_type" in
        laravel|symfony|php)
            safe_execute "cat > '$gitignore_file' << 'EOF'
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
EOF" "Создание .gitignore для $project_type" 0
            ;;

        bitrix)
            safe_execute "cat > '$gitignore_file' << 'EOF'
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
EOF" "Создание .gitignore для Bitrix24" 0

            if [ $? -eq 0 ]; then
                bitrix_info "Создан .gitignore для Bitrix24"

                # Создание README с инструкциями по Git workflow (только если не существует)
                local readme_file="$project_dir/README.git.md"
                if [ ! -f "$readme_file" ]; then
                    safe_execute "cat > '$readme_file' << 'EOF'
# Git Workflow для Bitrix24

## Структура веток
- \`main\`/prod - боевая версия
- \`stage\` - тестовый сервер
- \`dev\` - разработка

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
1. Разработка в ветке \`dev\`
2. Тестирование в \`stage\`
3. Деплой на продакшен из \`main\`
EOF" "Создание README.git.md" 0
                else
                    info "README.git.md уже существует, пропускаем создание"
                fi
            fi
            ;;

        nodejs)
            safe_execute "cat > '$gitignore_file' << 'EOF'
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
EOF" "Создание .gitignore для Node.js" 0
            ;;
    esac

    if [ $? -eq 0 ] && [ -f "$gitignore_file" ]; then
        info "Создан .gitignore для $project_type"
    fi

    # Создание скрипта для настройки окружения (всегда обновляем)
    local setup_env_script="$project_dir/setup-environment.sh"
    safe_execute "cat > '$setup_env_script' << EOF
#!/bin/bash
# Скрипт настройки окружения для $project_name

ENV=\\\${1:-$environment}

echo \"Настройка окружения: \\\$ENV\"

case \"\\\$ENV\" in
    dev)
        # Настройки для разработки
        echo \"DEV environment configuration\"

        # Для PHP проектов
        if [[ \"$project_type\" == \"php\" || \"$project_type\" == \"laravel\" || \"$project_type\" == \"symfony\" || \"$project_type\" == \"bitrix\" ]]; then
            # Включаем вывод ошибок для разработки
            sed -i \"s/display_errors = Off/display_errors = On/\" /etc/php/$php_version/fpm/php.ini 2>/dev/null || true
            sed -i \"s/error_reporting = .*/error_reporting = E_ALL/\" /etc/php/$php_version/fpm/php.ini 2>/dev/null || true

            # Перезагрузка PHP-FPM
            systemctl reload php$php_version-fpm
        fi

        # Для Bitrix
        if [ \"$project_type\" = \"bitrix\" ]; then
            # Включаем режим отладки
            if [ -f \"$project_dir/bitrix/.settings.php\" ]; then
                sed -i \"s/'debug' => false/'debug' => true/\" \"$project_dir/bitrix/.settings.php\" 2>/dev/null || true
            fi
        fi
        ;;

    prod)
        # Настройки для продакшена
        echo \"PROD environment configuration\"

        # Для PHP проектов
        if [[ \"$project_type\" == \"php\" || \"$project_type\" == \"laravel\" || \"$project_type\" == \"symfony\" || \"$project_type\" == \"bitrix\" ]]; then
            # Выключаем вывод ошибок
            sed -i \"s/display_errors = On/display_errors = Off/\" /etc/php/$php_version/fpm/php.ini 2>/dev/null || true
            sed -i \"s/error_reporting = .*/error_reporting = E_ALL \\\& ~E_DEPRECATED \\\& ~E_STRICT/\" /etc/php/$php_version/fpm/php.ini 2>/dev/null || true

            # Перезагрузка PHP-FPM
            systemctl reload php$php_version-fpm
        fi

        # Для Bitrix
        if [ \"$project_type\" = \"bitrix\" ]; then
            # Выключаем режим отладки
            if [ -f \"$project_dir/bitrix/.settings.php\" ]; then
                sed -i \"s/'debug' => true/'debug' => false/\" \"$project_dir/bitrix/.settings.php\" 2>/dev/null || true
            fi
        fi
        ;;
esac

echo \"Окружение \\\$ENV настроено\"
EOF" "Создание скрипта настройки окружения" 0

    if [ $? -eq 0 ]; then
        safe_chmod "$setup_env_script" "+x"
        info "Создан скрипт настройки окружения: $setup_env_script"
    fi
}

create_backup() {
    local backup_dir="/var/backups/$project_name"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    safe_mkdir "$backup_dir"

    # Бэкап конфигов
    tar -czf "$backup_dir/config_$timestamp.tar.gz" \
        "/etc/nginx/sites-available/$project_name" \
        "/etc/nginx/sites-enabled/$project_name" \
        "/etc/php/$php_version/fpm/pool.d/$fpm_pool_name.conf" \
        2>/dev/null || true
}

validate_dependencies() {
    local missing_deps=()

    case "$project_type" in
        laravel|symfony)
            if ! command -v composer &> /dev/null; then
                missing_deps+=("composer")
            fi
            ;;
        nodejs)
            if ! command -v node &> /dev/null; then
                missing_deps+=("nodejs")
            fi
            ;;
    esac

    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Отсутствуют зависимости: ${missing_deps[*]}"
        return 1
    fi
    return 0
}

setup_ssl() {
    if command -v certbot &> /dev/null; then
        read -p "Настроить SSL с Certbot? (y/n): " setup_ssl
        if [ "$setup_ssl" = "y" ]; then
            safe_execute "certbot --nginx -d $domain" "Настройка SSL сертификата" 0
        fi
    fi
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    critical_error "Запустите скрипт с правами root"
fi

# Проверка зависимостей
for cmd in nginx git; do
    if ! command -v $cmd &> /dev/null; then
        warn "Команда $cmd не найдена, некоторые функции могут не работать"
    fi
done

# Выбор режима работы
echo "=== ВЕБ-ПРОЕКТ ДЕПЛОЙ СКРИПТ ==="
echo "Выберите режим работы:"
echo "  1) Установка нового проекта"
echo "  2) Пересборка существующего проекта"
echo "  3) Обновление конфигурации проекта"
read -p "Выберите вариант (1-3): " mode_choice

case "$mode_choice" in
    1)
        mode="install"
        echo "Режим: Установка нового проекта"
        ;;
    2)
        rebuild_project
        ;;
    3)
        mode="update"
        rebuild_project
        ;;
    *)
        critical_error "Неверный выбор режима"
        ;;
esac

# Если не в режиме пересборки, запрашиваем данные для нового проекта
if [ "$mode" = "install" ]; then
    echo "=== Настройка нового веб-проекта ==="

    # Ввод данных с валидацией
    while true; do
        read -p "Введите имя проекта: " project_name
        if validate_project_name "$project_name"; then
            break
        else
            read -p "Попробовать снова? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                critical_error "Установка прервана"
            fi
        fi

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
        if validate_domain "$domain" && check_existing_domain "$domain"; then
            break
        else
            read -p "Попробовать снова? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                critical_error "Установка прервана"
            fi
        fi
    done

    while true; do
        read -p "Тип проекта (static/php/laravel/symfony/bitrix/nodejs): " project_type
        if validate_project_type "$project_type"; then
            break
        else
            read -p "Попробовать снова? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                critical_error "Установка прервана"
            fi
        fi
    done

    # Выбор окружения
    while true; do
        read -p "Окружение (dev/prod, по умолчанию: dev): " environment
        environment=${environment:-dev}
        if validate_environment "$environment"; then
            break
        else
            read -p "Попробовать снова? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                critical_error "Установка прервана"
            fi
        fi
    done

    info "Выбрано окружение: $environment"
fi

# Обновляем FILE_OWNER после определения окружения
if [ "$environment" = "dev" ]; then
    FILE_OWNER="$SUDO_USER:www-data"
else
    FILE_OWNER="www-data:www-data"
fi

is_php() { [[ "$project_type" == "php" || "$project_type" == "laravel" || "$project_type" == "symfony" || "$project_type" == "bitrix" ]]; }
# Выбор версии PHP для PHP проектов
if [ "$mode" = "install" ] && is_php; then
    php_version=""
    BITRIX_PHP_OPTIMIZED=0
    available_versions=($(detect_php_versions))
    default_version=$(get_default_php_version)

    if [ ${#available_versions[@]} -eq 0 ]; then
        critical_error "Не найдены установленные версии PHP"
    fi

    echo "Доступные версии PHP: ${available_versions[*]}"

    # Рекомендуемая версия для Bitrix
    if [ "$project_type" = "bitrix" ]; then
        default_version="8.1"
        bitrix_info "Рекомендуемая версия PHP для Bitrix24: 7.4-8.1"
    fi

    while true; do
        read -p "Выберите версию PHP (по умолчанию: $default_version): " selected_version
        php_version=${selected_version:-$default_version}
        if validate_php_version "$php_version" "$project_type"; then
            break
        else
            read -p "Попробовать снова? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                critical_error "Установка прервана"
            fi
        fi
    done

    # Проверка требований для Bitrix
    if [ "$project_type" = "bitrix" ]; then
        check_bitrix_requirements "$php_version"
    fi

    info "Выбрана версия PHP: $php_version"
fi

# Настройки Git (только для новой установки)
if [ "$mode" = "install" ]; then
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
        while true; do
            read -p "Выберите вариант (1-4): " bitrix_install_method
            case "$bitrix_install_method" in
                1)
                    repo_url="https://github.com/bitrix-docker/bitrix-docker.git"
                    use_git="y"
                    git_branch="master"
                    break
                    ;;
                2)
                    bitrix_info "Будет скачан готовый дистрибутив Bitrix24"
                    break
                    ;;
                3)
                    warn "Bitrix24 Virtual Appliance требует дополнительной настройки VMware/VirtualBox"
                    break
                    ;;
                4)
                    info "Ручная установка - подготовьте файлы в директории /var/www/$project_name"
                    break
                    ;;
                *)
                    echo "Неверный выбор. Попробуйте снова."
                    ;;
            esac
        done
    else
        if [ "$use_git" = "y" ]; then
            while true; do
                read -p "URL репозитория: " repo_url
                if validate_git_url "$repo_url"; then
                    break
                else
                    read -p "Попробовать снова? (Y/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Nn]$ ]]; then
                        use_git="n"
                        break
                    fi
                fi
            done
            if [ "$use_git" = "y" ]; then
                read -p "Ветка (по умолчанию: main): " git_branch
                git_branch=${git_branch:-main}
            fi
        fi
    fi

    create_db="n"
    if command -v mysql &> /dev/null; then
        read -p "Создать БД MySQL? (y/n): " create_db
    fi

    # Настройка PHP-FPM
    if is_php; then
        read -p "Имя PHP-FPM пула (по умолчанию: $project_name): " fpm_pool_name
        fpm_pool_name=${fpm_pool_name:-$project_name}

        # Валидация имени пула
        if ! validate_project_name "$fpm_pool_name"; then
            critical_error "Некорректное имя PHP-FPM пула"
        fi

        # Проверка существования пула
        if [ -f "/etc/php/$php_version/fpm/pool.d/$fpm_pool_name.conf" ]; then
            warn "PHP-FPM пул $fpm_pool_name уже существует"
            # Предлагаем варианты действий
            echo ""
            echo "Выберите действие для PHP-FPM пула '$fpm_pool_name':"
            echo "  1) Обновить пул (удалить старый и создать новый)"
            echo "  2) Использовать существующий пул (пропустить создание)"
            echo "  3) Использовать другое имя для пула"
            echo "  4) Прервать установку"

            while true; do
                read -p "Введите номер варианта (1-4): " pool_action
                case "$pool_action" in
                    1)
                        info "Обновление PHP-FPM пула '$fpm_pool_name'..."

                        # Удаляем старый пул
                        safe_execute "rm -f '/etc/php/$php_version/fpm/pool.d/$fpm_pool_name.conf'" "Удаление старого PHP-FPM пула" 0

                        # Перезагружаем PHP-FPM
                        if systemctl is-active --quiet "php$php_version-fpm"; then
                            safe_systemctl "reload" "php$php_version-fpm" "Перезагрузка PHP-FPM после удаления пула"
                        fi

                        info "Старый PHP-FPM пул удален. Будет создан новый."
                        break
                        ;;
                    2)
                        info "Используем существующий PHP-FPM пул '$fpm_pool_name'"
                        SKIP_FPM_POOL_CREATION=1
                        break
                        ;;
                    3)
                        read -p "Введите новое имя для PHP-FPM пула: " new_fpm_pool_name
                        if validate_project_name "$new_fpm_pool_name"; then
                            # Проверяем, не существует ли уже новый пул
                            if [ -f "/etc/php/$php_version/fpm/pool.d/$new_fpm_pool_name.conf" ]; then
                                warn "PHP-FPM пул '$new_fpm_pool_name' также уже существует"
                                read -p "Попробовать другое имя? (Y/n): " try_another
                                if [[ $try_another =~ ^[Nn]$ ]]; then
                                    continue
                                fi
                            else
                                fpm_pool_name="$new_fpm_pool_name"
                                info "Имя PHP-FPM пула изменено на: $fpm_pool_name"
                                break
                            fi
                        else
                            warn "Некорректное имя пула, попробуйте снова"
                        fi
                        ;;
                    4)
                        critical_error "Установка прервана пользователем"
                        ;;
                    *)
                        warn "Неверный выбор. Попробуйте снова."
                        ;;
                esac
            done
        else
            SKIP_FPM_POOL_CREATION=0
        fi
    fi
fi

# Показываем конфигурацию и подтверждаем
echo ""
info "Параметры проекта:"
echo "  Имя: $project_name"
echo "  Домен: $domain"
echo "  Тип: $project_type"
echo "  Окружение: $environment"
is_php && echo "  Версия PHP: $php_version"
echo "  Директория: /var/www/$project_name"
[ "$use_git" = "y" ] && echo "  GitHub: $repo_url ($git_branch)"
[ "$project_type" = "bitrix" ] && echo "  Способ установки Bitrix: $bitrix_install_method"
[ "$create_db" = "y" ] && echo "  Будет создана БД MySQL"
is_php && echo "  PHP-FPM пул: $fpm_pool_name"
[ "$mode" = "rebuild" ] && echo "  РЕЖИМ: ПЕРЕСБОРКА СУЩЕСТВУЮЩЕГО ПРОЕКТА"

read -p "Продолжить установку? (y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    critical_error "Установка отменена пользователем"
fi

echo ""
step "Начало установки..."

# Создание директорий (только для новой установки)
project_dir="/var/www/$project_name"
if [ "$mode" = "install" ]; then
    safe_mkdir "$project_dir" "Создание корневой директории проекта"
    safe_chmod "$project_dir" "775" "Установка прав корневой директории проекта"
fi

# Установка Bitrix24 (только для новой установки)
if [ "$mode" = "install" ] && [ "$project_type" = "bitrix" ]; then
    step "Установка Bitrix24..."

    case "$bitrix_install_method" in
        1)
            # Клонирование из GitHub
            safe_execute "git clone -b '$git_branch' '$repo_url' '$project_dir'" "Клонирование Bitrix24 из GitHub" 0
            ;;
        2)
            # Скачивание дистрибутива
            bitrix_info "Скачивание дистрибутива Bitrix24..."
            safe_execute "wget -O /tmp/bitrix.tar.gz 'https://www.1c-bitrix.ru/download/scripts/bitrix_server_test.php'" "Скачивание Bitrix24" 0
            if [ $? -eq 0 ]; then
                safe_execute "tar -xzf /tmp/bitrix.tar.gz -C '$project_dir' --strip-components=1" "Распаковка Bitrix24" 0
                safe_execute "rm -f /tmp/bitrix.tar.gz" "Удаление временного файла" 0
            fi
            ;;
        3)
            bitrix_info "Установка Bitrix24 Virtual Appliance..."
            warn "Этот метод требует ручной установки. Подготовьте VM образ."
            ;;
        4)
            info "Ручная установка - убедитесь что файлы Bitrix24 находятся в $project_dir"
            ;;
    esac

    if [ $ERROR_OCCURRED -eq 0 ] || [ $SKIP_STEP -eq 0 ]; then
        # Создание необходимых директорий для Bitrix
        safe_mkdir "$project_dir/upload" "Создание директории upload для Bitrix"
        safe_mkdir "$project_dir/bitrix/cache" "Создание директории cache для Bitrix"
        safe_mkdir "$project_dir/bitrix/managed_cache" "Создание директории managed_cache для Bitrix"
        safe_mkdir "$project_dir/bitrix/stack_cache" "Создание директории stack_cache для Bitrix"
        safe_mkdir "$project_dir/bitrix/html_pages" "Создание директории html_pages для Bitrix"

        # Права доступа для Bitrix
        safe_chown "$project_dir" "Настройка прав доступа для Bitrix"
        safe_execute "find '$project_dir' -type f -exec chmod 644 {} \;" "Установка прав файлов Bitrix" 0
        safe_execute "find '$project_dir' -type d -exec chmod 755 {} \;" "Установка прав директорий Bitrix" 0
        safe_chmod "$project_dir/upload" "775" "Установка прав для upload"
        safe_chmod "$project_dir/bitrix/cache" "775" "Установка прав для cache"
        safe_chmod "$project_dir/bitrix/managed_cache" "775" "Установка прав для managed_cache"
        safe_chmod "$project_dir/bitrix/stack_cache" "775" "Установка прав для stack_cache"
        safe_chmod "$project_dir/bitrix/html_pages" "775" "Установка прав для html_pages"

        bitrix_info "Созданы директории и установлены права доступа"
    fi
fi

# Клонирование репозитория для других проектов (только для новой установки)
if [ "$mode" = "install" ] && [ "$use_git" = "y" ] && [ "$project_type" != "bitrix" ]; then
    step "Клонирование репозитория..."
    if [ -d "$project_dir/.git" ]; then
        warn "Директория уже содержит git репозиторий, пропускаем клонирование"
    else
        safe_execute "git clone -b '$git_branch' '$repo_url' '$project_dir'" "Клонирование репозитория" 0
        if [ $? -eq 0 ]; then
            safe_chown "$project_dir" "Настройка прав после клонирования"
        fi
    fi
fi

# Настройка Git workflow (только для новой установки)
if [ "$mode" = "install" ]; then
    setup_git_workflow "$project_type" "$environment" "$project_dir"
fi

# Создание PHP-FPM пула
if is_php; then
    step "Настройка PHP-FPM пула..."

    if [ "${SKIP_FPM_POOL_CREATION:-0}" -eq 1 ]; then
        info "Пропускаем создание PHP-FPM пула (используем существующий)"
    else
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

        safe_execute "cat > '$fpm_pool_conf' << EOF
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
env[APP_DEBUG] = $([ \"$environment\" = \"dev\" ] && echo \"true\" || echo \"false\")
EOF" "Создание PHP-FPM конфигурации" 1

        # Перезагрузка PHP-FPM
        if systemctl is-active --quiet "php$php_version-fpm"; then
            systemctl reload "php$php_version-fpm"
            info "PHP-FPM $php_version перезагружен"
        else
            warn "Служба PHP-FPM $php_version не запущена, требуется перезапуск вручную"
        fi
    fi
fi

# Настройка Nginx
step "Настройка Nginx..."
nginx_conf="/etc/nginx/sites-available/$project_name"

# Общие настройки в зависимости от окружения
if [ "$environment" = "dev" ]; then
    # Для разработки - более детальное логирование с кастомным форматом
    access_log="access_log /var/log/nginx/${project_name}_access.log custom_dev buffer=64k flush=1m;"
    error_log="error_log /var/log/nginx/${project_name}_error.log debug;"
else
    # Для продакшена - стандартный комбинированный формат
    access_log="access_log /var/log/nginx/${project_name}_access.log combined buffer=256k flush=5m;"
    error_log="error_log /var/log/nginx/${project_name}_error.log warn;"
fi

nginx_custom_logs="/etc/nginx/conf.d/custom_logs.conf"
if [ ! -f "$nginx_custom_logs" ]; then
    cat > "$nginx_custom_logs" << 'EOF'
# Кастомные форматы логов для dev окружения
log_format custom_dev '$remote_addr - $remote_user [$time_local] '
                      '"$request" $status $body_bytes_sent '
                      '"$http_referer" "$http_user_agent" '
                      'rt=$request_time uct="$upstream_connect_time" uht="$upstream_header_time" urt="$upstream_response_time"';

log_format custom_bitrix '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" "$http_x_forwarded_for" '
                         'rt=$request_time uct="$upstream_connect_time" uht="$upstream_header_time" urt="$upstream_response_time"';
EOF
fi

case $project_type in
    static)
        safe_execute "cat > '$nginx_conf' << EOF
server {
    listen 80;
    server_name $domain;
    root $project_dir;
    index index.html;

    $access_log
    $error_log

    location / {
        try_files \\\$uri \\\$uri/ =404;
    }
}
EOF" "Создание Nginx конфигурации для static" 1
        ;;

    php)
        safe_execute "cat > '$nginx_conf' << EOF
server {
    listen 80;
    server_name $domain;
    root $project_dir;
    index index.php index.html;

    $access_log
    $error_log

    location / {
        try_files \\\$uri \\\$uri/ /index.php?\\\$query_string;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_param SCRIPT_FILENAME \\\$realpath_root\\\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \\\$realpath_root;
    }

    location ~ /\\.ht {
        deny all;
    }
}
EOF" "Создание Nginx конфигурации для PHP" 1
        ;;

    laravel)
        root_dir="$project_dir/public"

        safe_execute "cat > '$nginx_conf' << EOF
server {
    listen 80;
    server_name $domain;
    root $root_dir;
    index index.php index.html;

    $access_log
    $error_log

    location / {
        try_files \\\$uri \\\$uri/ /index.php?\\\$query_string;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_param SCRIPT_FILENAME \\\$realpath_root\\\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \\\$realpath_root;
    }

    location ~ /\\.ht {
        deny all;
    }
}
EOF" "Создание Nginx конфигурации для Laravel" 1
        ;;

    symfony)
        root_dir="$project_dir/public"

        safe_execute "cat > '$nginx_conf' << EOF
server {
    listen 80;
    server_name $domain;
    root $root_dir;
    index index.php index.html;

    $access_log
    $error_log

    location / {
        try_files \\\$uri /index.php\\\$is_args\\\$args;
    }

    location ~ ^/index\\.php(/|\$) {
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_split_path_info ^(.+\\.php)(/.*)\$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \\\$realpath_root\\\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \\\$realpath_root;
        internal;
    }

    location ~ \\.php\$ {
        return 404;
    }

    location ~ /\\.ht {
        deny all;
    }
}
EOF" "Создание Nginx конфигурации для Symfony" 1
        ;;

    bitrix)
        if [ "$environment" = "dev" ]; then
            bitrix_access_log="access_log /var/log/nginx/${project_name}_access.log custom_bitrix buffer=64k flush=1m;"
        else
            bitrix_access_log="access_log /var/log/nginx/${project_name}_access.log combined buffer=256k flush=5m;"
        fi

        safe_execute "cat > '$nginx_conf' << EOF
server {
    listen 80;
    server_name $domain;
    root $project_dir;
    index index.php index.html;

    $bitrix_access_log
    $error_log

    # Основные настройки для Bitrix
    client_max_body_size 128M;
    fastcgi_read_timeout 600;

    # Статические файлы
    location ~* \\.(?:css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control \"public, immutable\";
        try_files \\\$uri =404;
    }

    # Bitrix URL rewriting
    location / {
        try_files \\\$uri \\\$uri/ /bitrix/urlrewrite.php;
    }

    # Обработка PHP
    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_param SCRIPT_FILENAME \\\$realpath_root\\\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \\\$realpath_root;

        # Дополнительные параметры для Bitrix
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    # Запрет доступа к системным файлам
    location ~ /\\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~ /(upload|bitrix/modules|bitrix/php_interface|bitrix/templates|bitrix/wizards)/.*\\.php\$ {
        deny all;
    }

    # Особые правила для Bitrix
    location = /bitrix/urlrewrite.php {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-$fpm_pool_name.sock;
        fastcgi_param SCRIPT_FILENAME \\\$realpath_root\\\$fastcgi_script_name;
    }

    location ~* /\\.ht {
        deny all;
    }
}
EOF" "Создание Nginx конфигурации для Bitrix" 1
        ;;

    nodejs)
        safe_execute "cat > '$nginx_conf' << EOF
server {
    listen 80;
    server_name $domain;

    $access_log
    $error_log

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_cache_bypass \\\$http_upgrade;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF" "Создание Nginx конфигурации для Node.js" 1
        warn "Node.js проект настроен на порт 3000. Убедитесь, что приложение запущено"
        ;;
esac

# Активация сайта
if [ $? -eq 0 ]; then
    safe_execute "ln -sf '/etc/nginx/sites-available/$project_name' '/etc/nginx/sites-enabled/'" "Активация сайта Nginx" 1
    safe_nginx_test
    if [ $? -eq 0 ]; then
        safe_systemctl "reload" "nginx" "Перезагрузка Nginx"
    fi
fi

# Создание БД (только для новой установки)
if [ "$mode" = "install" ] && [ "$create_db" = "y" ] && ([ $ERROR_OCCURRED -eq 0 ] || [ $SKIP_STEP -eq 0 ]); then
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
    safe_execute "mysql -e 'SELECT 1'" "Проверка подключения к MySQL" 0

    # Проверка существования БД
    safe_execute "! mysql -e 'USE $db_name' 2>/dev/null" "Проверка отсутствия БД $db_name" 0

    safe_execute "mysql -e 'CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'" "Создание БД $db_name" 0
    safe_execute "mysql -e \"CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';\"" "Создание пользователя БД" 0
    safe_execute "mysql -e 'GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '\"'$db_user'\"'@'\''localhost'\'';'" "Назначение прав пользователю" 0
    safe_execute "mysql -e 'FLUSH PRIVILEGES;'" "Применение привилегий" 0

    if [ $? -eq 0 ]; then
        info "Создана БД: $db_name"
        info "Пользователь БД: $db_user"
        info "Пароль БД: $db_pass"

        # Создание файла с данными БД
        safe_execute "cat > '$project_dir/database_credentials.txt' << EOF
Окружение: $environment
База данных: $db_name
Пользователь: $db_user
Пароль: $db_pass
Хост: localhost
EOF" "Создание файла с данными БД" 0

        if [ $? -eq 0 ]; then
            safe_chmod "$project_dir/database_credentials.txt" "600"
            safe_chown "$project_dir/database_credentials.txt"
            warn "Данные БД сохранены в $project_dir/database_credentials.txt"
        fi
    fi

    # Для Bitrix создаем дополнительный файл с настройками
    if [ "$project_type" = "bitrix" ]; then
        bitrix_db_file="$project_dir/bitrix/.settings.php"
        if [ ! -f "$bitrix_db_file" ]; then
            mkdir -p "$project_dir/bitrix"
            safe_execute "cat > '$bitrix_db_file' << 'EOF'
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
EOF" "Для Bitrix создаем дополнительный файл с настройками" 0
            # Заменяем плейсхолдеры на реальные значения
            sed -i "s/DB_NAME/$db_name/g" "$bitrix_db_file"
            sed -i "s/DB_USER/$db_user/g" "$bitrix_db_file"
            sed -i "s/DB_PASSWORD/$db_pass/g" "$bitrix_db_file"
            safe_chown "$bitrix_db_file"
        fi
    fi
fi

# Установка Composer зависимостей для PHP проектов
if [ "$mode" = "install" ] && is_php; then
    step "Установка Composer зависимостей..."

    # Определяем флаги для composer в зависимости от окружения
    composer_flags=""
    if [ "$environment" = "prod" ]; then
        composer_flags="--no-dev --optimize-autoloader --no-interaction"
    else
        composer_flags="--no-interaction"
    fi

    # Проверяем наличие composer.json
    if [ -f "$project_dir/composer.json" ]; then
        info "Найден composer.json, устанавливаем зависимости..."

        # Определяем пользователя для запуска composer
        if [ "$environment" = "dev" ]; then
            COMPOSER_USER="$SUDO_USER"
        else
            COMPOSER_USER="www-data"
        fi

        # Устанавливаем зависимости
        safe_execute "cd '$project_dir' && sudo -u $COMPOSER_USER composer install $composer_flags" "Установка Composer зависимостей" 0

        if [ $? -eq 0 ]; then
            info "Composer зависимости успешно установлены"
            
            # Обновляем права после установки зависимостей
            safe_chown "$project_dir" "Обновление прав после установки зависимостей"
        fi
    else
        info "composer.json не найден, пропускаем установку зависимостей"
    fi
fi

# Дополнительные настройки для фреймворков с учетом окружения
case "$project_type" in
    laravel)
        step "Настройка Laravel..."

        # Проверка существования composer.json
        if [ -f "$project_dir/composer.json" ]; then
            # Установка прав для storage и bootstrap/cache
            safe_chown "$project_dir/storage" "Настройка прав для storage"
            safe_chown "$project_dir/bootstrap/cache" "Настройка прав для bootstrap/cache"
            safe_chmod "$project_dir/storage" "775" "Установка прав для storage"
            safe_chmod "$project_dir/bootstrap/cache" "775" "Установка прав для bootstrap/cache"

            # Создание .env файла (только для новой установки)
            if [ "$mode" = "install" ] && [ ! -f "$project_dir/.env" ]; then
                if [ -f "$project_dir/.env.example" ]; then
                    safe_execute "cp '$project_dir/.env.example' '$project_dir/.env'" "Копирование .env примера" 0
                else
                    # Создаем базовый .env
                    safe_execute "cat > '$project_dir/.env' << EOF
APP_NAME=\"$project_name\"
APP_ENV=$environment
APP_KEY=
APP_DEBUG=$([ \"$environment\" = \"dev\" ] && echo \"true\" || echo \"false\")
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
MAIL_FROM_NAME=\"\\\${APP_NAME}\"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=

PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_APP_CLUSTER=mt1

MIX_PUSHER_APP_KEY=\"\\\${PUSHER_APP_KEY}\"
MIX_PUSHER_APP_CLUSTER=\"\\\${PUSHER_APP_CLUSTER}\"
EOF" "Создание .env файла" 0
                fi
                if [ $? -eq 0 ]; then
                    safe_chown "$project_dir/.env"
                    # Генерируем ключ приложения
                    safe_execute "cd '$project_dir' && sudo -u www-data /usr/bin/php$php_version artisan key:generate" "Генерация ключа приложения Laravel" 0
                    warn "Создан .env файл для окружения $environment"
                fi
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
            safe_chown "$project_dir/var"
            safe_chown "$project_dir/config"
            safe_chmod "$project_dir/var" "775"
            safe_chmod "$project_dir/config" "775"

            # Копирование .env файла если его нет (только для новой установки)
            if [ "$mode" = "install" ] && [ ! -f "$project_dir/.env" ] && { [ -f "$project_dir/.env.example" ] || [ -f "$project_dir/.env.dist" ]; }; then
                if [ -f "$project_dir/.env.example" ]; then
                    cp $project_dir/.env.example $project_dir/.env
                elif [ -f "$project_dir/.env.dist" ]; then
                    cp $project_dir/.env.dist $project_dir/.env
                fi
                safe_chown "$project_dir/.env"

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
	        safe_execute "cat > '$bitrix_php_ini' << EOF
; Настройки PHP для Bitrix24 - $project_name
memory_limit = 512M
upload_max_filesize = 128M
post_max_size = 128M
max_execution_time = 120
max_input_time = 60
max_input_vars = 10000
date.timezone = Europe/Moscow

; Настройки в зависимости от окружения
display_errors = $([ \"$environment\" = \"dev\" ] && echo \"On\" || echo \"Off\")
error_reporting = $([ \"$environment\" = \"dev\" ] && echo \"E_ALL\" || echo \"E_ALL & ~E_DEPRECATED\")

; Настройки OPcache для Bitrix
opcache.memory_consumption = 256
opcache.max_accelerated_files = 20000
opcache.revalidate_freq = 2
opcache.enable_cli = 1

; Отключение ограничений для Bitrix
disable_functions =
safe_mode = Off
EOF" "Создание php.ini для Bitrix" 0

            if [ $? -eq 0 ]; then
                safe_systemctl "reload" "php$php_version-fpm" "Перезагрузка PHP-FPM после настройки Bitrix"
                bitrix_info "Создан оптимизированный php.ini для Bitrix24"
            fi
        fi

        # Создаем cron задания для Bitrix
        bitrix_cron="/etc/cron.d/bitrix-$project_name"
        safe_execute "cat > '$bitrix_cron' << EOF
# Cron задания для Bitrix24 - $project_name
*/5 * * * * www-data /usr/bin/php$php_version $project_dir/bitrix/modules/main/tools/cron_events.php
*/10 * * * * www-data /usr/bin/php$php_version $project_dir/bitrix/php_interface/include/catalog_export/cron_frame.php
0 */2 * * * www-data /usr/bin/php$php_version $project_dir/bitrix/php_interface/include/catalog_export/cron_run.php

# Очистка кеша для dev окружения
$([ \"$environment\" = \"dev\" ] && echo \"*/15 * * * * www-data rm -rf $project_dir/bitrix/cache/* $project_dir/bitrix/managed_cache/*\")
EOF" "Создание cron заданий для Bitrix" 0

        if [ $? -eq 0 ]; then
            safe_chmod "$bitrix_cron" "644"
            bitrix_info "Добавлены cron задания для Bitrix24"
        fi

        # Создаем конфигурационный файл для разных окружений
        bitrix_env_config="$project_dir/bitrix/configuration.php"
        if [ ! -f "$bitrix_env_config" ]; then
            safe_execute "cat > '$bitrix_env_config' << EOF
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
EOF" "Создаем конфигурационный файл для разных окружений Bitrix" 0
            safe_chown "$bitrix_env_config"
        fi
        ;;
esac

# Создание деплой скрипта для проекта
deploy_script="$project_dir/deploy.sh"
safe_execute "cat > '$deploy_script' << 'EOF'
#!/bin/bash
# Скрипт деплоя для $project_name

ENV=\\\${1:-$environment}
cd $project_dir

echo \"Деплой проекта $project_name в окружении: \\\$ENV\"

# Обновление кода
if [ -d \".git\" ]; then
    git fetch origin
    git reset --hard origin/\\\$([ \"\\\$ENV\" = \"prod\" ] && echo \"main\" || echo \"dev\")
fi

# Зависимости PHP проектов
case \"$project_type\" in
    laravel|symfony)
        # Установка/обновление композера
        if [ ! -f \"composer.phar\" ]; then
            curl -sS https://getcomposer.org/installer | php -- --install-dir=.
        fi

        # Установка зависимостей
        if [ \"$project_type\" = \"laravel\" ]; then
            php composer.phar install --no-dev --optimize-autoloader
            php artisan config:cache
            php artisan route:cache
            php artisan view:cache
            php artisan migrate --force
        elif [ \"$project_type\" = \"symfony\" ]; then
            php composer.phar install --no-dev --optimize-autoloader
            php bin/console cache:clear --env=\\\$ENV
            php bin/console cache:warmup --env=\\\$ENV
            php bin/console doctrine:migrations:migrate --no-interaction --env=\\\$ENV
        fi
        ;;

    bitrix)
        # Обновление Bitrix
        if [ -f \"bitrix/updates/update.php\" ]; then
            echo \"Проверка обновлений Bitrix24...\"
            /usr/bin/php$php_version bitrix/updates/update.php
        fi

        # Очистка кеша Bitrix
        if [ -d \"bitrix/cache\" ]; then
            rm -rf bitrix/cache/*
            rm -rf bitrix/managed_cache/*
            rm -rf bitrix/stack_cache/*
            rm -rf bitrix/html_pages/*
        fi
        ;;
esac

# Права доступа
chown -R $FILE_OWNER $project_dir
find $project_dir -type f -exec chmod 644 {} \\\\
find $project_dir -type d -exec chmod 755 {} \\\\

# Особые права для фреймворков
case \"$project_type\" in
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
if [ -f \"$project_dir/setup-environment.sh\" ]; then
    $project_dir/setup-environment.sh \\\$ENV
fi

# Перезагрузка PHP-FPM
systemctl reload php$php_version-fpm

echo \"Деплой проекта $project_name в окружении \\\$ENV завершен\"
EOF" "Создание скрипта деплоя" 0

if [ $? -eq 0 ]; then
    safe_chmod "$deploy_script" "+x"
    info "Создан скрипт деплоя: $deploy_script"
fi

# Создание скрипта пересборки
rebuild_script="$project_dir/rebuild.sh"
safe_execute "cat > '$rebuild_script' << 'EOF'
#!/bin/bash
# Скрипт пересборки проекта $project_name

echo \"Пересборка проекта $project_name...\"
echo \"Этот скрипт позволяет изменить конфигурацию проекта без потери данных.\"

# Запускаем основной скрипт в режиме пересборки
sudo \$(readlink -f \"\$0\") --rebuild

echo \"Пересборка завершена!\"
EOF" "Создание скрипта пересборки" 0

if [ $? -eq 0 ]; then
    safe_chmod "$rebuild_script" "+x"
    info "Создан скрипт пересборки: $rebuild_script"
fi

# Сохранение конфигурации проекта
save_project_config "$project_dir"

# Показываем сводку установки
echo ""
if [ $ERROR_OCCURRED -eq 0 ]; then
    info "=== Проект $project_name успешно настроен! ==="
else
    warn "=== Проект $project_name настроен с ошибками! ==="
    show_error_summary
fi

echo ""
echo "Данные проекта:"
echo "  Домен: http://$domain"
echo "  Окружение: $environment"
echo "  Директория: $project_dir"
[ "$create_db" = "y" ] && [ -n "$db_name" ] && echo "  База данных: $db_name"
is_php && echo "  Версия PHP: $php_version"
is_php && echo "  PHP-FPM пул: $fpm_pool_name"
echo ""
[ "$mode" = "rebuild" ] && rebuild_info "ПРОЕКТ ПЕРЕСОБРАН!" && echo ""

if [ $ERROR_OCCURRED -eq 0 ]; then
    echo "Git workflow:"
    echo "  - Создан .gitignore для $project_type"
    echo "  - Используйте ветку '$([ "$environment" = "prod" ] && echo "main" || echo "dev")' для этого окружения"
    echo ""
fi

echo "Следующие шаги:"
case "$project_type" in
    laravel)
        if [ -f "$project_dir/.env" ]; then
            echo "  - Ключ приложения уже сгенерирован"
        else
            echo "  - Настройте .env файл вручную"
        fi
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
echo "Управление проектом:"
[ -f "$project_dir/setup-environment.sh" ] && echo "  - Смена окружения: $project_dir/setup-environment.sh [dev|prod]"
[ -f "$deploy_script" ] && echo "  - Деплой: $deploy_script [dev|prod]"
[ -f "$rebuild_script" ] && echo "  - Пересборка: $rebuild_script"
[ -f "$project_dir/.deploy-config" ] && echo "  - Конфигурация: $project_dir/.deploy-config"
echo ""

if [ $ERROR_OCCURRED -eq 1 ]; then
    warn "ВНИМАНИЕ: Установка завершена с ошибками!"
    warn "Некоторые функции могут работать некорректно."
    echo ""
    read -p "Показать подробную сводку ошибок? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        show_error_summary
    fi
fi

[ "$environment" = "prod" ] && warn "ВНИМАНИЕ: Настроено PROD окружение! Убедитесь что debug режим выключен."
[ "$environment" = "dev" ] && info "Режим разработки активирован. Debug информация будет отображаться."

# Возвращаем соответствующий код выхода
if [ $ERROR_OCCURRED -eq 0 ]; then
    exit 0
else
    exit 1
fi
