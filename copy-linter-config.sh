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

# Проверяем наличие папки config
if [ ! -d "$CONFIG_DIR" ]; then
    echo -e "${RED}Папка config не найдена! Создайте папку config с конфигами.${NC}"
    exit 1
fi

echo -e "${GREEN}Папка config найдена: $CONFIG_DIR${NC}"

# Получаем путь к глобальным Composer пакетам
COMPOSER_HOME=${COMPOSER_HOME:-$HOME/.config/composer}
COMPOSER_BIN="$COMPOSER_HOME/vendor/bin"

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

# Установка PHP инструментов
echo -e "${YELLOW}Устанавливаем PHP инструменты...${NC}"

copy_config_dir "$CONFIG_DIR/phpcs-rules" \
    ~/

# PHP-CS-Fixer конфиг
copy_config_file "PHP-CS-Fixer" \
    "$CONFIG_DIR/.php-cs-fixer.dist.php" \
    ~/.php-cs-fixer.dist.php

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

# Psalm конфиг
copy_config_file "Psalm" \
    "$CONFIG_DIR/psalm.xml" \
    ~/psalm.xml

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

echo -e "${GREEN}Установка завершена!${NC}"
echo ""

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
