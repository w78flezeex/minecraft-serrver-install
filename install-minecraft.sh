#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    error "Пожалуйста, запустите скрипт от имени root (sudo ./install-minecraft.sh)"
    exit 1
fi

info "=== Установщик Minecraft сервера ==="
echo ""

# Выбор директории для установки
read -p "Введите путь для установки сервера (по умолчанию: /opt/minecraft): " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-/opt/minecraft}

# Создание директории
if [ ! -d "$INSTALL_DIR" ]; then
    info "Создание директории $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
fi

cd "$INSTALL_DIR" || exit 1

# Проверка и установка Java
info "Проверка Java..."
if ! command -v java &> /dev/null; then
    warning "Java не найдена. Устанавливаю Java 17 (OpenJDK)..."
    
    # Определение системы
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y openjdk-17-jdk wget curl
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL/Fedora
        if command -v dnf &> /dev/null; then
            dnf install -y java-17-openjdk-devel wget curl
        else
            yum install -y java-17-openjdk-devel wget curl
        fi
    else
        error "Неподдерживаемая система. Установите Java вручную."
        exit 1
    fi
else
    JAVA_VERSION=$(java -version 2>&1 | head -n 1)
    info "Java уже установлена: $JAVA_VERSION"
fi

# Проверка и установка screen
info "Проверка screen..."
if ! command -v screen &> /dev/null; then
    warning "Screen не найден. Устанавливаю screen..."
    if [ -f /etc/debian_version ]; then
        apt-get install -y screen
    elif [ -f /etc/redhat-release ]; then
        if command -v dnf &> /dev/null; then
            dnf install -y screen
        else
            yum install -y screen
        fi
    fi
else
    info "Screen уже установлен"
fi

# Проверка версии Java
JAVA_VERSION_CHECK=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F '.' '{print $1}')
if [ "$JAVA_VERSION_CHECK" -lt 17 ]; then
    warning "Рекомендуется Java 17 или выше. Текущая версия: $JAVA_VERSION_CHECK"
    read -p "Продолжить? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        exit 1
    fi
fi

# Выбор версии Minecraft
echo ""
info "Выберите версию Minecraft:"
echo "1) 1.20.4 (рекомендуется)"
echo "2) 1.20.1"
echo "3) 1.19.4"
echo "4) 1.18.2"
echo "5) 1.17.1"
echo "6) 1.16.5"
echo "7) Другая версия (указать вручную)"
read -p "Ваш выбор (1-7): " VERSION_CHOICE

case $VERSION_CHOICE in
    1) MINECRAFT_VERSION="1.20.4" ;;
    2) MINECRAFT_VERSION="1.20.1" ;;
    3) MINECRAFT_VERSION="1.19.4" ;;
    4) MINECRAFT_VERSION="1.18.2" ;;
    5) MINECRAFT_VERSION="1.17.1" ;;
    6) MINECRAFT_VERSION="1.16.5" ;;
    7)
        read -p "Введите версию (например, 1.20.3): " MINECRAFT_VERSION
        ;;
    *)
        warning "Неверный выбор, используется версия по умолчанию: 1.20.4"
        MINECRAFT_VERSION="1.20.4"
        ;;
esac

# Выбор ядра/типа сервера
echo ""
info "Выберите ядро сервера:"
echo "1) Vanilla (официальный)"
echo "2) Paper (рекомендуется, оптимизированное)"
echo "3) Spigot (оптимизированное с плагинами)"
echo "4) Fabric (моды)"
echo "5) Forge (моды)"
read -p "Ваш выбор (1-5): " CORE_CHOICE

case $CORE_CHOICE in
    1) SERVER_TYPE="vanilla" ;;
    2) SERVER_TYPE="paper" ;;
    3) SERVER_TYPE="spigot" ;;
    4) SERVER_TYPE="fabric" ;;
    5) SERVER_TYPE="forge" ;;
    *)
        warning "Неверный выбор, используется Paper"
        SERVER_TYPE="paper"
        ;;
esac

info "Выбрано: Minecraft $MINECRAFT_VERSION, Ядро: $SERVER_TYPE"

