#!/bin/bash

# Скрипт для обновления настроек Cursor с заменой [HOME] на актуальный путь

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Определяем домашнюю директорию
USER_HOME="$HOME"
echo -e "${YELLOW}Домашняя директория: $USER_HOME${NC}"

# Пути к файлам
SOURCE_FILE="Cursor/.config/Cursor/User/settings.json"
TARGET_DIR="$HOME/Cursor/.config/Cursor/User"
TARGET_FILE="$TARGET_DIR/settings.json"
BACKUP_FILE="$TARGET_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Проверяем существование исходного файла
if [ ! -f "$SOURCE_FILE" ]; then
    echo -e "${RED}Исходный файл не найден: $SOURCE_FILE${NC}"
    echo "Убедитесь, что вы запускаете скрипт из правильной директории"
    exit 1
fi

# Создаем целевую директорию если не существует
mkdir -p "$TARGET_DIR"
if [ $? -ne 0 ]; then
    echo -e "${RED}Не удалось создать директорию: $TARGET_DIR${NC}"
    exit 1
fi

# Создаем бэкап существующего файла если он есть
if [ -f "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}Создан бэкап: $BACKUP_FILE${NC}"
fi

# Заменяем [HOME] на актуальный путь и копируем файл
echo -e "${YELLOW}Обновляем настройки Cursor...${NC}"
sed "s|\[HOME\]|$USER_HOME|g" "$SOURCE_FILE" > "$TARGET_FILE"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Настройки Cursor успешно обновлены!${NC}"
    echo -e "${GREEN}Файл: $TARGET_FILE${NC}"
else
    echo -e "${RED}❌ Ошибка при обновлении настроек${NC}"
    exit 1
fi

# Проверяем результат
echo ""
echo -e "${YELLOW}Проверка замены:${NC}"
echo "В файле найдены пути:"
grep -o "\"$USER_HOME/[^\"]*\"" "$TARGET_FILE" | head -5

echo ""
echo -e "${GREEN}Готово! Перезапустите Cursor для применения настроек.${NC}"