#!/bin/bash

# Скрипт для комплексной проверки проекта
# save как check-project.sh

PROJECT_DIR=${1:-.}

echo "🔍 Запуск комплексной проверки проекта в: $PROJECT_DIR"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Пути к инструментам
NPM_BIN="$HOME/.npm-global/bin"
COMPOSER_BIN="$HOME/.config/composer/vendor/bin"
LOCAL_BIN="$HOME/.local/bin"

# Функция проверки команды с поиском в альтернативных путях
check_command() {
    local cmd=$1
    if command -v "$cmd" &> /dev/null; then
        return 0
    elif [ -f "$COMPOSER_BIN/$cmd" ]; then
        return 0
    elif [ -f "$NPM_BIN/$cmd" ]; then
        return 0
    elif [ -f "$LOCAL_BIN/$cmd" ]; then
        return 0
    else
        return 1
    fi
}

# Функция выполнения команды с поиском в альтернативных путях
run_command() {
    local cmd=$1
    shift
    local args=("$@")
    
    if command -v "$cmd" &> /dev/null; then
        "$cmd" "${args[@]}"
    elif [ -f "$COMPOSER_BIN/$cmd" ]; then
        "$COMPOSER_BIN/$cmd" "${args[@]}"
    elif [ -f "$NPM_BIN/$cmd" ]; then
        "$NPM_BIN/$cmd" "${args[@]}"
    elif [ -f "$LOCAL_BIN/$cmd" ]; then
        "$LOCAL_BIN/$cmd" "${args[@]}"
    else
        echo -e "${RED}Команда $cmd не найдена${NC}"
        return 1
    fi
}

