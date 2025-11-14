#!/bin/bash
# optimize-cursor.sh - Оптимизация Cursor для работы с линтерами

echo "⚡ Оптимизация Cursor для линтеров..."

# Создаем директорию для кэша линтеров
mkdir -p ~/.cursor/cache

# Настройка лимитов для линтеров
cat > ~/.cursor-limits.json << 'EOF'
{
  "eslint": {
    "maxWarnings": 50,
    "timeout": 5000
  },
  "phpcs": {
    "maxWarnings": 100,
    "timeout": 7000
  },
  "stylelint": {
    "maxWarnings": 30,
    "timeout": 4000
  }
}
EOF

# Создаем ignore-файлы для линтеров
cat > ~/.cursor-eslintignore << 'EOF'
node_modules/
vendor/
dist/
build/
*.min.js
coverage/
.cache/
EOF

cat > ~/.cursor-phpcsignore << 'EOF'
vendor/
node_modules/
storage/
cache/
logs/
tmp/
EOF

echo "✅ Оптимизация завершена!"