# Функция скачивания сервера
download_server() {
    case $SERVER_TYPE in
        vanilla)
            info "Скачивание Vanilla сервера..."
            # Получение URL для Vanilla сервера через Mojang API
            VERSION_MANIFEST="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
            VERSION_DATA=$(curl -s "$VERSION_MANIFEST" | grep -o "\"id\":\"$MINECRAFT_VERSION\"[^}]*")
            
            if [ -z "$VERSION_DATA" ]; then
                warning "Версия $MINECRAFT_VERSION не найдена в manifest. Используется последняя версия."
                # Получаем последнюю версию
                LATEST_VERSION=$(curl -s "$VERSION_MANIFEST" | grep -o '"latest":{"release":"[^"]*"' | grep -o '"[^"]*"' | head -1 | tr -d '"')
                VERSION_URL=$(curl -s "$VERSION_MANIFEST" | grep -o "\"id\":\"$LATEST_VERSION\"[^}]*\"url\":\"[^\"]*" | grep -o '"url":"[^"]*' | cut -d'"' -f4)
            else
                # Получаем URL для конкретной версии
                VERSION_URL=$(curl -s "$VERSION_MANIFEST" | grep -A 5 "\"id\":\"$MINECRAFT_VERSION\"" | grep -o '"url":"[^"]*' | cut -d'"' -f4)
            fi
            
            if [ -n "$VERSION_URL" ]; then
                SERVER_INFO=$(curl -s "$VERSION_URL" | grep -o '"server":{[^}]*"url":"[^"]*')
                SERVER_URL=$(echo "$SERVER_INFO" | grep -o '"url":"[^"]*' | cut -d'"' -f4)
                
                if [ -z "$SERVER_URL" ]; then
                    error "Не удалось получить URL сервера для версии $MINECRAFT_VERSION"
                    read -p "Введите URL для Vanilla сервера вручную: " SERVER_URL
                fi
            else
                error "Не удалось получить информацию о версии $MINECRAFT_VERSION"
                read -p "Введите URL для Vanilla сервера вручную: " SERVER_URL
            fi
            
            wget -O server.jar "$SERVER_URL" || {
                error "Не удалось скачать Vanilla сервер. Проверьте версию и интернет-соединение."
                exit 1
            }
            ;;
        paper)
            info "Скачивание Paper сервера..."
            # Получение последней сборки Paper для выбранной версии
            BUILD_API="https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION"
            BUILD_INFO=$(curl -s "$BUILD_API")
            
            if [ -z "$BUILD_INFO" ] || echo "$BUILD_INFO" | grep -q "error"; then
                error "Не удалось получить информацию о сборках Paper. Версия может быть не поддерживается."
                read -p "Введите номер сборки вручную (или нажмите Enter для пропуска): " LATEST_BUILD
                if [ -z "$LATEST_BUILD" ]; then
                    error "Отмена установки."
                    exit 1
                fi
            else
                # Получаем последнюю сборку из JSON ответа
                LATEST_BUILD=$(echo "$BUILD_INFO" | grep -o '"builds":\[[0-9,]*\]' | grep -o '[0-9]*' | tail -1)
            fi
            
            if [ -z "$LATEST_BUILD" ]; then
                error "Не удалось определить номер сборки."
                read -p "Введите номер сборки вручную: " LATEST_BUILD
                if [ -z "$LATEST_BUILD" ]; then
                    error "Отмена установки."
                    exit 1
                fi
            fi
            
            SERVER_URL="https://api.papermc.io/v2/projects/paper/versions/$MINECRAFT_VERSION/builds/$LATEST_BUILD/downloads/paper-$MINECRAFT_VERSION-$LATEST_BUILD.jar"
            info "Используется сборка Paper: $LATEST_BUILD"
            wget -O server.jar "$SERVER_URL" || {
                error "Не удалось скачать Paper сервер. Проверьте версию и интернет-соединение."
                exit 1
            }
            ;;
        spigot)
            info "Скачивание Spigot сервера..."
            warning "Spigot требует BuildTools. Используется Spigot BuildTools..."
            # Используем Paper вместо Spigot, так как BuildTools требует много времени
            warning "Spigot BuildTools может занять много времени. Рекомендуется использовать Paper вместо Spigot."
            read -p "Использовать Paper вместо Spigot? (y/n): " USE_PAPER
            if [ "$USE_PAPER" = "y" ] || [ "$USE_PAPER" = "Y" ]; then
                SERVER_TYPE="paper"
                download_server
                return
            fi
            
            # Скачивание BuildTools для Spigot
            wget -O BuildTools.jar https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar
            java -jar BuildTools.jar --rev "$MINECRAFT_VERSION" --compile craftbukkit spigot
            mv spigot-*.jar server.jar 2>/dev/null || {
                error "Не удалось собрать Spigot."
                exit 1
            }
            ;;
        fabric)
            info "Скачивание Fabric сервера..."
            # Получение информации о Fabric Installer
            FABRIC_INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/0.11.2/fabric-installer-0.11.2.jar"
            wget -O fabric-installer.jar "$FABRIC_INSTALLER_URL"
            java -jar fabric-installer.jar server -downloadMinecraft -mcversion "$MINECRAFT_VERSION"
            mv fabric-server-launch.jar server.jar 2>/dev/null || {
                error "Не удалось установить Fabric сервер."
                exit 1
            }
            ;;
        forge)
            info "Скачивание Forge сервера..."
            warning "Forge требует ручного указания URL. Пожалуйста, скачайте установщик с https://files.minecraftforge.net/"
            read -p "Введите URL для Forge установщика: " FORGE_URL
            wget -O forge-installer.jar "$FORGE_URL"
            java -jar forge-installer.jar --installServer
            mv forge-*-universal.jar server.jar 2>/dev/null || {
                error "Не удалось установить Forge сервер."
                exit 1
            }
            ;;
    esac
}

