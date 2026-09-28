#!/bin/bash
set -e

VERSION="0.4.3"

# =============================================================================
# Non-interactive mode (optional)
#
# Set environment variables below to skip interactive prompts.
# When a variable is set, the corresponding read/select is bypassed.
# When unset, the script behaves interactively as before.
#
# Run with sudo -E to preserve environment variables.
#
# --- Common variables (all targets) ---
#   OBS_TARGET            Install target: 1=CE, 2=Pro stable, 3=Pro rolling,
#                         4=UNIX-Agent only, 5=SNMPD only, 6=Remote poller
#   OBS_INSTALL_SNMPD     Install SNMPD: "y" or "n" (default: y for targets 1-3,6)
#   OBS_INSTALL_AGENT     Install UNIX-Agent: "y" or "n" (default: n)
#
# --- CE and Pro/Ent (targets 1, 2, 3) ---
#   OBS_APACHE_OVERWRITE  Overwrite existing Apache config: "y" or "n"
#   OBS_MYSQL_ROOT        MySQL/MariaDB root password (empty = auto-generate)
#   OBS_MYSQL_DB          Database name (default: "observium")
#   OBS_ADMIN_USER        Observium web admin username (empty = "observium")
#   OBS_ADMIN_PASS        Observium web admin password (empty = auto-generate)
#   OBS_SNMP_COMMUNITY    SNMP v2c community string (empty = auto-generate)
#
# --- Pro/Ent only (targets 2, 3) ---
#   OBS_SVN_USER          SVN username for Pro/Ent checkout
#   OBS_SVN_PASSWORD      SVN password for Pro/Ent checkout
#
# --- Remote poller only (target 6) ---
#   OBS_SVN_USER          SVN username
#   OBS_SVN_PASSWORD      SVN password
#   OBS_MYSQL_HOST        Remote MySQL host:port
#   OBS_MYSQL_USER        Remote MySQL username (default: "observium")
#   OBS_MYSQL_PASSWORD    Remote MySQL password
#   OBS_RRDCACHED_HOST    Remote RRDCacheD host:port
#   OBS_POLLER_NAME       Poller name (default: hostname -f)
#
# --- Examples ---
#
# CE non-interactive:
#   sudo OBS_TARGET=1 OBS_MYSQL_ROOT="rootpass" OBS_ADMIN_USER="admin" \
#        OBS_ADMIN_PASS="secret" OBS_SNMP_COMMUNITY="public" \
#        OBS_APACHE_OVERWRITE=y OBS_INSTALL_SNMPD=y OBS_INSTALL_AGENT=n \
#        bash <(wget -qO- https://www.observium.org/observium_installscript.sh)
#
# Pro/Ent stable non-interactive:
#   sudo OBS_TARGET=2 OBS_SVN_USER="user" OBS_SVN_PASSWORD="pass" \
#        OBS_MYSQL_ROOT="rootpass" OBS_ADMIN_USER="admin" \
#        OBS_ADMIN_PASS="secret" OBS_SNMP_COMMUNITY="public" \
#        OBS_APACHE_OVERWRITE=y OBS_INSTALL_SNMPD=y OBS_INSTALL_AGENT=n \
#        bash <(wget -qO- https://www.observium.org/observium_installscript.sh)
#
# Remote poller non-interactive:
#   sudo OBS_TARGET=6 OBS_SVN_USER="user" OBS_SVN_PASSWORD="pass" \
#        OBS_MYSQL_HOST="db.example.com:3306" OBS_MYSQL_USER="observium" \
#        OBS_MYSQL_PASSWORD="dbpass" OBS_RRDCACHED_HOST="rrd.example.com:42217" \
#        OBS_POLLER_NAME="poller-eu-1" \
#        OBS_INSTALL_SNMPD=y OBS_INSTALL_AGENT=n \
#        bash <(wget -qO- https://www.observium.org/observium_installscript.sh)
#
# SNMP only with UNIX agent non-interactive:
#  sudo OBS_TARGET=5 OBS_INSTALL_AGENT=y OBS_SNMP_COMMUNITY="public" \
#       bash <(wget -qO- https://www.observium.org/observium_installscript.sh)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# examples:
# generate_password 12                  # uses default A-Za-z0-9
# generate_password 16 'A-Za-z0-9!@#$'  # custom allowed characters
# echo "Generated password: $(generate_password 12)"
function generate_password() {
    local length="$1"
    # Default charset is strictly alphanumeric — no underscore (MySQL LIKE/host-grant
    # wildcard) or quote characters that could break SQL/sed interpolation downstream.
    local allowed_chars="${2:-A-Za-z0-9}"

    if [[ -z "$length" || ! "$length" =~ ^[0-9]+$ ]]; then
        echo "Usage: generate_password <length> [allowed_chars]"
        return 1
    fi

    LC_ALL=C tr -dc "$allowed_chars" < /dev/urandom | head -c "$length"
    echo
}

