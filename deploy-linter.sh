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

# Проверяем наличие папки config
if [ ! -d "$CONFIG_DIR" ]; then
    echo -e "${RED}Папка config не найдена! Создайте папку config с конфигами.${NC}"
    exit 1
fi

echo -e "${GREEN}Папка config найдена: $CONFIG_DIR${NC}"

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

# Функция для копирования конфигурационных файлов
copy_config_file() {
    local config_name=$1
    local source_file=$2
    local destination=$3

    echo -e "${YELLOW}Копируем конфиг $config_name...${NC}"

    if [ -f "$source_file" ]; then
        # Копирование с перезаписью и сохранением атрибутов
        cp -af "$source_file" "$destination" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Конфиг '$config_name' успешно скопирован!${NC}"
            return 0
        else
            echo -e "${RED}Ошибка при копировании конфига '$config_name'${NC}"
            return 1
        fi
    else
        echo -e "${RED}Конфиг '$config_name' не найден: '$source_file'${NC}"
        return 1
    fi
}

copy_config_dir() {
    local source_dir="$1"
    local destination="$2"

    echo -e "${YELLOW}Копируем из директории '$source_dir' в '$destination'...${NC}"

    # Проверяем, что источник существует и является директорией
    if [ ! -d "$source_dir" ]; then
        echo -e "${RED}Директория не найдена: '$source_dir'${NC}"
        return 1
    fi

    # Копирование с сохранением всех атрибутов (права, время, симлинки)
    cp -a "$source_dir" "$destination" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Директория '$source_dir' успешно скопирована!${NC}"
        return 0
    else
        echo -e "${RED}Ошибка при копировании директории '$source_dir'${NC}"
        return 1
    fi
}

# Установка ESLint (JavaScript)
install_npm_global "eslint"

# Копируем конфиг ESLint
copy_config_file "ESLint" \
    "$CONFIG_DIR/.eslintrc.js" \
    ~/.eslintrc.js

# Если не удалось скопировать, создаем базовый
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг ESLint...${NC}"
    cat > ~/.eslintrc.js << 'EOF'
module.exports = {
    env: {
        browser: true,
        es2021: true,
        node: true
    },
    extends: 'eslint:recommended',
    parserOptions: {
        ecmaVersion: 12,
        sourceType: 'module'
    },
    rules: {
        'no-unused-vars': 'error',
        'prefer-const': 'error',
        'no-console': 'warn'
    },
    globals: {
        jQuery: 'readonly',
        $: 'readonly'
    }
};
EOF
    echo -e "${GREEN}Базовый конфиг ESLint создан!${NC}"
fi

# Установка Stylelint (CSS)
install_npm_global "stylelint"
install_npm_global "stylelint-config-standard"

# Копируем конфиг Stylelint
copy_config_file "Stylelint" \
    "$CONFIG_DIR/.stylelintrc.json" \
    ~/.stylelintrc.json

# Если не удалось скопировать, создаем базовый
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг Stylelint...${NC}"
    cat > ~/.stylelintrc.json << 'EOF'
{
    "extends": "stylelint-config-standard",
    "rules": {
        "indentation": 4,
        "selector-class-pattern": null,
        "color-hex-case": "lower",
        "number-leading-zero": "always"
    }
}
EOF
    echo -e "${GREEN}Базовый конфиг Stylelint создан!${NC}"
fi

# Установка HTMLHint (HTML)
install_npm_global "htmlhint"

# Копируем конфиг HTMLHint
copy_config_file "HTMLHint" \
    "$CONFIG_DIR/.htmlhintrc" \
    ~/.htmlhintrc

# Если не удалось скопировать, создаем базовый
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг HTMLHint...${NC}"
    cat > ~/.htmlhintrc << 'EOF'
{
    "tagname-lowercase": true,
    "attr-lowercase": true,
    "attr-value-double-quotes": true,
    "doctype-first": true,
    "tag-pair": true,
    "spec-char-escape": true,
    "id-unique": true,
    "src-not-empty": true,
    "attr-no-duplication": true,
    "alt-require": true
}
EOF
    echo -e "${GREEN}Базовый конфиг HTMLHint создан!${NC}"
fi

# Предварительная настройка Composer для автоматического подтверждения
echo -e "${YELLOW}Настраиваем Composer для автоматической установки...${NC}"
composer global config --no-interaction allow-plugins.dealerdirect/phpcodesniffer-composer-installer true
composer global config --no-interaction allow-plugins.squizlabs/php_codesniffer true

