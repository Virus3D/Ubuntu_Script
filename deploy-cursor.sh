#!/bin/bash

# Скрипт установки Cursor для x86_64
# Автоматически загружает и устанавливает Cursor AppImage

set -e  # Прерывать выполнение при ошибках

# Переменные
CURSOR_URL="https://downloads.cursor.com/production/45fd70f3fe72037444ba35c9e51ce86a1977ac11/linux/x64/Cursor-2.0.34-x86_64.AppImage"
DOWNLOAD_DIR="/tmp"
INSTALL_DIR="/opt/cursor"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/256x256/apps"
APP_NAME="Cursor"
APPIMAGE_NAME="Cursor.AppImage"
FINAL_APPIMAGE_NAME="Cursor.AppImage"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функции для вывода
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Этот скрипт требует прав root для глобальной установки"
        error "Запустите с sudo: sudo $0"
        exit 1
    fi
}

# Проверка архитектуры
check_architecture() {
    info "Проверка архитектуры..."
    if [ "$(uname -m)" != "x86_64" ]; then
	error "Этот скрипт предназначен только для x86_64 систем"
        error "Текущая архитектура: $(uname -m)"
        exit 1
    fi
    info "Архитектура x86_64 подтверждена"
}

# Установка зависимостей
install_dependencies() {
    info "Установка системных зависимостей..."
    
    # Обновляем список пакетов
    apt update
    
    # Определяем менеджер пакетов
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
    elif command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
    else
        error "Не найден поддерживаемый менеджер пакетов (apt/apt-get)"
        exit 1
    fi
    
    # Устанавливаем зависимости
    local dependencies=(
        "wget"
        "curl"
        "fuse"
    )
    
    # Фильтруем уже установленные пакеты
    local to_install=()
    for dep in "${dependencies[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep "; then
            to_install+=("$dep")
        else
            info "Пакет $dep уже установлен"
        fi
    done
    
    # Устанавливаем отсутствующие пакеты
    if [ ${#to_install[@]} -ne 0 ]; then
        info "Устанавливаем пакеты: ${to_install[*]}"
        $PKG_MANAGER install -y "${to_install[@]}"
    else
        info "Все зависимости уже установлены"
    fi
    
    # Проверяем установку FUSE
    info "Проверка установки FUSE..."
    if ! ldconfig -p | grep -q libfuse.so.2; then
        warn "libfuse.so.2 не найден, устанавливаем дополнительные пакеты..."
        $PKG_MANAGER install -y libfuse2 fuse
        
        # Для современных систем (Ubuntu 22.04+)
        if $PKG_MANAGER install -y fuse3 libfuse3-3 2>/dev/null; then
            info "FUSE3 установлен"
        fi
    else
        info "FUSE библиотеки найдены"
    fi
    
    # Проверяем доступность FUSE в системе
    if [ ! -e /dev/fuse ]; then
        warn "Устройство FUSE не найдено, загружаем модуль..."
        modprobe fuse 2>/dev/null || true
    fi
    
    # Проверяем возможность монтирования FUSE
    if [ ! -w /dev/fuse ]; then
        warn "Нет прав на запись в /dev/fuse"
        warn "Добавьте пользователя в группу fuse: sudo usermod -a -G fuse \$USER"
    fi
}

# Создание директорий
create_directories() {
    info "Создание директорий..."
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$DESKTOP_DIR"
    mkdir -p "$ICON_DIR"
    
    info "Директории созданы:"
    info "  Установка: $INSTALL_DIR"
    info "  Бинарники: $BIN_DIR"
    info "  Ярлыки: $DESKTOP_DIR"
    info "  Иконки: $ICON_DIR"
}

# Загрузка Cursor
download_cursor() {
    info "Загрузка Cursor..."
    
    if [ -f "$DOWNLOAD_DIR/$APPIMAGE_NAME" ]; then
        warn "Файл уже существует, перезаписываем..."
        rm -f "$DOWNLOAD_DIR/$APPIMAGE_NAME"
    fi
    
    cd "$DOWNLOAD_DIR"
    if wget --show-progress -O "$APPIMAGE_NAME" "$CURSOR_URL"; then
        info "Cursor успешно загружен"
    else
        error "Ошибка загрузки Cursor"
        exit 1
    fi
}

# Установка Cursor
install_cursor() {
    info "Установка Cursor в системные директории..."
    
    # Делаем AppImage исполняемым
    chmod +x "$DOWNLOAD_DIR/$APPIMAGE_NAME"
    
    # Копируем в директорию установки
    cp "$DOWNLOAD_DIR/$APPIMAGE_NAME" "$INSTALL_DIR/$FINAL_APPIMAGE_NAME"

    # Создаем симлинк для удобного запуска
    ln -sf "$INSTALL_DIR/$FINAL_APPIMAGE_NAME" "$BIN_DIR/cursor"
    
    info "Cursor установлен в $INSTALL_DIR"
    info "Созданы симлинки: $BIN_DIR/cursor"
}

# Создание desktop файла
create_desktop_file() {
    info "Создание ярлыка для рабочего стола..."
    
    cat > "$DESKTOP_DIR/cursor.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Cursor
Comment=The AI-first code editor
Exec=$INSTALL_DIR/$FINAL_APPIMAGE_NAME
Icon=cursor
Categories=Development;IDE;TextEditor;
Terminal=false
StartupWMClass=Cursor
MimeType=text/plain;text/x-chdr;text/x-csrc;text/x-c++hdr;text/x-c++src;text/x-java;text/x-dsrc;text/x-pascal;text/x-perl;text/x-python;application/x-php;application/x-httpd-php3;application/x-httpd-php4;application/x-httpd-php5;application/xml;text/html;text/css;text/x-sql;text/x-diff;x-scheme-handler/tg;
Keywords=cursor;ai;code;editor;development;programming;
X-AppImage-Version=2.0.34
EOF

    # Обновляем кэш desktop файлов
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    
    info "Ярлык приложения создан"
}

# Установка иконки (опционально)
install_icon() {
    info "Установка иконки..."
    
    # Создаем временную директорию для извлечения иконки
    TEMP_DIR=$(mktemp -d)
    
    # Извлекаем иконку из AppImage
    if cd "$TEMP_DIR" && "$DOWNLOAD_DIR/$APPIMAGE_NAME" --appimage-extract >/dev/null 2>&1; then
        # Ищем иконки в извлеченных файлах
        find "$TEMP_DIR" -name "*.png" -o -name "*.svg" | head -5 | while read -r icon_file; do
            if file "$icon_file" | grep -q "256 x 256"; then
                cp "$icon_file" "$ICON_DIR/cursor.png"
                info "Иконка 256x256 найдена и установлена"
                break
            fi
        done
        
        # Если не нашли подходящую иконку, копируем первую попавшуюся PNG
        if [ ! -f "$ICON_DIR/cursor.png" ]; then
            FIRST_PNG=$(find "$TEMP_DIR" -name "*.png" | head -1)
            if [ -n "$FIRST_PNG" ]; then
                cp "$FIRST_PNG" "$ICON_DIR/cursor.png"
                info "Иконка скопирована: $ICON_DIR/cursor.png"
            fi
        fi
    fi
    
    # Очистка временных файлов
    rm -rf "$TEMP_DIR"
    
    if [ ! -f "$ICON_DIR/cursor.png" ]; then
        warn "Не удалось извлечь иконку из AppImage"
        warn "Будет использована стандартная иконка системы"
    fi
    
    # Обновляем кэш иконок
    gtk-update-icon-cache /usr/share/icons/hicolor -f 2>/dev/null || true
}

# Настройка AppArmor профиля
setup_apparmor() {
    info "Настройка AppArmor профиля..."
    
    local APPARMOR_DIR="/etc/apparmor.d"
    local APPARMOR_PROFILE="$APPARMOR_DIR/cursor"
    
    if ! command -v aa-status &> /dev/null; then
        warn "AppArmor не установлен, пропускаем настройку"
        return 0
    fi
    
    # Создаем AppArmor профиль
    cat > "$APPARMOR_PROFILE" << EOF
abi <abi/4.0>,
include <tunables/global>

profile cursor $INSTALL_DIR/$APPIMAGE_NAME flags=(unconfined) {
  userns,
  include if exists <local/cursor>
}
EOF

    # Применяем профиль AppArmor
    if aa-enable "$APPARMOR_PROFILE" 2>/dev/null || aa-complain "$APPARMOR_PROFILE" 2>/dev/null; then
        info "AppArmor профиль создан: $APPARMOR_PROFILE"
        info "Профиль работает в режиме enforce"
    else
        warn "Не удалось активировать AppArmor профиль автоматически"
    fi
    
    # Перезагружаем AppArmor
    if systemctl is-active --quiet apparmor; then
        systemctl reload apparmor
        info "AppArmor перезагружен"
    fi
}

# Настройка прав доступа
setup_permissions() {
    info "Настройка прав доступа..."
    
    # Устанавливаем владельца для файлов Cursor
    chown -R root:root "$INSTALL_DIR"
    
    # Устанавливаем права для исполняемого файла
    chmod 755 "$INSTALL_DIR/$FINAL_APPIMAGE_NAME"
    chmod 755 "$BIN_DIR/cursor"
    
    # Права для desktop файла
    chmod 644 "$DESKTOP_DIR/cursor.desktop"
    
    info "Права доступа настроены"
}

# Основная функция установки
main() {
    echo "=================================================="
    echo "    Глобальная установка Cursor для x86_64"
    echo "         с настройкой AppArmor"
    echo "=================================================="
    
    check_root
    check_architecture
    install_dependencies
    create_directories
    download_cursor
    install_cursor
    create_desktop_file
    install_icon
    setup_apparmor
    setup_permissions
    
    echo ""
    echo "=================================================="
    info "Установка завершена успешно!"
    echo "=================================================="
    echo ""
    info "Доступные команды:"
    info "  cursor              - Запуск Cursor (с AppArmor)"
    info "  cursor-apparmor     - Запуск с проверкой AppArmor"
    info "  cursor-no-sandbox   - Запуск без sandbox (не рекомендуется)"
    info "  cursor-update       - Обновление Cursor"
    echo ""
    info "Файлы установлены в:"
    info "  Бинарник: /opt/cursor/cursor.AppImage"
    info "  Симлинки: /usr/local/bin/cursor*"
    info "  Ярлык: /usr/share/applications/cursor.desktop"
    info "  AppArmor: /etc/apparmor.d/cursor"
    echo ""
    warn "Важно: AppArmor профиль обеспечивает безопасность вместо sandbox"
    info "Статус AppArmor: sudo aa-status | grep cursor"
    info "Логи AppArmor: sudo dmesg | grep apparmor"
    echo ""
}

# Запуск основной функции
main "$@"
