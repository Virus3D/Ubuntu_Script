#!/bin/bash

# Установка линтеров для PHP, JS, CSS, HTML
# Включая PHPMD, Psalm, PHPStan
# Без использования sudo, с правильной настройкой прав

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Начинаем установку линтеров...${NC}"

# Определяем директорию где находится скрипт
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

# Проверка наличия Node.js и npm
if ! command -v node &> /dev/null; then
    echo -e "${RED}Node.js не найден. Установите Node.js сначала.${NC}"
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo -e "${RED}npm не найден. Установите npm сначала.${NC}"
    exit 1
fi

# Проверка наличия PHP
if ! command -v php &> /dev/null; then
    echo -e "${RED}PHP не найден. Установите PHP сначала.${NC}"
    exit 1
fi

# Проверка наличия Composer
if ! command -v composer &> /dev/null; then
    echo -e "${RED}Composer не найден. Установите Composer сначала.${NC}"
    exit 1
fi

# Получаем путь к глобальным Composer пакетам
COMPOSER_HOME=${COMPOSER_HOME:-$HOME/.config/composer}
COMPOSER_BIN="$COMPOSER_HOME/vendor/bin"

# Настройка npm для установки в домашнюю директорию
echo -e "${YELLOW}Настраиваем npm для установки в домашнюю директорию...${NC}"
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global

# Создаем директории если не существуют
mkdir -p "$COMPOSER_HOME"
mkdir -p "$COMPOSER_BIN"
mkdir -p ~/.npm-global/bin

# Функция для добавления пути в PATH
add_to_path() {
    local path_to_add="$1"
    if [[ ":$PATH:" != *":$path_to_add:"* ]]; then
        if [ -n "$BASH_VERSION" ]; then
            grep -q "export PATH.*$path_to_add" ~/.bashrc || echo "export PATH=\"$path_to_add:\$PATH\"" >> ~/.bashrc
        elif [ -n "$ZSH_VERSION" ]; then
            grep -q "export PATH.*$path_to_add" ~/.zshrc || echo "export PATH=\"$path_to_add:\$PATH\"" >> ~/.zshrc
        fi
    fi
}

# Добавляем пути
add_to_path "$HOME/.npm-global/bin"
add_to_path "$COMPOSER_BIN"

# Применяем изменения немедленно
export PATH="$HOME/.npm-global/bin:$COMPOSER_BIN:$PATH"

# Функция для установки npm пакетов
install_npm_global() {
    local package=$1
    echo -e "${YELLOW}Устанавливаем $package...${NC}"
    if npm install -g "$package"; then
        echo -e "${GREEN}$package успешно установлен!${NC}"
        return 0
    else
        echo -e "${RED}Ошибка установки $package!${NC}"
        return 1
    fi
}

# Функция для установки composer пакетов
install_composer_global() {
    local package=$1
    echo -e "${YELLOW}Устанавливаем $package...${NC}"

    # Устанавливаем в глобальную директорию Composer
    if composer global require "$package"; then
        echo -e "${GREEN}$package успешно установлен!${NC}"

        # Проверяем наличие бинарных файлов
        local package_name=$(echo "$package" | cut -d'/' -f2 | cut -d':' -f1)
        if [ -f "$COMPOSER_BIN/$package_name" ]; then
            echo -e "${GREEN}Бинарный файл $package_name найден в $COMPOSER_BIN${NC}"
        fi
        return 0
    else
        echo -e "${RED}Ошибка установки $package!${NC}"
        return 1
    fi
}

# Установка ESLint (JavaScript)
install_npm_global "eslint"

# Установка Stylelint (CSS)
install_npm_global "stylelint"
install_npm_global "stylelint-config-standard"

# Установка HTMLHint (HTML)
install_npm_global "htmlhint"

# Предварительная настройка Composer для автоматического подтверждения
echo -e "${YELLOW}Настраиваем Composer для автоматической установки...${NC}"
composer global config --no-interaction allow-plugins.dealerdirect/phpcodesniffer-composer-installer true
composer global config --no-interaction allow-plugins.squizlabs/php_codesniffer true

# Установка PHP инструментов
echo -e "${YELLOW}Устанавливаем PHP инструменты...${NC}"

# PHP Code Sniffer
install_composer_global "squizlabs/php_codesniffer"
install_composer_global "slevomat/coding-standard"

# PHP-CS-Fixer
install_composer_global "friendsofphp/php-cs-fixer"

# PHPMD (PHP Mess Detector)
install_composer_global "phpmd/phpmd"

# Psalm
install_composer_global "vimeo/psalm"

