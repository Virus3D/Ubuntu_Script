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
HOME_CONFIG_DIR="$HOME/config"

# Создаем директорию для конфигов, если она не существует
if [ ! -d "$HOME_CONFIG_DIR" ]; then
    echo -e "${YELLOW}Создаем директорию для конфигов: $HOME_CONFIG_DIR${NC}"
    mkdir -p "$HOME_CONFIG_DIR"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Директория создана успешно!${NC}"
    else
        echo -e "${RED}Не удалось создать директорию: $HOME_CONFIG_DIR${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Директория для конфигов уже существует: $HOME_CONFIG_DIR${NC}"
fi

# Проверяем наличие папки config с исходными конфигами
if [ ! -d "$CONFIG_DIR" ]; then
    echo -e "${RED}Папка config не найдена! Создайте папку config с конфигами.${NC}"
    exit 1
fi

echo -e "${GREEN}Папка для исходных конфигов: $CONFIG_DIR${NC}"
echo -e "${GREEN}Папка для установленных конфигов: $HOME_CONFIG_DIR${NC}"

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
        echo -e "${YELLOW}Конфиг '$config_name' не найден: '$source_file'${NC}"
        echo -e "${YELLOW}Создаем базовый конфиг '$config_name'...${NC}"
        return 2
    fi
}

copy_config_dir() {
    local source_dir="$1"
    local destination="$2"

    echo -e "${YELLOW}Копируем из директории '$source_dir' в '$destination'...${NC}"

    # Проверяем, что источник существует и является директорией
    if [ ! -d "$source_dir" ]; then
        echo -e "${YELLOW}Директория не найдена: '$source_dir'${NC}"
        return 1
    fi

    # Создаем целевую директорию, если её нет
    mkdir -p "$destination"

    # Копирование с сохранением всех атрибутов (права, время, симлинки)
    cp -a "$source_dir/." "$destination" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Директория '$source_dir' успешно скопирована в '$destination'!${NC}"
        return 0
    else
        echo -e "${RED}Ошибка при копировании директории '$source_dir'${NC}"
        return 1
    fi
}

# Копируем конфиг ESLint
copy_config_file "ESLint" \
    "$CONFIG_DIR/.eslintrc.js" \
    "$HOME_CONFIG_DIR/.eslintrc.js"