# Скачивание сервера
download_server

if [ ! -f "server.jar" ]; then
    error "server.jar не найден. Установка не удалась."
    exit 1
fi

success "Сервер скачан успешно!"

# Настройка параметров сервера
echo ""
read -p "Введите название сервера (по умолчанию: Minecraft Server): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-Minecraft Server}

read -p "Введите максимальное количество игроков (по умолчанию: 20): " MAX_PLAYERS
MAX_PLAYERS=${MAX_PLAYERS:-20}

read -p "Введите порт сервера (по умолчанию: 25565): " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-25565}

read -p "Введите размер памяти для сервера в GB (по умолчанию: 2): " MEMORY_GB
MEMORY_GB=${MEMORY_GB:-2}

# Создание eula.txt
info "Создание eula.txt..."
echo "eula=true" > eula.txt

# Создание server.properties
info "Создание server.properties..."
cat > server.properties <<EOF
#Minecraft Server Properties
#$(date)
motd=$SERVER_NAME
server-port=$SERVER_PORT
max-players=$MAX_PLAYERS
online-mode=true
white-list=false
enforce-whitelist=false
spawn-protection=16
max-world-size=29999984
function-permission-level=2
max-tick-time=60000
use-native-transport=true
enable-jmx-monitoring=false
enable-status=true
broadcast-rcon-to-ops=true
view-distance=10
simulation-distance=10
server-ip=
resource-pack=
resource-pack-prompt=
resource-pack-sha1=
max-build-height=320
require-resource-pack=false
spawn-monsters=true
spawn-animals=true
spawn-npcs=true
allow-flight=false
pvp=true
difficulty=easy
gamemode=survival
force-gamemode=false
hardcore=false
enable-command-block=false
broadcast-console-to-ops=true
enable-query=false
player-idle-timeout=0
max-chained-neighbor-updates=1000000
rate-limit=0
list-online-players=true
entity-broadcast-range-percentage=100
sync-chunk-writes=true
op-permission-level=4
prevent-proxy-connections=false
hide-online-players=false
resource-pack-sha1=
entity-broadcast-range-percentage=100
simulation-distance=10
rcon.port=25575
enable-rcon=false
EOF

# Создание скрипта запуска
info "Создание скрипта запуска..."
cat > start.sh <<EOF
#!/bin/bash
cd "$INSTALL_DIR"

