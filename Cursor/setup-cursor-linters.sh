#!/bin/bash
# setup-cursor-linters.sh

echo "🎯 Настройка линтеров для Cursor..."

# Создаем директорию для настроек Cursor
mkdir -p ~/.cursor
mkdir -p ~/.cursor/userdata/User

# Основные настройки Cursor
cat > ~/.cursor/userdata/User/settings.json << 'EOF'
{
  "eslint.enable": true,
  "eslint.run": "onType",
  "eslint.options": {
    "configFile": "~/.eslintrc.js"
  },
  "stylelint.enable": true,
  "stylelint.configFile": "~/.stylelintrc.json",
  "phpcs.enable": true,
  "phpcs.standard": "PSR12",
  "phpstan.enable": true,
  "psalm.enable": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit",
    "source.fixAll.stylelint": "explicit"
  },
  "files.watcherExclude": {
    "**/node_modules/**": true,
    "**/vendor/**": true
  }
}
EOF

# Создаем workspace настройки
cat > ~/.cursor/workspace.settings.json << 'EOF'
{
  "folders": [
    {
      "path": "."
    }
  ],
  "settings": {
    "phpcs.standard": "PSR12",
    "eslint.workingDirectories": ["."]
  }
}
EOF

echo "✅ Настройки Cursor созданы!"