# Если не удалось скопировать (файл не найден в source), создаем базовый в destination
if [ $? -eq 2 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг ESLint в $HOME_CONFIG_DIR...${NC}"
    cat > "$HOME_CONFIG_DIR/.eslintrc.js" << 'EOF'
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
    "$HOME_CONFIG_DIR/.stylelintrc.json"

# Если не удалось скопировать, создаем базовый
if [ $? -eq 2 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг Stylelint в $HOME_CONFIG_DIR...${NC}"
    cat > "$HOME_CONFIG_DIR/.stylelintrc.json" << 'EOF'
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
    "$HOME_CONFIG_DIR/.htmlhintrc"

# Если не удалось скопировать, создаем базовый
if [ $? -eq 2 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг HTMLHint в $HOME_CONFIG_DIR...${NC}"
    cat > "$HOME_CONFIG_DIR/.htmlhintrc" << 'EOF'
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

# Копируем директорию phpcs-rules в домашнюю директорию
echo -e "${YELLOW}Копируем phpcs-rules в домашнюю директорию...${NC}"
copy_config_dir "$CONFIG_DIR/phpcs-rules" \
    "$HOME/phpcs-rules"

# PHP-CS-Fixer конфиг
copy_config_file "PHP-CS-Fixer" \
    "$CONFIG_DIR/.php-cs-fixer.dist.php" \
    "$HOME_CONFIG_DIR/.php-cs-fixer.dist.php"

# Если не удалось скопировать, создаем базовый
if [ $? -eq 2 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг PHP-CS-Fixer в $HOME_CONFIG_DIR...${NC}"
    cat > "$HOME_CONFIG_DIR/.php-cs-fixer.dist.php" << 'EOF'
<?php

$finder = PhpCsFixer\Finder::create()
    ->in(__DIR__)
    ->exclude('vendor')
    ->exclude('node_modules')
    ->exclude('storage')
    ->exclude('bootstrap/cache')
    ->name('*.php')
    ->notName('*.blade.php')
    ->ignoreDotFiles(true)
    ->ignoreVCS(true);

$config = new PhpCsFixer\Config();
return $config->setRules([
        '@PSR12' => true,
        'array_syntax' => ['syntax' => 'short'],
        'ordered_imports' => ['sort_algorithm' => 'alpha'],
        'no_unused_imports' => true,
        'not_operator_with_successor_space' => true,
        'trailing_comma_in_multiline' => true,
        'phpdoc_scalar' => true,
        'unary_operator_spaces' => true,
        'binary_operator_spaces' => true,
        'blank_line_before_statement' => [
            'statements' => ['break', 'continue', 'declare', 'return', 'throw', 'try'],
        ],
        'phpdoc_single_line_var_spacing' => true,
        'phpdoc_var_without_name' => true,
        'class_attributes_separation' => [
            'elements' => [
                'method' => 'one',
            ],
        ],
        'method_argument_space' => [
            'on_multiline' => 'ensure_fully_multiline',
            'keep_multiple_spaces_after_comma' => true,
        ],
        'single_trait_insert_per_statement' => true,
    ])
    ->setFinder($finder);
EOF
    echo -e "${GREEN}Базовый конфиг PHP-CS-Fixer создан!${NC}"
fi

# Копируем конфиг PHPMD
copy_config_file "PHPMD" \
    "$CONFIG_DIR/.phpmd.xml" \
    "$HOME_CONFIG_DIR/.phpmd.xml"

# Если не удалось скопировать, создаем базовый
if [ $? -eq 2 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг PHPMD в $HOME_CONFIG_DIR...${NC}"
    cat > "$HOME_CONFIG_DIR/.phpmd.xml" << 'EOF'
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
    "$HOME_CONFIG_DIR/psalm.xml"

# Если не удалось скопировать, создаем базовый
if [ $? -eq 2 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг Psalm в $HOME_CONFIG_DIR...${NC}"
    cat > "$HOME_CONFIG_DIR/psalm.xml" << 'EOF'
<?xml version="1.0"?>
<psalm
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns="https://getpsalm.org/schema/config"
    xsi:schemaLocation="https://getpsalm.org/schema/config vendor/vimeo/psalm/config.xsd"
    errorLevel="5"
    resolveFromConfigFile="true"
    findUnusedCode="false"
    findUnusedBaselineEntry="false"
>
    <projectFiles>
        <directory name="." />
        <ignoreFiles>
            <directory name="vendor" />
            <directory name="node_modules" />
            <directory name="storage" />
            <directory name="bootstrap/cache" />
        </ignoreFiles>
    </projectFiles>
</psalm>
EOF
    echo -e "${GREEN}Базовый конфиг Psalm создан!${NC}"
fi

# Копируем конфиг PHPStan
copy_config_file "PHPStan" \
    "$CONFIG_DIR/.phpstan.neon" \
    "$HOME_CONFIG_DIR/.phpstan.neon"

# Если не удалось скопировать, создаем базовый
if [ $? -eq 2 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг PHPStan в $HOME_CONFIG_DIR...${NC}"
    cat > "$HOME_CONFIG_DIR/.phpstan.neon" << 'EOF'
parameters:
    level: 5
    paths:
        - .
    checkMissingIterableValueType: false
    checkGenericClassInNonGenericObjectType: false
EOF
    echo -e "${GREEN}Базовый конфиг PHPStan создан!${NC}"
fi

# Копируем конфиг TwigCS
copy_config_file "TwigCS" \
    "$CONFIG_DIR/.twigcs.json" \
    "$HOME_CONFIG_DIR/.twigcs.json"

# Если не удалось скопировать, создаем базовый
if [ $? -eq 2 ]; then
    echo -e "${YELLOW}Создаем базовый конфиг TwigCS в $HOME_CONFIG_DIR...${NC}"
    cat > "$HOME_CONFIG_DIR/.twigcs.json" << 'EOF'
{
    "severity": "warning",
    "ruleset": "FriendsOfTwig\\Twigcs\\RuleSet\\Official",
    "reporter": "console"
}
EOF
    echo -e "${GREEN}Базовый конфиг TwigCS создан!${NC}"
fi

echo -e "${GREEN}Установка завершена!${NC}"
echo ""

# Показываем установленные конфиги
echo ""
echo -e "${YELLOW}Установленные конфиги в $HOME_CONFIG_DIR:${NC}"
configs=(
    ".eslintrc.js"
    ".stylelintrc.json"
    ".htmlhintrc"
    ".phpmd.xml"
    ".phpstan.neon"
    ".php-cs-fixer.dist.php"
    "psalm.xml"
    ".twigcs.json"
)

all_success=true
for config in "${configs[@]}"; do
    if [ -f "$HOME_CONFIG_DIR/$config" ]; then
        echo -e "${GREEN}✓ $HOME_CONFIG_DIR/$config${NC}"
    else
        echo -e "${RED}✗ $HOME_CONFIG_DIR/$config (отсутствует)${NC}"
        all_success=false
    fi
done

# Проверяем директорию phpcs-rules в домашней директории
if [ -d "$HOME/phpcs-rules" ]; then
    echo -e "${GREEN}✓ $HOME/phpcs-rules (директория)${NC}"
else
    echo -e "${YELLOW}⚠ $HOME/phpcs-rules (директория отсутствует)${NC}"
fi

# Показываем исходные конфиги
echo ""
echo -e "${YELLOW}Исходные конфиги в папке $CONFIG_DIR:${NC}"
for config in "${configs[@]}"; do
    if [ -f "$CONFIG_DIR/$config" ]; then
        echo -e "${GREEN}✓ $CONFIG_DIR/$config${NC}"
    else
        echo -e "${YELLOW}⚠ $CONFIG_DIR/$config (отсутствует)${NC}"
    fi
done

echo ""
if [ "$all_success" = true ]; then
    echo -e "${GREEN}✅ Все конфиги успешно установлены!${NC}"
    echo -e "${BLUE}Конфиги находятся в: $HOME_CONFIG_DIR${NC}"
    echo -e "${BLUE}Директория phpcs-rules: $HOME/phpcs-rules${NC}"
else
    echo -e "${YELLOW}⚠ Некоторые конфиги не были установлены${NC}"
fi