# Проверка, не запущен ли уже сервер
if screen -list | grep -q "minecraft"; then
    echo "Сервер уже запущен! Используйте ./console.sh для подключения к консоли."
    exit 1
fi

# Запуск сервера в screen сессии
screen -dmS minecraft bash -c "java -Xms${MEMORY_GB}G -Xmx${MEMORY_GB}G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar server.jar nogui"

sleep 2
if screen -list | grep -q "minecraft"; then
    echo "Сервер запущен в screen сессии 'minecraft'"
    echo "Используйте ./console.sh для подключения к консоли"
    echo "Используйте ./logs.sh для просмотра логов"
else
    echo "Ошибка: Не удалось запустить сервер!"
    exit 1
fi
EOF

# Создание скрипта остановки
info "Создание скрипта остановки..."
cat > stop.sh <<EOF
#!/bin/bash
cd "$INSTALL_DIR"

if ! screen -list | grep -q "minecraft"; then
    echo "Сервер не запущен!"
    exit 1
fi

echo "Остановка сервера..."
screen -S minecraft -X stuff "stop$(printf \\r)"
sleep 3

# Ждем завершения сервера
for i in {1..30}; do
    if ! screen -list | grep -q "minecraft"; then
        echo "Сервер успешно остановлен!"
        exit 0
    fi
    sleep 1
done

# Если сервер не остановился, принудительно завершаем
if screen -list | grep -q "minecraft"; then
    echo "Принудительное завершение..."
    screen -S minecraft -X quit
    sleep 1
    echo "Сервер остановлен принудительно"
else
    echo "Сервер остановлен!"
fi
EOF

# Создание скрипта для подключения к консоли
info "Создание скрипта консоли..."
cat > console.sh <<EOF
#!/bin/bash
cd "$INSTALL_DIR"

if ! screen -list | grep -q "minecraft"; then
    echo "Сервер не запущен! Запустите его с помощью ./start.sh"
    exit 1
fi

echo "Подключение к консоли сервера..."
echo "Команды для управления screen:"
echo "  - Для отключения без остановки сервера: нажмите Ctrl+A, затем D"
echo "  - Для остановки и отключения: введите 'stop' в консоли, затем Ctrl+A, затем D"
echo ""
echo "Нажмите Enter для подключения..."
read

screen -r minecraft
EOF

# Создание скрипта для просмотра логов
info "Создание скрипта просмотра логов..."
cat > logs.sh <<EOF
#!/bin/bash
cd "$INSTALL_DIR"

if [ ! -d "logs" ]; then
    echo "Папка logs не найдена. Сервер возможно еще не запускался."
    exit 1
fi

LATEST_LOG="logs/latest.log"

if [ ! -f "\$LATEST_LOG" ]; then
    echo "Лог файл не найден: \$LATEST_LOG"
    exit 1
fi

echo "Просмотр логов сервера (последние 50 строк)..."
echo "Для просмотра в реальном времени используйте: tail -f \$LATEST_LOG"
echo "Для просмотра всех логов: cat \$LATEST_LOG"
echo ""
echo "=== Последние 50 строк логов ==="
tail -n 50 "\$LATEST_LOG"

echo ""
echo ""
read -p "Показать логи в реальном времени? (y/n): " FOLLOW
if [ "\$FOLLOW" = "y" ] || [ "\$FOLLOW" = "Y" ]; then
    echo "Просмотр логов в реальном времени (Ctrl+C для выхода)..."
    tail -f "\$LATEST_LOG"
fi
EOF

# Создание скрипта для отправки команд в консоль
info "Создание скрипта отправки команд..."
cat > command.sh <<EOF
#!/bin/bash
cd "$INSTALL_DIR"

if ! screen -list | grep -q "minecraft"; then
    echo "Сервер не запущен!"
    exit 1
fi

if [ -z "\$1" ]; then
    echo "Использование: ./command.sh <команда>"
    echo "Примеры:"
    echo "  ./command.sh \"say Привет всем!\""
    echo "  ./command.sh \"give PlayerName diamond 64\""
    echo "  ./command.sh \"list\""
    echo "  ./command.sh \"whitelist add PlayerName\""
    exit 1
fi