# PHPStan
install_composer_global "phpstan/phpstan"
install_composer_global "phpstan/phpstan-doctrine"
install_composer_global "spaze/phpstan-disallowed-calls"
install_composer_global "ergebnis/phpstan-rules"
install_composer_global "phpstan/phpstan-deprecation-rules"
install_composer_global "slam/phpstan-extensions"
install_composer_global "shipmonk/phpstan-rules"
install_composer_global "shipmonk/dead-code-detector"
install_composer_global "staabm/phpstan-todo-by"

# Копируем дополнительные конфиги
echo -e "${YELLOW}Копируем дополнительные конфиги...${NC}"

# Создаем алиасы для удобства
if [ -n "$BASH_VERSION" ]; then
    cat >> ~/.bashrc << 'EOF'

# Алиасы для линтеров
alias lint-js='eslint'
alias lint-css='stylelint'
alias lint-html='htmlhint'
alias lint-php='phpcs'
alias fix-php='php-cs-fixer fix'
alias analyze-php='phpmd'
alias check-types='psalm'
alias static-analysis='phpstan analyse'

# Пути к инструментам
export COMPOSER_HOME="$HOME/.config/composer"
export PATH="$HOME/.npm-global/bin:$COMPOSER_HOME/vendor/bin:$PATH"
EOF
elif [ -n "$ZSH_VERSION" ]; then
    cat >> ~/.zshrc << 'EOF'

# Алиасы для линтеров
alias lint-js='eslint'
alias lint-css='stylelint'
alias lint-html='htmlhint'
alias lint-php='phpcs'
alias fix-php='php-cs-fixer fix'
alias analyze-php='phpmd'
alias check-types='psalm'
alias static-analysis='phpstan analyse'

# Пути к инструментам
export COMPOSER_HOME="$HOME/.config/composer"
export PATH="$HOME/.npm-global/bin:$COMPOSER_HOME/vendor/bin:$PATH"
EOF
fi

# Применяем изменения
if [ -n "$BASH_VERSION" ]; then
    source ~/.bashrc
elif [ -n "$ZSH_VERSION" ]; then
    source ~/.zshrc
fi

echo -e "${GREEN}Установка завершена!${NC}"
echo ""

# Проверка установки
echo -e "${YELLOW}Проверка установленных инструментов:${NC}"

check_tool() {
    local tool=$1
    local path=$2
    if command -v "$tool" &> /dev/null; then
        echo -e "${GREEN}✓ $tool установлен ($(which $tool))${NC}"
        return 0
    elif [ -n "$path" ] && [ -f "$path" ]; then
        echo -e "${GREEN}✓ $tool установлен ($path)${NC}"
        return 0
    else
        echo -e "${RED}✗ $tool не установлен${NC}"
        return 1
    fi
}

check_tool "eslint"
check_tool "stylelint"
check_tool "htmlhint"
check_tool "phpcs" "$COMPOSER_BIN/phpcs"
check_tool "php-cs-fixer" "$COMPOSER_BIN/php-cs-fixer"
check_tool "phpmd" "$COMPOSER_BIN/phpmd"
check_tool "psalm" "$COMPOSER_BIN/psalm"
check_tool "phpstan" "$COMPOSER_BIN/phpstan"

echo ""
echo -e "${YELLOW}Для применения изменений в текущей сессии выполните:${NC}"
echo "source ~/.bashrc  # для bash"
echo "source ~/.zshrc   # для zsh"
echo ""
echo -e "${YELLOW}Или перезапустите терминал.${NC}"

# Создаем скрипт для ручного добавления в PATH
cat > ~/add-linters-to-path.sh << 'EOF'
#!/bin/bash
echo "Добавляем пути линтеров в текущую сессию..."
export PATH="$HOME/.npm-global/bin:$HOME/.config/composer/vendor/bin:$PATH"
echo "Готово! Пути добавлены в текущую сессию."
echo "Для постоянного добавления выполните: source ~/.bashrc или source ~/.zshrc"
EOF

chmod +x ~/add-linters-to-path.sh

echo ""
echo -e "${GREEN}Создан скрипт для ручного добавления в PATH: ~/add-linters-to-path.sh${NC}"
echo "Используйте: source ~/add-linters-to-path.sh"

echo ""
echo -e "${YELLOW}Примеры использования:${NC}"
echo "ESLint (JavaScript): eslint file.js"
echo "Stylelint (CSS): stylelint file.css"
echo "HTMLHint (HTML): htmlhint file.html"
echo "PHP Code Sniffer: phpcs file.php"
echo "PHP-CS-Fixer: php-cs-fixer fix file.php"
echo "PHPMD: phpmd file.php text ~/.phpmd.xml"
echo "Psalm: psalm"
echo "PHPStan: phpstan analyse file.php"