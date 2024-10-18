#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/system_hardening.log"
VER=$(lsb_release -rs)
DATE=$(date)
DRY_RUN=false

trap 'echo "[!] Error on line $LINENO"; exit 1' ERR
trap 'echo "[+] Cleaning up resources..."; # add clean-up code here' EXIT

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Backup function
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.bak.$(date +%F_%T)"
        log "[+] Backed up $file to ${file}.bak.$(date +%F_%T)"
    fi
}

# Dry-run log function
dry_run_log() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $1"
    else
        log "$1"
        eval "$1"
    fi
}

# Check Ubuntu version
check_version() {
    case $VER in
        "16.04" | "18.04" | "20.04" | "22.04" | "24.01")
            log "[+] Ubuntu $VER detected"
            ;;
        *)
            log "[!] This Ubuntu version $VER is not supported"
            exit 1
            ;;
    esac
}

# Disable IPv6
dis_ipv6() {
    case $VER in
        "16.04")
            backup_file /etc/sysctl.conf
            dry_run_log "echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf"
            dry_run_log "echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf"
            dry_run_log "echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf"
            dry_run_log "sysctl -p"
            ;;
        "18.04" | "20.04" | "22.04" | "24.01")
            backup_file /etc/default/grub
            dry_run_log "sed -i -e 's/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"ipv6.disable=1\"/' /etc/default/grub"
            dry_run_log "update-grub"
            ;;
        *)
            log "[!] Unsupported version $VER for disabling IPv6"
            exit 1
            ;;
    esac
}

# Update repository with a timeout
update_repo() {
    dry_run_log "timeout 300 apt-get update"
}

# Upgrade repository with a timeout
upgrade_repo() {
    dry_run_log "timeout 300 apt-get upgrade -y"
}

# Autoremove unused packages
autoremove_repo() {
    dry_run_log "timeout 300 apt-get autoremove -y"
}

# Install services with backup
install_service() {
    dry_run_log "apt-get -yq install $1"
}

# Check for network interface
check_network_interface() {
    if ifconfig | grep "inet" > /dev/null; then
        log "[+] Network interface is up"
    else
        log "[!] No active network interface found"
        exit 1
    fi
}

# Check dependencies and network
check_dependency() {
    # check root
    if [[ $EUID -ne 0 ]]; then
       log "[!] This script must be run as root"
       exit 1
    fi

    # check network interface
    check_network_interface

    # check network status (internet and DNS)
    if ping -q -c 3 -W 1 www.google.com > /dev/null 2>&1; then
        log "[+] Checking network OK"
    else
        if ping -q -c 3 -W 1 8.8.8.8 > /dev/null 2>&1; then
            log "[!] Check your DNS settings"
            exit $?
        else
            log "[!] Check your NETWORK settings"
            exit $?
        fi
    fi

    # check whiptail
    if which whiptail > /dev/null 2>&1; then
        log "[+] Checking whiptail OK"
    else
        install_service whiptail
    fi
}

# Confirmation to disable IPv6
get_confirmation_ipv6_disable() {
    if (whiptail --title "IPv6" --yesno "This script will disable IPv6. Do you agree?" 8 78); then
        log "[+] Disabling IPv6..."
        dis_ipv6
    fi
}

# Reconfigure date
reconfig_date() {
    if (whiptail --title "Date" --yesno "The current date is $DATE. Is it correct?" 8 78); then
        :
    else
        log "[+] Reconfiguring date..."
        dry_run_log "dpkg-reconfigure tzdata"
    fi
}

# Reboot confirmation with timeout
cmd_reboot() {
    whiptail --title "Rebooting..." --msgbox "This server will reboot in 5 seconds. If you're connected via SSH, please reconnect after the reboot." 8 78
    log "[+] Rebooting system in 5 seconds..."
    sleep 5
    dry_run_log "timeout 30 reboot"
}

# Main display
display_ascii() {
    echo -e '
        
    ░██████╗███████╗██████╗░██╗░░░██╗███████╗██████╗░░░░░░░██╗███╗░░██╗██╗████████╗
    ██╔════╝██╔════╝██╔══██╗██║░░░██║██╔════╝██╔══██╗░░░░░░██║████╗░██║██║╚══██╔══╝
    ╚█████╗░█████╗░░██████╔╝╚██╗░██╔╝█████╗░░██████╔╝█████╗██║██╔██╗██║██║░░░██║░░░
    ░╚═══██╗██╔══╝░░██╔══██╗░╚████╔╝░██╔══╝░░██╔══██╗╚════╝██║██║╚████║██║░░░██║░░░
    ██████╔╝███████╗██║░░██║░░╚██╔╝░░███████╗██║░░██║░░░░░░██║██║░╚███║██║░░░██║░░░
    ╚═════╝░╚══════╝╚═╝░░╚═╝░░░╚═╝░░░╚══════╝╚═╝░░╚═╝░░░░░░╚═╝╚═╝░░╚══╝╚═╝░░░╚═╝░░░                                              
    '
    sleep 3
}

# Run main function
main() {
    display_ascii

    check_version

    check_dependency

    get_confirmation_ipv6_disable

    reconfig_date

    update_repo

    upgrade_repo

    autoremove_repo

    cmd_reboot
}

# Optional dry-run mode
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
    esac
done

main