COMMAND="\$*"
screen -S minecraft -X stuff "\$COMMAND\$(printf \\r)"
echo "Команда отправлена: \$COMMAND"
EOF

chmod +x start.sh stop.sh console.sh logs.sh command.sh

# Создание systemd service (опционально)
echo ""
read -p "Создать systemd service для автозапуска? (y/n): " CREATE_SERVICE
if [ "$CREATE_SERVICE" = "y" ] || [ "$CREATE_SERVICE" = "Y" ]; then
    info "Создание systemd service..."
    
    # Определение пользователя
    read -p "Введите имя пользователя для запуска сервера (по умолчанию: minecraft): " MC_USER
    MC_USER=${MC_USER:-minecraft}
    
    # Создание пользователя если не существует
    if ! id "$MC_USER" &>/dev/null; then
        useradd -r -s /bin/false "$MC_USER"
        chown -R "$MC_USER:$MC_USER" "$INSTALL_DIR"
    fi
    
    cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=simple
User=$MC_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/java -Xms${MEMORY_GB}G -Xmx${MEMORY_GB}G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar $INSTALL_DIR/server.jar nogui
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable minecraft.service
    
    success "Systemd service создан!"
    info "Управление сервером:"
    info "  Запуск:   systemctl start minecraft"
    info "  Остановка: systemctl stop minecraft"
    info "  Статус:   systemctl status minecraft"
fi

# Настройка прав доступа
chmod +x start.sh
if [ -n "$MC_USER" ]; then
    chown -R "$MC_USER:$MC_USER" "$INSTALL_DIR" 2>/dev/null || chown -R "$(whoami):$(whoami)" "$INSTALL_DIR"
else
    chown -R "$(whoami):$(whoami)" "$INSTALL_DIR"
fi

# Финальная информация
echo ""
success "=== Установка завершена! ==="
info "Директория сервера: $INSTALL_DIR"
info "Версия: Minecraft $MINECRAFT_VERSION"
info "Ядро: $SERVER_TYPE"
info "Порт: $SERVER_PORT"
info "Память: ${MEMORY_GB}GB"
echo ""
info "=== Управление сервером ==="
info ""
info "Запуск сервера:"
info "  cd $INSTALL_DIR"
info "  ./start.sh"
info ""
info "Остановка сервера:"
info "  ./stop.sh"
info ""
info "Подключение к консоли сервера (для ввода команд):"
info "  ./console.sh"
info "  (Для отключения без остановки: Ctrl+A, затем D)"
info ""
info "Просмотр логов:"
info "  ./logs.sh"
info ""
info "Отправка команды в консоль без подключения:"
info "  ./command.sh \"say Привет всем!\""
info "  ./command.sh \"list\""
info "  ./command.sh \"give PlayerName diamond 64\""
info ""
if [ "$CREATE_SERVICE" = "y" ] || [ "$CREATE_SERVICE" = "Y" ]; then
    info "Управление через systemd:"
    info "  Запуск:   systemctl start minecraft"
    info "  Остановка: systemctl stop minecraft"
    info "  Статус:   systemctl status minecraft"
    info "  Логи:     journalctl -u minecraft -f"
    info ""
fi
echo ""
warning "ВАЖНО: Убедитесь, что порт $SERVER_PORT открыт в файрволе!"
info "Для Ubuntu/Debian: ufw allow $SERVER_PORT/tcp"
info "Для CentOS/RHEL: firewall-cmd --permanent --add-port=$SERVER_PORT/tcp && firewall-cmd --reload"
echo ""
info "=== Полезные команды Minecraft ==="
info "  list              - список игроков онлайн"
info "  op <ник>          - выдать права оператора"
info "  deop <ник>        - убрать права оператора"
info "  whitelist add <ник> - добавить в белый список"
info "  ban <ник>         - забанить игрока"
info "  pardon <ник>      - разбанить игрока"
info "  say <сообщение>   - отправить сообщение всем"
info "  give <ник> <предмет> [количество] - выдать предмет"
info "  gamemode <режим> [ник] - изменить режим игры"
info "  save-all          - сохранить мир"
info "  stop              - остановить сервер"

