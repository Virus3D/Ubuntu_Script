#!/bin/bash
# linter-manager.sh - Управление линтерами для Cursor

case "$1" in
    "start")
        echo "🚀 Запуск линтеров для Cursor..."
        
        # Создаем легковесные конфиги для Cursor
        cat > ~/.cursor-eslintrc.js << 'EOF'
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
        'no-unused-vars': ['error', { 'args': 'none' }],
        'prefer-const': 'error',
        'no-console': 'off'  // Отключаем для разработки
    }
};
EOF

        cat > ~/.cursor-stylelintrc.json << 'EOF'
{
    "extends": "stylelint-config-standard",
    "rules": {
        "indentation": 4,
        "selector-class-pattern": null,
        "color-hex-case": null,
        "number-leading-zero": null
    }
}
EOF
        
        echo "✅ Легковесные конфиги созданы"
        ;;
        
    "stop")
        echo "🛑 Очистка временных конфигов..."
        rm -f ~/.cursor-eslintrc.js ~/.cursor-stylelintrc.json
        echo "✅ Временные конфиги удалены"
        ;;
        
    "status")
        echo "📊 Статус линтеров:"
        command -v eslint >/dev/null && echo "✅ ESLint установлен" || echo "❌ ESLint не установлен"
        command -v phpcs >/dev/null && echo "✅ PHPCS установлен" || echo "❌ PHPCS не установлен"
        command -v stylelint >/dev/null && echo "✅ Stylelint установлен" || echo "❌ Stylelint не установлен"
        ;;
        
    *)
        echo "Использование: $0 {start|stop|status}"
        echo "  start  - подготовить легковесные конфиги для Cursor"
        echo "  stop   - очистить временные конфиги"
        echo "  status - показать статус линтеров"
        ;;
esac