# Установка PHP инструментов
echo -e "${YELLOW}Устанавливаем PHP инструменты...${NC}"

# PHP Code Sniffer
install_composer_global "squizlabs/php_codesniffer"
install_composer_global "slevomat/coding-standard"

copy_config_dir "$CONFIG_DIR/phpcs-rules" \
    ~/phpcs-rules

# PHP-CS-Fixer
install_composer_global "friendsofphp/php-cs-fixer"

# PHP-CS-Fixer конфиг
copy_config_file "PHP-CS-Fixer" \
    "$CONFIG_DIR/.php-cs-fixer.dist.php" \
    ~/.php-cs-fixer.dist.php

# PHPMD (PHP Mess Detector)
install_composer_global "phpmd/phpmd"

# Копируем конфиг PHPMD
copy_config_file "PHPMD" \
    "$CONFIG_DIR/.phpmd.xml" \
    ~/.phpmd.xml

# Если не удалось скопировать, создаем базовый
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг PHPMD...${NC}"
    cat > ~/.phpmd.xml << 'EOF'
<?xml version="1.0"?>
<ruleset name="PHPMD rule set"
         xmlns="http://pmd.sf.net/ruleset/1.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://pmd.sf.net/ruleset/1.0.0
                     http://pmd.sf.net/ruleset_xml_schema.xsd"
         xsi:noNamespaceSchemaLocation="
                     http://pmd.sf.net/ruleset_xml_schema.xsd">
    <description>Custom PHPMD rule set</description>

    <rule ref="rulesets/codesize.xml/CyclomaticComplexity" />
    <rule ref="rulesets/codesize.xml/NPathComplexity" />
    <rule ref="rulesets/codesize.xml/ExcessiveMethodLength" />
    <rule ref="rulesets/codesize.xml/ExcessiveClassLength" />
    <rule ref="rulesets/codesize.xml/ExcessiveParameterList" />
    <rule ref="rulesets/codesize.xml/ExcessivePublicCount" />
    <rule ref="rulesets/codesize.xml/TooManyFields" />
    <rule ref="rulesets/codesize.xml/TooManyMethods" />
    <rule ref="rulesets/codesize.xml/ExcessiveClassComplexity" />

    <rule ref="rulesets/design.xml" />

    <rule ref="rulesets/naming.xml" />

    <rule ref="rulesets/unusedcode.xml" />

    <rule ref="rulesets/controversial.xml" />
</ruleset>
EOF
    echo -e "${GREEN}Базовый конфиг PHPMD создан!${NC}"
fi

# Psalm
install_composer_global "vimeo/psalm"

# Psalm конфиг
copy_config_file "Psalm" \
    "$CONFIG_DIR/psalm.xml" \
    ~/psalm.xml

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

# Копируем конфиг PHPStan
copy_config_file "PHPStan" \
    "$CONFIG_DIR/.phpstan.neon" \
    ~/.phpstan.neon

# Если не удалось скопировать, создаем базовый
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг PHPStan...${NC}"
    cat > ~/.phpstan.neon << 'EOF'
parameters:
    level: 5
    paths:
        - .
    checkMissingIterableValueType: false
    checkGenericClassInNonGenericObjectType: false
EOF
    echo -e "${GREEN}Базовый конфиг PHPStan создан!${NC}"
fi

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

# Показываем установленные конфиги
echo ""
echo -e "${YELLOW}Установленные конфиги:${NC}"
configs=(
    ".eslintrc.js"
    ".stylelintrc.json"
    ".htmlhintrc"
    ".phpmd.xml"
    ".phpstan.neon"
    ".php-cs-fixer.dist.php"
    "psalm.xml"
)

for config in "${configs[@]}"; do
    if [ -f "$HOME/$config" ]; then
        echo -e "${GREEN}✓ ~/$config${NC}"
    else
        echo -e "${RED}✗ ~/$config (отсутствует)${NC}"
    fi
done

# Показываем исходные конфиги
echo ""
echo -e "${YELLOW}Исходные конфиги в папке config:${NC}"
for config in "${configs[@]}"; do
    if [ -f "$CONFIG_DIR/$config" ]; then
        echo -e "${GREEN}✓ $CONFIG_DIR/$config${NC}"
    else
        echo -e "${YELLOW}⚠ $CONFIG_DIR/$config (отсутствует)${NC}"
    fi
done

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