function get_ip() {
    # Get first non-loopback local IP (prefer IPv4)
    local local_ip=$(hostname -I | awk '{for (i=1; i<=NF; i++) if ($i !~ /^127\./ && $i !~ /:/) { print $i; exit }}')

    # If no internal IP found, fallback to external IP
    if [[ -z "$local_ip" ]]; then
        local_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
        [[ -z "$local_ip" ]] && local_ip=$(curl -s https://api.ipify.org)
    fi

    echo "$local_ip"
}

function observiumfound {
    observium_found="no"
    if [ -d "/opt/observium" ]; then
        observium_found="yes"
        if [ -f "/opt/observium/config.php" ] && command -v php >/dev/null 2>&1; then
            observium_found="configured"
        fi
    fi
}

function verify_svn_credentials {
    echo -e "${GREEN} [*] Verifying SVN credentials...${NC}"
    if svn info --username "$svn_user" --password "$svn_password" --non-interactive https://svn.observium.org/svn/observium/branches/stable >/dev/null 2>&1; then
        echo -e "${GREEN} [*] SVN credentials OK${NC}"
    else
        echo -e "${RED}ERROR: SVN authentication failed for user '${svn_user}'.${NC}"
        echo -e "${RED}Please check your credentials at https://www.observium.org/subs/${NC}"
        exit 1
    fi
}

function agentinstall {
    if [ -d "/run/systemd/system" ] && [ -f "/opt/observium/scripts/systemd/observium_agent.socket" ]; then
        echo -e "${GREEN}Installing systemd unix-agent service...${NC}"
        cp /opt/observium/scripts/systemd/observium_agent.service /etc/systemd/system/observium_agent\@.service
        cp /opt/observium/scripts/systemd/observium_agent.socket /etc/systemd/system/observium_agent.socket
        systemctl daemon-reload
        systemctl enable observium_agent.socket
        systemctl start observium_agent.socket
        apt -qq install -y dmidecode
    else
        echo -e "${GREEN}Installing xinetd unix-agent service...${NC}"
        apt-get -qq install -y xinetd libwww-perl dmidecode
        cp /opt/observium/scripts/observium_agent_xinetd /etc/xinetd.d/observium_agent_xinetd
        service xinetd restart
    fi
    
    cp /opt/observium/scripts/observium_agent /usr/bin/observium_agent
    mkdir -p /usr/lib/observium_agent
    mkdir -p /usr/lib/observium_agent/scripts-available
    mkdir -p /usr/lib/observium_agent/scripts-enabled
    cp -r /opt/observium/scripts/agent-local/* /usr/lib/observium_agent/scripts-available
    chmod +x /usr/bin/observium_agent
    ln -sf /usr/lib/observium_agent/scripts-available/dmi /usr/lib/observium_agent/scripts-enabled
    ln -sf /usr/lib/observium_agent/scripts-available/dpkg /usr/lib/observium_agent/scripts-enabled
    
    if [ "$observium_target" -lt "4" ]; then
        ln -sf /usr/lib/observium_agent/scripts-available/apache /usr/lib/observium_agent/scripts-enabled
        ln -sf /usr/lib/observium_agent/scripts-available/mysql /usr/lib/observium_agent/scripts-enabled
    fi


    echo "\$config['poller_modules']['unix-agent']                   = 1;" >> /opt/observium/config.php
    echo -e "${GREEN}DONE! UNIX-agent is installed and this server is now monitored by Observium${NC}"
}

function snmpdinstall {
    echo -e "${GREEN}Installing snmpd...${NC}"
    apt-get -qq install -y snmpd

    observiumfound
    if [ "$observium_found" = "no" ]; then
        # Observium not installed, download distro from site
        echo -e "${YELLOW}Installing distro script${NC}"
        if command -v curl >/dev/null 2>&1; then
            curl -s -o /usr/local/bin/distro https://www.observium.org/files/distro
        else
            wget -O /usr/local/bin/distro https://www.observium.org/files/distro
        fi
    else
        # locally installed observium, copy from scripts
        echo -e "${YELLOW}Copy distro script${NC}"
        cp /opt/observium/scripts/distro /usr/local/bin/distro
    fi
    chmod +x /usr/local/bin/distro

    if [ "$observium_target" = "6" ] || [ "$observium_found" != "configured" ]; then
        echo -e "${YELLOW}Reconfiguring snmpd for remote connections${NC}"
        # remote poller or snmp only install
        hostname="$(hostname -f)"
        # WARNING. Remote pollers have troubles with ip 127.0.1.1 (default in debian for hosts)
        echo "agentAddress udp:161" > /etc/snmp/snmpd.conf
    else
        echo -e "${YELLOW}Reconfiguring snmpd for localhost only${NC}"
        # common install, probably better to use full hostname..
        hostname="localhost"
        echo "agentAddress  udp:127.0.0.1:161" > /etc/snmp/snmpd.conf
    fi
    if [ -n "${OBS_SNMP_COMMUNITY:-}" ]; then
        snmpcommunity="$OBS_SNMP_COMMUNITY"
        echo -e "${GREEN} [*] Using SNMP community from OBS_SNMP_COMMUNITY${NC}"
    else
        snmpcommunity="$(generate_password 15)"
    fi
    echo "rocommunity $snmpcommunity" >> /etc/snmp/snmpd.conf

    # Distro sctipt
    echo "# This line allows Observium to detect the host OS if the distro script is installed" >> /etc/snmp/snmpd.conf
    echo "extend .1.3.6.1.4.1.2021.7890.1 distro /usr/local/bin/distro" >> /etc/snmp/snmpd.conf

    # Vendor/hardware extending
    if [ -f "/sys/devices/virtual/dmi/id/product_name" ]; then
        echo "# This lines allows Observium to detect hardware, vendor and serial" >> /etc/snmp/snmpd.conf
        echo "extend .1.3.6.1.4.1.2021.7890.2 hardware /bin/cat /sys/devices/virtual/dmi/id/product_name" >> /etc/snmp/snmpd.conf
        echo "extend .1.3.6.1.4.1.2021.7890.3 vendor   /bin/cat /sys/devices/virtual/dmi/id/sys_vendor" >> /etc/snmp/snmpd.conf
        echo "#extend .1.3.6.1.4.1.2021.7890.4 serial   /bin/cat /sys/devices/virtual/dmi/id/product_serial" >> /etc/snmp/snmpd.conf
    elif [ -f "/proc/device-tree/model" ]; then
        # ARM/RPi specific hardware
        echo "# This lines allows Observium to detect hardware, vendor and serial" >> /etc/snmp/snmpd.conf
        echo "extend .1.3.6.1.4.1.2021.7890.2 hardware /bin/cat /proc/device-tree/model" >> /etc/snmp/snmpd.conf
        echo "#extend .1.3.6.1.4.1.2021.7890.4 serial   /bin/cat /proc/device-tree/serial" >> /etc/snmp/snmpd.conf
    fi

    # Accurate uptime
    echo "# This line allows Observium to collect an accurate uptime" >> /etc/snmp/snmpd.conf
    echo "extend uptime /bin/cat /proc/uptime" >> /etc/snmp/snmpd.conf

    echo "# This line enables Observium's ifAlias description injection" >> /etc/snmp/snmpd.conf
    echo "#pass_persist .1.3.6.1.2.1.31.1.1.1.18 /usr/local/bin/ifAlias_persist" >> /etc/snmp/snmpd.conf

    echo "# AgentX Sub-agents for services like LLDP" >> /etc/snmp/snmpd.conf
    echo "master agentx" >> /etc/snmp/snmpd.conf
    
    service snmpd restart

    if [ "$observium_found" = "configured" ]; then
        # observium install with php available, auto add host to db
        echo -e "${YELLOW}Adding $hostname to Observium${NC}"
        /opt/observium/add_device.php $hostname $snmpcommunity
        echo -e "${GREEN}DONE! SNMPD is installed and this server is now monitored by Observium${NC}"
    else
        # snmpd without observium or without php
        echo -e "${YELLOW}You can add host to Observium${NC}"
        echo -e "      SNMP hostname: ${BOLD}$hostname${NC}"
        echo -e " SNMP v2c community: ${BOLD}$snmpcommunity${NC}"
        echo -e "${GREEN}DONE! SNMPD is installed and this server can be monitored by Observium${NC}"
    fi
}

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}" 2>&1
    # Check if running from pipe/process substitution
    if [[ "$0" =~ ^/dev/fd/ ]]; then
        echo -e "${YELLOW}Please run: ${BOLD}sudo bash <(wget -qO- http://www.observium.org/observium_installscript.sh)${NC}" 2>&1
    else
        echo -e "${YELLOW}Please use: ${BOLD}sudo $0${NC}" 2>&1
    fi
    exit 1
fi

# OS, Version and Arch
function is_redhat_based() {
    local ID ID_LIKE
    
    if [[ -f /etc/os-release ]]; then
        ID=$(awk -F= '/^ID=/{gsub(/"/,"",$2);print $2}' /etc/os-release)
        ID_LIKE=$(awk -F= '/^ID_LIKE=/{gsub(/"/,"",$2);print $2}' /etc/os-release)

        if [[ "$ID_LIKE" == *rhel* ]] ||
           [[ "$ID" == "rhel" ]] ||
           [[ "$ID" == "fedora" ]] ||
           [[ "$ID" == "rocky" ]] ||
           [[ "$ID" == "almalinux" ]] ||
           [[ "$ID" == "ol" ]]; then
            return 0
        fi
    fi

    [[ -f /etc/redhat-release || -f /etc/centos-release ]] && return 0

    return 1
}
        
ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')

if [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    OS=Debian  # XXX or Ubuntu??
    VER=$(cat /etc/debian_version)
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

# Experimental: map Debian/Ubuntu derivatives (Devuan, Raspberry Pi OS,
# Armbian) onto their upstream identity using codenames from /etc/os-release,
# so they fall through to the existing Debian/Ubuntu install branches.
if [[ "$OS" =~ ^(Devuan|Raspbian|Armbian)$ ]]; then
    derivative_name="$OS"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ -n "${UBUNTU_CODENAME:-}" ]; then
            OS=Ubuntu
            case "$UBUNTU_CODENAME" in
                focal)    VER="20.04" ;;
                jammy)    VER="22.04" ;;
                noble)    VER="24.04" ;;
                resolute) VER="26.04" ;;
            esac
        else
            OS=Debian
            case "${VERSION_CODENAME:-}" in
                buster)   VER="10" ;;
                bullseye) VER="11" ;;
                bookworm) VER="12" ;;
                trixie)   VER="13" ;;
            esac
        fi
    fi
    echo -e "${YELLOW} [*] Detected ${derivative_name}; treating as ${OS} ${VER} (experimental).${NC}"
    unset derivative_name
fi

if is_redhat_based; then
    echo -e "${RED} [*] ERROR: This installscript does not support $OS distro, only Debian or Ubuntu supported.${NC}"
    echo "     Use the manual guide at https://docs.observium.org/install_rhel/"
    exit 1
elif [[ !$OS =~ ^(Ubuntu|Debian)$ ]]; then
    echo -e "${RED} [*] ERROR: This installscript does not support $OS distro, only Debian or Ubuntu supported.${NC}"
    exit 1
fi

cat << "EOF"
  ___  _                         _
 / _ \| |__  ___  ___ _ ____   _(_)_   _ _ __ ___
| | | | '_ \/ __|/ _ \ '__\ \ / / | | | | '_ ` _ \
| |_| | |_) \__ \  __/ |   \ V /| | |_| | | | | | |
 \___/|_.__/|___/\___|_|    \_/ |_|\__,_|_| |_| |_|
EOF
echo -e ""
echo -e "${GREEN}Welcome to Observium installation script v${VERSION}"
echo -e ""
echo -e "Please select the version of Observium you would like to install${NC}"
echo -e ""
echo -e "1. Observium ${BOLD}Community Edition${NC}"
echo -e "2. Observium ${BOLD}Pro/Ent Edition ${GREEN}stable${NC} (requires account at https://www.observium.org/subs/)"
echo -e "3. Observium ${BOLD}Pro/Ent Edition ${YELLOW}rolling${NC} (requires account at https://www.observium.org/subs/)"
echo -e "4. Install the UNIX-Agent"
echo -e "5. Install the SNMPD (snmpd-config will be overwritten)"
echo -e "6. ${YELLOW}Remote poller${NC} for ${BOLD}Observium Pro/Ent Edition ${GREEN}stable${NC} (requires account at https://www.observium.org/subs/)"
echo -n "(1-6): "
if [ -n "${OBS_TARGET:-}" ]; then
    observium_target="$OBS_TARGET"
    echo "$observium_target (from OBS_TARGET)"
else
    read -n 1 observium_target
    echo -e ""
fi

# Validate input
if [[ ! "$observium_target" =~ ^[1-6]$ ]]; then
    echo -e "${RED} [*] ERROR: Invalid option '$observium_target'. Please enter a number from 1 to 6.${NC}"
    exit 1
fi

echo "you choose $observium_target"
echo " "

# check already installed Observium
observiumfound
if [ "$observium_target" = "4" ]; then
    if [ "$observium_found" = "no" ]; then
        echo -e "${YELLOW} Observium not installed. Please install it before installing UNIX-Agent${NC}"
    fi
    agentinstall
    exit 1
elif [ "$observium_target" = "5" ]; then
    snmpdinstall
    exit 1
fi

# Database name (used in SQL commands and config.php)
mysql_db="${OBS_MYSQL_DB:-observium}"

if [ "$observium_found" = "yes" ]; then
    echo -e "${RED} Observium already installed.${NC}"
    echo -e " Please follow update procedure: https://docs.observium.org/#upgrading-observium"
    echo -e " or backup and remove /opt/observium directory for reinstall."
    exit 1
fi

if [ "$observium_target" = "2" ] || [ "$observium_target" = "3" ]; then
    echo -e "${BOLD} Your SVN username and password can be found after logging in at: https://www.observium.org/subs/${NC}"
    if [ -n "${OBS_SVN_USER:-}" ]; then
        svn_user="$OBS_SVN_USER"
    else
        read -p "Please enter your SVN Username: " svn_user
    fi
    if [ -n "${OBS_SVN_PASSWORD:-}" ]; then
        svn_password="$OBS_SVN_PASSWORD"
    else
        read -s -p "Please enter your SVN Password: " svn_password
    fi
    echo -e ""

    mysql_user="observium"
elif [ "$observium_target" = "6" ]; then
    # echo -e "${BOLD} Requested installing Remote poller for Observium Pro/Ent${NC}"
    # echo -e ""
    
    echo -e "${BOLD} You have selected: Remote poller for Observium Pro/Ent Edition (stable).${NC}"
    echo -e ""
    echo -e "${RED} IMPORTANT: Before continuing, make sure you have already installed:${NC}"
    echo -e "   •{BOLD} The main poller (primary Observium instance)${NC}"
    echo "   • A remote MySQL database (accessible from this host)"
    echo "   • A remote RRDCacheD service (accessible from this host)"
    echo -e ""
        
    echo -e "${YELLOW}Please enter your params...${NC}"
    echo -e "${BOLD} Your SVN username and password can be found after logging in at: https://www.observium.org/subs/${NC}"
    if [ -n "${OBS_SVN_USER:-}" ]; then
        svn_user="$OBS_SVN_USER"
    else
        read -p "  SVN Username: " svn_user
    fi
    if [ -n "${OBS_SVN_PASSWORD:-}" ]; then
        svn_password="$OBS_SVN_PASSWORD"
    else
        read -s -p "  SVN Password: " svn_password
    fi
    echo -e ""

    echo -e "${BOLD} Your MySQL server should be remotely accessed to DB 'observium' with this username and password${NC}"
    if [ -n "${OBS_MYSQL_HOST:-}" ]; then
        mysql_host="$OBS_MYSQL_HOST"
    else
        read -p "  MySQL Host:Port: " mysql_host
    fi
    if [ -n "${OBS_MYSQL_USER:-}" ]; then
        mysql_user="$OBS_MYSQL_USER"
    else
        read -p "  MySQL Username [observium]: " mysql_user
    fi
    mysql_user=${mysql_user:-observium}
    if [ -n "${OBS_MYSQL_PASSWORD:-}" ]; then
        mysql_password="$OBS_MYSQL_PASSWORD"
    else
        read -s -p "  MySQL Password: " mysql_password
    fi
    echo -e ""

    # Verify remote MySQL credentials early (warning only — can be fixed in config.php later)
    echo -e "${GREEN} [*] Verifying remote MySQL credentials...${NC}"
    if mysql -u "$mysql_user" -p"$mysql_password" -h "$mysql_host" -D "$mysql_db" -e "SELECT 1" >/dev/null 2>&1; then
        echo -e "${GREEN} [*] Remote MySQL credentials OK${NC}"
    else
        echo -e "${YELLOW}WARNING: Cannot connect to MySQL at ${mysql_host} as '${mysql_user}' to database '${mysql_db}'.${NC}"
        echo -e "${YELLOW}Please check host, username, password and that database '${mysql_db}' exists.${NC}"
        echo -e "${YELLOW}You can fix this later in /opt/observium/config.php${NC}"
    fi

    if [ -n "${OBS_RRDCACHED_HOST:-}" ]; then
        rrdcahed_host="$OBS_RRDCACHED_HOST"
    else
        read -p "  RRDCacheD Host:Port: " rrdcahed_host
    fi
    echo -e ""

    hostname="$(hostname -f)"
    if [ -n "${OBS_POLLER_NAME:-}" ]; then
        observium_poller="$OBS_POLLER_NAME"
    else
        read -p "  Observium Poller Name [$hostname]: " observium_poller
    fi
    if [ -z "${observium_poller}" ]; then
        observium_poller=$hostname
    fi
    echo -e ""
elif [ "$observium_target" = "1" ]; then
    echo -e "${BOLD} Requested installing Observium CE${NC}"
    echo -e ""
    mysql_user="observium"
else
    echo -e "${RED} [*] ERROR: Invalid option $observium_target${NC}"
    exit 1
fi

if [ "$observium_target" -lt "4" ]; then
    if [ -f /etc/apache2/sites-available/000-default.conf ] || [ -f /etc/apache2/sites-available/default ]; then
        echo -e "${YELLOW}WARNING: Apache default configuration was found. This script will overwrite that configuration, and your current settings will be lost.${NC}"
        if [ -n "${OBS_APACHE_OVERWRITE:-}" ]; then
            case "$OBS_APACHE_OVERWRITE" in
                y|Y|yes|Yes|YES)
                    echo "Apache config will be overwritten... (from OBS_APACHE_OVERWRITE)"
                    ;;
                *)
                    echo "Apache overwrite declined (from OBS_APACHE_OVERWRITE). Exiting..."
                    exit 1
                    ;;
            esac
        else
            echo "Continue?"
            select yn in "Yes" "No"; do
                case $yn in
                    Yes )
                        echo "Apache config will be overwritten..."
                        break
                        ;;
                    No )
                        echo "Exiting..."
                        exit 1
                        ;;
                esac
            done
        fi
    fi

    # mysql server only for base install
    mysql_already_installed="no"
    if $(dpkg --list mysql-server 2>/dev/null | egrep -q ^ii) || $(dpkg --list mariadb-server 2>/dev/null | egrep -q ^ii); then
        mysql_already_installed="yes"
    fi

    if [ -n "${OBS_MYSQL_ROOT:-}" ]; then
        # Non-interactive: use provided MySQL root password
        mysql_root="$OBS_MYSQL_ROOT"
        echo -e "${GREEN} [*] Using MySQL root password from OBS_MYSQL_ROOT${NC}"
    elif [ "$mysql_already_installed" = "yes" ]; then
        echo -e "${YELLOW}WARNING: A MySQL server is already installed. Do you know the root password for this server?${NC}"
        select yn in "Yes" "No"; do
            case $yn in
                Yes )
                    echo "Please enter the MySQL root password and press [ENTER]"
                    read -s mysql_root
                    break
                    ;;
                No )
                    echo "Exiting..."
                    exit 1
                    ;;
            esac
        done
    else
        echo -e "${GREEN} [*] No MySQL server was detected on this server. Installing MySQL...${NC}"
        echo "Choose a MySQL root password. Leave empty to generate a random password."
        read -s mysql_root
        # Generate root password if variable is empty
        [[ -z "$mysql_root" ]] && mysql_root="$(generate_password 15)"
    fi

    # Verify MySQL root credentials if server is already running
    if [ "$mysql_already_installed" = "yes" ]; then
        echo -e "${GREEN} [*] Verifying MySQL root credentials...${NC}"
        if ! mysql -uroot -p"$mysql_root" -e "SELECT 1" >/dev/null 2>&1; then
            echo -e "${RED}ERROR: Cannot connect to MySQL with provided root password.${NC}"
            echo -e "${RED}Please check the password and try again.${NC}"
            exit 1
        fi
        echo -e "${GREEN} [*] MySQL root credentials OK${NC}"
    fi
    
    echo "mysql-server mysql-server/root_password password $mysql_root" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $mysql_root" | debconf-set-selections
fi

echo -e "${GREEN} [*] Starting package installation; this may take up to 30 minutes${NC}"
if [ "$OS" = "Ubuntu" ] && [ "$VER" = "16.04" ]; then
    # Unsupported!
    echo -e "${RED} [*] UNSUPPORTED! We are on Ubuntu 16.04 LTS, installing packages...${NC}"
    apt-get -qq update
    apt-get -qq install -y php7.0-cli php7.0-mysql php7.0-gd php7.0-mcrypt php7.0-json php7.0-bcmath php7.0-mbstring php7.0-curl php-apcu php-pear snmp fping  mysql-client python-mysqldb rrdtool subversion whois mtr-tiny ipmitool
    phpenmod mcrypt
    if [ "$observium_target" -lt "4" ]; then
        apt-get -qq install -y libapache2-mod-php7.0 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php7.0
    fi
elif [ "$OS" = "Ubuntu" ] && [ "$VER" = "17.04" ]; then
    # Unsupported!
    echo -e "${RED} [*] UNSUPPORTED! We are on Ubuntu 17.04, installing packages...${NC}"
    apt-get -qq update
    apt-get -qq install -y php7.0-cli php7.0-mysql php7.0-gd php7.0-mcrypt php7.0-json php7.0-bcmath php7.0-mbstring php7.0-curl php-apcu php-pear snmp fping mysql-client python-mysqldb rrdtool subversion whois mtr-tiny ipmitool
    phpenmod mcrypt
    if [ "$observium_target" -lt "4" ]; then
        apt-get -qq install -y libapache2-mod-php7.0 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php7.0
    fi
elif [ "$OS" = "Ubuntu" ] && [ "$VER" = "17.10" ]; then
    # Unsupported!
    echo -e "${RED} [*] UNSUPPORTED! We are on Ubuntu 17.10, installing packages...${NC}"
    apt-get -qq update
    apt-get -qq install -y php7.1-cli php7.1-mysql php7.1-gd php7.1-mcrypt php7.1-json php7.1-bcmath php7.1-mbstring php7.1-opcache php7.1-curl php-apcu php-pear snmp fping mysql-client python-mysqldb rrdtool subversion whois mtr-tiny ipmitool libvirt-clients
    phpenmod mcrypt
    if [ "$observium_target" -lt "4" ]; then
        apt-get -qq install -y libapache2-mod-php7.1 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php7.1
    fi
elif [ "$OS" = "Ubuntu" ] && [ "$VER" = "18.04" ]; then
    # Unsupported!
    echo -e "${RED} [*] UNSUPPORTED! We are on Ubuntu 18.04 (Bionic Beaver), installing packages...${NC}"
    add-apt-repository universe -y
    add-apt-repository multiverse -y
    apt -qq update
    apt -qq install -y php7.2-cli php7.2-mysql php7.2-gd php7.2-json php7.2-bcmath php7.2-mbstring php7.2-opcache php7.2-curl php-apcu php-pear snmp fping mysql-client python-mysqldb rrdtool subversion whois mtr-tiny ipmitool libvirt-clients
    #phpenmod mcrypt
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y libapache2-mod-php7.2 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php7.2
    fi
elif [ "$OS" = "Ubuntu" ] && [ "$VER" = "20.04" ]; then
    echo -e "${GREEN} [*] We are on Ubuntu 20.04 (Focal Fossa), installing packages...${NC}"
    add-apt-repository universe -y
    add-apt-repository multiverse -y
    apt -qq update
    apt -qq install -y --no-install-recommends php7.4-cli php7.4-mysql php7.4-gd php7.4-json php7.4-bcmath php7.4-mbstring php7.4-opcache php7.4-curl php-apcu php-pear snmp fping mysql-client rrdtool subversion whois mtr-tiny ipmitool libvirt-clients python3-mysqldb python3-pymysql python-is-python3
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php7.4 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php7.4
    fi
elif [ "$OS" = "Ubuntu" ] && [ "$VER" = "21.04" ]; then
    echo -e "${GREEN} [*] We are on Ubuntu 21.04, installing packages...${NC}"
    echo -e "${YELLOW} [*] Please note that we generally recommend using the latest Ubuntu LTS release.${NC}"
    add-apt-repository universe -y
    add-apt-repository multiverse -y
    apt -qq update
    apt -qq install -y --no-install-recommends php7.4-cli php7.4-mysql php7.4-gd php7.4-json php7.4-bcmath php7.4-mbstring php7.4-opcache php7.4-curl php-apcu php-pear snmp fping mysql-client rrdtool subversion whois mtr-tiny ipmitool libvirt-clients python3-mysqldb python3-pymysql python-is-python3
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php7.4 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php7.4
    fi
elif [ "$OS" = "Ubuntu" ] && [ "$VER" = "22.04" ]; then
    echo -e "${GREEN} [*] We are on Ubuntu 22.04 (Jammy Jellyfish), installing PHP 8.1 and other packages...${NC}"
    add-apt-repository universe -y
    add-apt-repository multiverse -y
    apt -qq update
    apt -qq install -y --no-install-recommends php8.1-cli php8.1-mysql php8.1-gd php8.1-bcmath php8.1-mbstring php8.1-opcache php8.1-curl php-apcu php-pear snmp fping mysql-client rrdtool subversion whois mtr-tiny ipmitool libvirt-clients python3-mysqldb python3-pymysql python-is-python3
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php8.1 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php8.1
    fi
elif [ "$OS" = "Ubuntu" ] && [ "$VER" = "24.04" ]; then
    echo -e "${GREEN} [*] We are on Ubuntu 24.04 (Noble Numbat), installing PHP 8.3 and other packages...${NC}"
    add-apt-repository universe -y
    add-apt-repository multiverse -y
    apt -qq update
    apt -qq install -y --no-install-recommends php8.3-cli php8.3-mysql php8.3-gd php8.3-bcmath php8.3-mbstring php8.3-opcache php8.3-curl php-apcu php-pear snmp fping mysql-client rrdtool subversion whois mtr-tiny ipmitool libvirt-clients apparmor-utils python3-mysqldb python3-pymysql python-is-python3
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php8.3 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php8.3
    fi
    # https://docs.observium.org/syslog/
    echo -e "${YELLOW} [*] Disabling AppArmor enforcement for rsyslogd...${NC}"
    sudo aa-disable /etc/apparmor.d/usr.sbin.rsyslogd || echo -e "${YELLOW} [*] WARNING: aa-disable failed (non-fatal, continuing)${NC}"
elif [ "$OS" = "Ubuntu" ] && [ "$VER" = "26.04" ]; then
    echo -e "${GREEN} [*] We are on Ubuntu 26.04 (Resolute Wombat), installing PHP 8.5 and other packages...${NC}"
    add-apt-repository universe -y
    add-apt-repository multiverse -y
    apt -qq update
    apt -qq install -y --no-install-recommends php8.5-cli php8.5-mysql php8.5-gd php8.5-bcmath php8.5-mbstring php8.5-curl php-apcu php-pear snmp fping mysql-client rrdtool subversion whois mtr-tiny ipmitool libvirt-clients apparmor-utils python3-mysqldb python3-pymysql python-is-python3
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php8.5 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php8.5
    fi
    # https://docs.observium.org/syslog/
    echo -e "${YELLOW} [*] Disabling AppArmor enforcement for rsyslogd...${NC}"
    sudo aa-disable /etc/apparmor.d/usr.sbin.rsyslogd || echo -e "${YELLOW} [*] WARNING: aa-disable failed (non-fatal, continuing)${NC}"
elif [ "$OS" = "Debian" ] && [[ "$VER" =~ ^8.* ]]; then
    echo -e "${RED} [*] UNSUPPORTED! We are on Debian 8.x (Jessie), installing packages...${NC}"
    # Unsupported!
    apt-get -qq update
    apt-get -qq install -y php7.0-cli php7.0-mysql php7.0-gd php7.0-libsodium php7.0-mcrypt php7.0-json php7.0-bcmath php7.0-mbstring php7.0-opcache php7.0-apcu php7.0-curl php-pear snmp fping mysql-client python-mysqldb rrdtool subversion whois mtr-tiny ipmitool
    phpenmod mcrypt
    if [ "$observium_target" -lt "4" ]; then
        apt-get -qq install -y libapache2-mod-php7.0 graphviz imagemagick mysql-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php7.0
    fi
elif [ "$OS" = "Debian" ] && [[ "$VER" =~ ^9.* ]]; then
    # Unsupported!
    echo -e "${RED} [*] UNSUPPORTED! We are on Debian 9.x (Stretch), installing packages...${NC}"
    apt-get -qq update
    apt-get -qq install -y php7.0-cli php7.0-mysql php7.0-gd php7.0-libsodium php7.0-mcrypt php7.0-json php7.0-bcmath php7.0-mbstring php7.0-opcache php7.0-apcu php7.0-curl php-pear snmp fping mariadb-client python-mysqldb rrdtool subversion whois mtr-tiny ipmitool
    phpenmod mcrypt
    if [ "$observium_target" -lt "4" ]; then
        apt-get -qq install -y libapache2-mod-php7.0 graphviz imagemagick mariadb-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
        a2enmod php7.0
    fi
elif [ "$OS" = "Debian" ] && [[ "$VER" =~ ^10.* ]]; then
    # Unsupported!
    echo -e "${RED} [*] UNSUPPORTED! We are on Debian 10.x (Buster), installing PHP 7.3 and other packages...${NC}"
    apt -qq update
    apt -qq install -y --no-install-recommends php7.3-cli php7.3-mysql php7.3-gd php7.3-json php7.3-bcmath php7.3-mbstring php7.3-opcache php7.3-apcu php7.3-curl php-pear snmp fping mariadb-client python-mysqldb rrdtool subversion whois mtr-tiny ipmitool libvirt-clients
    #phpenmod mcrypt
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php7.3 graphviz imagemagick mariadb-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
    fi
elif [ "$OS" = "Debian" ] && [[ "$VER" =~ ^11.* ]]; then
    echo -e "${GREEN} [*] We are on Debian 11.x (Bullseye), installing PHP 7.4 and other packages...${NC}"
    apt -qq update
    apt -qq install -y --no-install-recommends php7.4-cli php7.4-mysql php7.4-gd php7.4-json php7.4-bcmath php7.4-mbstring php7.4-opcache php7.4-apcu php7.4-curl php-pear snmp fping mariadb-client python3-mysqldb rrdtool subversion whois mtr-tiny ipmitool libvirt-clients python-is-python3 python3-pymysql
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php7.4 graphviz imagemagick mariadb-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
    fi
elif [ "$OS" = "Debian" ] && [[ "$VER" =~ ^12.* ]]; then
    echo -e "${GREEN} [*] We are on Debian 12.x (Bookworm), installing PHP 8.2 and other packages...${NC}"
    apt -qq update
    apt -qq install -y --no-install-recommends php8.2-cli php8.2-mysql php8.2-gd php8.2-bcmath php8.2-mbstring php8.2-opcache php8.2-apcu php8.2-curl php-json php-pear snmp fping mariadb-client python3-mysqldb python3-pymysql python-is-python3 rrdtool subversion whois mtr-tiny ipmitool libvirt-clients
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php8.2 graphviz imagemagick mariadb-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
    fi
elif [ "$OS" = "Debian" ] && [[ "$VER" =~ ^13.* ]]; then
    echo -e "${GREEN} [*] We are on Debian 13.x (Trixie), installing PHP 8.4 and other packages...${NC}"
    apt -qq update
    apt -qq install -y --no-install-recommends php8.4-cli php8.4-mysql php8.4-gd php8.4-bcmath php8.4-mbstring php8.4-opcache php8.4-apcu php8.4-curl php-json php-pear snmp fping mariadb-client python3-mysqldb python3-pymysql python-is-python3 rrdtool subversion whois mtr-tiny ipmitool libvirt-clients
    if [ "$observium_target" -lt "4" ]; then
        apt -qq install -y --no-install-recommends libapache2-mod-php8.4 graphviz imagemagick mariadb-server apache2
        a2dismod mpm_event
        a2enmod mpm_prefork
    fi
else
    echo -e "${RED} [*] ERROR: This installscript does not support this distro version.${NC}"
    echo    "     Use the manual guide at https://docs.observium.org/install_debian/"
    echo "OS: $OS"
    echo "Version: $VER"
    exit 1
fi

# Verify SVN credentials now that subversion is installed
if [ "$observium_target" = "2" ] || [ "$observium_target" = "3" ] || [ "$observium_target" = "6" ]; then
    verify_svn_credentials
fi

# Ensure the database service is running after package installation.
# On some minimal/container systems the service may not auto-start.
if [ "$observium_target" -lt "4" ]; then
    if dpkg --list mariadb-server 2>/dev/null | egrep -q ^ii; then
        systemctl start mariadb 2>/dev/null || true
    else
        systemctl start mysql 2>/dev/null || true
    fi
fi

echo -e "${GREEN} [*] Creating Observium directory${NC}"
mkdir -p /opt/observium && cd /opt

if [ "$observium_target" = "1" ]; then
    echo -e "${GREEN} [*] Downloading Observium CE and unpacking...${NC}"
    wget -r -nv https://www.observium.org/observium-community-latest.tar.gz -O /opt/observium-community-latest.tar.gz
    tar zxf observium-community-latest.tar.gz --checkpoint=.1000
    echo " "
elif [ "$observium_target" = "2" ] || [ "$observium_target" = "6" ]; then
    echo -e "${GREEN} [*] Checking out Observium Pro/Ent stable from SVN${NC}"
    #echo "Your SVN username and password is found after you login at: https://www.observium.org/subs/"
    #read -p "Please enter your SVN username: " svn_user
    svn co -q --non-interactive --no-auth-cache --username "$svn_user" --password "$svn_password" https://svn.observium.org/svn/observium/branches/stable observium
elif [ "$observium_target" = "3" ]; then
    echo -e "${GREEN} [*] Checking out Observium Pro/Ent rolling from SVN${NC}"
    #echo "Your SVN username and password is found after you login at: https://www.observium.org/subs/"
    #read -p "Please enter your SVN username: " svn_user
    svn co -q --non-interactive --no-auth-cache --username "$svn_user" --password "$svn_password" https://svn.observium.org/svn/observium/trunk observium
fi

cd observium

# fixate community.inc.php if file exists but missing get_entity_group_names()
if [ "$observium_target" = "1" ] && [ -f "includes/community.inc.php" ]; then
    if ! grep -q 'function get_entity_group_names' "includes/community.inc.php"; then
        echo -e "${GREEN} [*] Patching includes/community.inc.php with stub functions...${NC}"
        cat > "includes/community.inc.php" << 'CMNT'
<?php

// stub functions for not exist features
function cache_groups() { return []; }
function get_type_groups($type = NULL, $check_permission = TRUE) { return []; }
function get_groups_by_type($type = NULL) { return []; }
function get_group_entities($group_ids, $entity_type = '') { return []; }
function get_group_entities_array($group_ids, $entity_type = '') { return []; }
function get_entity_group_names($entity_type, $entity_id) { return []; }

// EOF
CMNT
    else
        echo -e "${GREEN} [*] community.inc.php already contains get_entity_group_names(), skipping patch${NC}"
    fi
fi

if [ "$observium_target" -lt "4" ]; then
    # initial mysql db user/password creation
    echo -e "${GREEN} [*] Creating database user for Observium with a random password...${NC}"
    mysql_password="$(generate_password 15)"
    # Pass the root password via MYSQL_PWD instead of -p"…" to avoid the
    # "Using a password on the command line interface can be insecure" warning.
    export MYSQL_PWD="$mysql_root"
    mysql -uroot -e "CREATE DATABASE $mysql_db DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci"

    if [[ "$OS" = "Ubuntu" ]] && [[ "${VER%%.*}" -ge 20 ]]; then
        #echo -e "${GREEN} [*] We are on Ubuntu 20.04 LTS, installing packages...${NC}"
        mysql -uroot -e "CREATE USER 'observium'@'localhost' IDENTIFIED BY '$mysql_password'"
        mysql -uroot -e "GRANT ALL ON ${mysql_db}.* TO 'observium'@'localhost'"
    else
        mysql -uroot -e "GRANT ALL PRIVILEGES ON ${mysql_db}.* TO 'observium'@'localhost' IDENTIFIED BY '$mysql_password'"
    fi
    unset MYSQL_PWD

    # Disable binary logging — Observium does not need it and it wastes disk.
    # MySQL (Ubuntu) keeps configs in /etc/mysql/mysql.conf.d/
    # MariaDB (Debian) keeps configs in /etc/mysql/mariadb.conf.d/
    echo -e "${GREEN} [*] Disabling MySQL/MariaDB binary logging...${NC}"
    if dpkg --list mariadb-server 2>/dev/null | egrep -q ^ii; then
        # MariaDB
        MYSQL_CONF_DIR="/etc/mysql/mariadb.conf.d"
        MYSQL_SVC="mariadb"
    else
        # MySQL
        MYSQL_CONF_DIR="/etc/mysql/mysql.conf.d"
        MYSQL_SVC="mysql"
    fi
    mkdir -p "$MYSQL_CONF_DIR"
    cat > "${MYSQL_CONF_DIR}/99-observium-no-binlog.cnf" <<- 'NOBINLOG'
	[mysqld]
	skip-log-bin
	NOBINLOG
    systemctl restart "$MYSQL_SVC"
    echo -e "${GREEN} [*] Binary logging disabled${NC}"

elif [ "$observium_target" = "6" ]; then
    echo -e ""
    if mysql -u "$mysql_user" -p"$mysql_password" -h "$mysql_host" -D "$mysql_db" -e "SELECT VERSION();" > /dev/null 2>&1; then
        echo "Connection to database successful."
    else
        # still configure poller for manual config later
        echo "Failed to connect to database. Please check DB host/user/password and set correct in config.php"
    fi
fi

echo -e "${GREEN} [*] Creating Observium config-file...${NC}"
sed "s/'USERNAME'/'$mysql_user'/g" config.php.default > config.php
sed -i "s/'PASSWORD'/'$mysql_password'/g" config.php
if [ "$mysql_db" != "observium" ]; then
    sed -i "s/\$config\['db_name'\].*=.*'observium'/\$config['db_name']      = '$mysql_db'/" config.php
fi

echo -e "" >> config.php
echo -e "# Force minimum php memory 512M" >> config.php
echo -e "\$config['php_memory_limit_min'] = '512M';" >> config.php

if [ "$observium_target" = "6" ]; then
    # extra configurations for remote poller
    sed -i "s/'localhost'/'$mysql_host'/g" config.php

    echo -e "" >> config.php
    echo -e "# Remote poller" >> config.php
    echo -e "\$config['rrdcached']      = '$rrdcahed_host';" >> config.php
    echo -e "# Force get poller_id by host id if name changed" >> config.php
    echo -e "\$config['poller_by_host'] = TRUE;" >> config.php
    echo -e "\$config['poller_name']    = '$observium_poller';" >> config.php

fi

echo -e "${GREEN} [*] Creating log and RRD directories...${NC}"
id -u observium &>/dev/null || useradd -G www-data observium
mkdir -p logs
chown -R observium:observium logs
#this mode makes all files created inherit permissions of rrd/-folder
mkdir -p --mode=u+rwx,g+rs,o-w rrd
chown -R observium:www-data rrd
chmod -R g+w rrd

if [ "$observium_target" -lt "4" ]; then
    # DB schema upgrade & apache config for common install
    ./discovery.php -u

    apachever="$(apache2ctl -v)"
    if [[ "$apachever" == *"Apache/2.4"* ]]; then
        echo -e "${GREEN} [*] Apache version is 2.4, creating config...${NC}"
        cat > /etc/apache2/sites-available/000-default.conf <<- EOM
  <VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /opt/observium/html
    <FilesMatch \.php$>
      SetHandler application/x-httpd-php
    </FilesMatch>
    <Directory />
            Options FollowSymLinks
            AllowOverride None
    </Directory>
    <Directory /opt/observium/html/>
            DirectoryIndex index.php
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
    </Directory>
    ErrorLog  ${APACHE_LOG_DIR}/error.log
    LogLevel warn
    CustomLog  ${APACHE_LOG_DIR}/access.log combined
    ServerSignature On
  </VirtualHost>
EOM
        
        #echo "$APACHE24" > /etc/apache2/sites-available/000-default.conf
    elif [[ "$apachever" == *"Apache/2.2"* ]]; then
        echo -e "${GREEN} [*] Apache version is 2.2, creating config...${NC}"
        cat > /etc/apache2/sites-available/default <<- EOM
  <VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /opt/observium/html
    <FilesMatch \.php$>
      SetHandler application/x-httpd-php
    </FilesMatch>
    <Directory />
            Options FollowSymLinks
            AllowOverride None
    </Directory>
    <Directory /opt/observium/html/>
            DirectoryIndex index.php
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Order allow,deny
            allow from all
    </Directory>
    ErrorLog  ${APACHE_LOG_DIR}/error.log
    LogLevel warn
    CustomLog  ${APACHE_LOG_DIR}/access.log combined
    ServerSignature On
  </VirtualHost>
EOM
        
        #echo "$APACHE22" > /etc/apache2/sites-available/default
    else
        echo -e "${RED} [*] ERROR: Could not determine Apache version${NC}"
        exit 1
    fi
    a2enmod rewrite
    apache2ctl restart
    
    echo -e "${GREEN} [*] Create first Observium admin user. Leave empty to generate random password and username 'observium'${NC}"
    if [ -n "${OBS_ADMIN_USER:-}" ]; then
        observ_username="$OBS_ADMIN_USER"
    else
        read -p "Username: " observ_username
    fi
    # default username is observium
    [[ -z "$observ_username" ]] && observ_username="observium"
    if [ -n "${OBS_ADMIN_PASS:-}" ]; then
        observ_password="$OBS_ADMIN_PASS"
    else
        read -s -p "Password: " observ_password
    fi
    # Generate password if variable is empty
    [[ -z "$observ_password" ]] && observ_password="$(generate_password 15)"
    
    ./adduser.php $observ_username $observ_password 10

    echo -e "${GREEN} [*] Creating Observium cronjob...${NC}"
cat > /etc/cron.d/observium <<- EOM
# Run a complete discovery of all devices once every 6 hours
33  */6   * * *   observium   /opt/observium/observium-wrapper discovery >> /dev/null 2>&1
# Run automated discovery of newly added devices every 5 minutes
*/5 *     * * *   observium   /opt/observium/observium-wrapper discovery --host new >> /dev/null 2>&1
# Run multithreaded poller wrapper every 5 minutes
*/5 *     * * *   observium   /opt/observium/observium-wrapper poller >> /dev/null 2>&1

# Run housekeeping script daily for syslog, eventlog and alert log
13 5      * * *   observium   /opt/observium/housekeeping.php -ysel >> /dev/null 2>&1
# Run housekeeping script daily for rrds, ports, orphaned entries in the database and performance data
47 4      * * *   observium   /opt/observium/housekeeping.php -yrptb >> /dev/null 2>&1
EOM

    echo "--------------------------------------------"
    echo -e "Now you can access to ${BOLD}Observium:${NC} http://$(get_ip)"
    echo -e "${BOLD}Username:${NC} $observ_username"
    echo -e "${BOLD}Password:${NC} $observ_password"
    echo "--------------------------------------------"
else
    # remote poller, housekeeping disabled
    echo -e "${GREEN} [*] Creating Observium cronjob...${NC}"
cat > /etc/cron.d/observium <<- EOM
# Run a complete discovery of all devices once every 6 hours
33  */6   * * *   observium   /opt/observium/observium-wrapper discovery >> /dev/null 2>&1
# Run automated discovery of newly added devices every 5 minutes
*/5 *     * * *   observium   /opt/observium/observium-wrapper discovery --host new >> /dev/null 2>&1
# Run multithreaded poller wrapper every 5 minutes
*/5 *     * * *   observium   /opt/observium/observium-wrapper poller >> /dev/null 2>&1

# Run housekeeping script daily for syslog, eventlog and alert log
#13 5      * * *   observium   /opt/observium/housekeeping.php -ysel >> /dev/null 2>&1
# Run housekeeping script daily for rrds, ports, orphaned entries in the database and performance data
#47 4      * * *   observium   /opt/observium/housekeeping.php -yrptb >> /dev/null 2>&1
EOM

fi

# Fixate fping on ARM devices (required for proper ICMP ping functionality)
if [[ "$ARCH" =~ ^(aarch64|armv7l|armv6l|arm)$ ]] && [ -f /usr/bin/fping ]; then
    echo -e "${YELLOW} [*] ARM architecture detected, setting SUID bit on fping...${NC}"
    chmod u+s /usr/bin/fping
fi

echo -en "${GREEN}Would you like to install/configure SNMP daemon and monitor this host with Observium? ${YELLOW}(your snmpd-config will be overwritten!)${NC} (${BOLD}Y${NC}/n): "
if [ -n "${OBS_INSTALL_SNMPD:-}" ]; then
    yn="$OBS_INSTALL_SNMPD"
    echo "$yn (from OBS_INSTALL_SNMPD)"
else
    read -n 1 yn
    echo
fi
case $yn in
  No|no|N|n)
    echo "Skipping snmpd installation"
    ;;
  *)
    snmpdinstall
    ;;
esac

echo -en "${GREEN}Would you like to install the UNIX-agent on this host?${NC} (y/${BOLD}N${NC}): "
if [ -n "${OBS_INSTALL_AGENT:-}" ]; then
    yn="$OBS_INSTALL_AGENT"
    echo "$yn (from OBS_INSTALL_AGENT)"
else
    read -n 1 yn
    echo
fi
case $yn in
  Yes|YES|yes|Y|y)
    agentinstall
    ;;
  *)
    echo "Skipping unix-agent installation"
    ;;
esac

echo -e "${GREEN} [*] Installation complete! Open your web browser, log in to the web interface with the account you just created, and add your first device.${NC}"

# EOF