# Функция подсчета файлов для проверки
count_files() {
    local pattern=$1
    local exclude=$2
    if [ -d "$PROJECT_DIR" ]; then
        find "$PROJECT_DIR" -name "$pattern" -not -path "$exclude" 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

# Вывод статистики файлов
echo -e "${BLUE}📊 Статистика файлов:${NC}"
php_files=$(count_files '*.php' '*/vendor/*')
js_files=$(count_files '*.js' '*/node_modules/*')
css_files=$(count_files '*.css' '*/node_modules/*')
html_files=$(count_files '*.html' '')

echo "PHP: $php_files файлов, JavaScript: $js_files файлов, CSS: $css_files файлов, HTML: $html_files файлов"

# Проверка PHP файлов
if [ "$php_files" -gt 0 ]; then
    echo -e "\n${YELLOW}=== PHP ПРОВЕРКА ===${NC}"
    
    # PHP Code Sniffer
    if check_command phpcs; then
        echo -e "\n📝 PHP Code Sniffer:"
        run_command phpcs "$PROJECT_DIR" --standard=PSR12 --extensions=php --ignore=*/vendor/* --colors 2>/dev/null || echo -e "${YELLOW}PHPCS: ошибки или предупреждения${NC}"
    else
        echo -e "${RED}❌ PHP Code Sniffer не установлен${NC}"
    fi
    
    # PHPMD
    if check_command phpmd; then
        echo -e "\n🔍 PHP Mess Detector:"
        # Проверяем только первые 3 файла чтобы не перегружать вывод
        find "$PROJECT_DIR" -name '*.php' -not -path '*/vendor/*' | head -n 3 | while read -r file; do
            echo -e "${BLUE}Проверка: $file${NC}"
            run_command phpmd "$file" text ~/.phpmd.xml 2>/dev/null || true
        done
        if [ "$php_files" -gt 3 ]; then
            echo -e "${YELLOW}... и еще $((php_files - 3)) файлов${NC}"
        fi
    else
        echo -e "${RED}❌ PHPMD не установлен${NC}"
    fi
    
    # PHPStan
    if check_command phpstan; then
        echo -e "\n🎯 PHPStan:"
        run_command phpstan analyse "$PROJECT_DIR" --level=5 --no-progress --error-format=table 2>/dev/null || echo -e "${YELLOW}PHPStan: завершено с предупреждениями${NC}"
    else
        echo -e "${RED}❌ PHPStan не установлен${NC}"
    fi
    
    # Psalm
    if check_command psalm; then
        echo -e "\n📖 Psalm:"
        if [ -f "$PROJECT_DIR/psalm.xml" ] || [ -f "$PROJECT_DIR/psalm.xml.dist" ]; then
            run_command psalm --no-progress --output-format=console 2>/dev/null || echo -e "${YELLOW}Psalm: завершено с предупреждениями${NC}"
        else
            echo -e "${YELLOW}📄 Конфиг Psalm не найден, создаем базовый...${NC}"
            run_command psalm --init "$PROJECT_DIR" 2>/dev/null
            if [ -f "$PROJECT_DIR/psalm.xml" ]; then
                run_command psalm --no-progress --output-format=console 2>/dev/null || echo -e "${YELLOW}Psalm: завершено с предупреждениями${NC}"
            fi
        fi
    else
        echo -e "${RED}❌ Psalm не установлен${NC}"
    fi
    
    # PHP-CS-Fixer (проверка без исправления)
    if check_command php-cs-fixer; then
        echo -e "\n✨ PHP-CS-Fixer (dry-run):"
        run_command php-cs-fixer fix --dry-run --diff --using-cache=no --rules=@PSR12 "$PROJECT_DIR" 2>/dev/null || echo -e "${YELLOW}Требуется форматирование кода${NC}"
    fi
fi

# Проверка JavaScript
if [ "$js_files" -gt 0 ]; then
    echo -e "\n${YELLOW}=== JAVASCRIPT ПРОВЕРКА ===${NC}"
    if check_command eslint; then
        echo -e "\n📝 ESLint:"
        # Проверяем только первые 3 файла
        find "$PROJECT_DIR" -name '*.js' -not -path '*/node_modules/*' | head -n 3 | while read -r file; do
            echo -e "${BLUE}Проверка: $file${NC}"
            run_command eslint "$file" -c ~/.eslintrc.js --color 2>/dev/null || echo -e "${YELLOW}Найдены проблемы в $file${NC}"
        done
        if [ "$js_files" -gt 3 ]; then
            echo -e "${YELLOW}... и еще $((js_files - 3)) файлов${NC}"
        fi
    else
        echo -e "${RED}❌ ESLint не установлен${NC}"
    fi
fi

# Проверка CSS
if [ "$css_files" -gt 0 ]; then
    echo -e "\n${YELLOW}=== CSS ПРОВЕРКА ===${NC}"
    if check_command stylelint; then
        echo -e "\n🎨 Stylelint:"
        find "$PROJECT_DIR" -name '*.css' -not -path '*/node_modules/*' | head -n 3 | while read -r file; do
            echo -e "${BLUE}Проверка: $file${NC}"
            run_command stylelint "$file" --config ~/.stylelintrc.json --color 2>/dev/null || echo -e "${YELLOW}Найдены проблемы в $file${NC}"
        done
        if [ "$css_files" -gt 3 ]; then
            echo -e "${YELLOW}... и еще $((css_files - 3)) файлов${NC}"
        fi
    else
        echo -e "${RED}❌ Stylelint не установлен${NC}"
    fi
fi

# Проверка HTML
if [ "$html_files" -gt 0 ]; then
    echo -e "\n${YELLOW}=== HTML ПРОВЕРКА ===${NC}"
    if check_command htmlhint; then
        echo -e "\n🌐 HTMLHint:"
        find "$PROJECT_DIR" -name '*.html' | head -n 3 | while read -r file; do
            echo -e "${BLUE}Проверка: $file${NC}"
            run_command htmlhint "$file" -c ~/.htmlhintrc --color 2>/dev/null || echo -e "${YELLOW}Найдены проблемы в $file${NC}"
        done
        if [ "$html_files" -gt 3 ]; then
            echo -e "${YELLOW}... и еще $((html_files - 3)) файлов${NC}"
        fi
    else
        echo -e "${RED}❌ HTMLHint не установлен${NC}"
    fi
fi

# Сводка
echo -e "\n${GREEN}✅ Проверка завершена!${NC}"
echo -e "\n${BLUE}📈 Сводка:${NC}"
echo "PHP файлов проверено: $php_files"
echo "JavaScript файлов проверено: $((js_files > 3 ? 3 : js_files)) из $js_files"
echo "CSS файлов проверено: $((css_files > 3 ? 3 : css_files)) из $css_files"
echo "HTML файлов проверено: $((html_files > 3 ? 3 : html_files)) из $html_files"

# Рекомендации
echo -e "\n${YELLOW}💡 Рекомендации:${NC}"
if [ "$php_files" -gt 0 ]; then
    echo "Для исправления PHP стиля: php-cs-fixer fix $PROJECT_DIR"
    echo "Для автоматического исправления PHPCS: phpcbf $PROJECT_DIR --standard=PSR12"
fi
if [ "$js_files" -gt 0 ]; then
    echo "Для автоматического исправления ESLint: eslint --fix $PROJECT_DIR"
fi
if [ "$css_files" -gt 0 ]; then
    echo "Для автоматического исправления Stylelint: stylelint --fix $PROJECT_DIR"
fi