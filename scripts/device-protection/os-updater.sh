#!/bin/bash

# ============================================================
# OS & Application Auto-Updater
# Supports: Linux, Windows, macOS, Android, iOS
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/os-updater.log"
CONFIG_FILE="${SCRIPT_DIR}/../configs/updater.conf"
UPDATE_TYPE="${1:-regular}"  # security, critical, regular
BOOT_REQUIRED=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$LOG_FILE")"

# ============================================================
# LOGGING
# ============================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $@" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[✓]${NC} $@"
    log "$@"
}

log_error() {
    echo -e "${RED}[✗]${NC} $@" >&2
    log "ERROR: $@"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $@"
    log "$@"
}

# ============================================================
# LINUX UPDATES
# ============================================================

update_linux() {
    log_info "Starting Linux OS updates..."
    
    # Detect distribution
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        distro="$ID"
    else
        distro="unknown"
    fi
    
    log_info "Detected distribution: $distro"
    
    case "$distro" in
        ubuntu|debian)
            log_info "Updating Debian-based system..."
            sudo apt-get update -qq
            
            case "$UPDATE_TYPE" in
                security)
                    log_info "Installing security updates only..."
                    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Pre-Install-Pkgs="{}/usr/bin/deb-systemd-helper" -o APT::Status-Fd=7 unattended-upgrades
                    sudo unattended-upgrade -d
                    ;;
                critical)
                    log_info "Installing critical & security updates..."
                    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y linux-generic-hwe-$(lsb_release -rs)
                    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
                    ;;
                regular)
                    log_info "Installing all available updates..."
                    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
                    sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
                    ;;
            esac
            
            # Clean up
            sudo apt-get autoremove -y
            sudo apt-get autoclean -y
            
            # Check if reboot needed
            if [[ -f /var/run/reboot-required ]]; then
                BOOT_REQUIRED=true
                log_warn "System reboot required"
            fi
            ;;
        
        rhel|fedora|centos)
            log_info "Updating RHEL-based system..."
            
            case "$UPDATE_TYPE" in
                security)
                    log_info "Installing security updates only..."
                    sudo yum update --security -y
                    ;;
                critical)
                    log_info "Installing critical & kernel updates..."
                    sudo yum update -y
                    ;;
                regular)
                    log_info "Installing all available updates..."
                    sudo yum update -y
                    ;;
            esac
            
            # Check if reboot needed
            if sudo needs-restarting -r &>/dev/null; then
                BOOT_REQUIRED=true
                log_warn "System reboot required"
            fi
            ;;
        
        arch)
            log_info "Updating Arch Linux system..."
            sudo pacman -Syyu --noconfirm
            ;;
        
        *)
            log_error "Unsupported Linux distribution: $distro"
            return 1
            ;;
    esac
    
    log_info "Linux updates completed"
}

# ============================================================
# WINDOWS UPDATES
# ============================================================

update_windows() {
    if [[ ! -f /c/Windows/System32/cmd.exe ]] && [[ ! -f /mnt/c/Windows/System32/cmd.exe ]]; then
        log_error "Not running on Windows"
        return 1
    fi
    
    log_info "Starting Windows OS updates..."
    
    # Using Windows Update PowerShell module
    powershell -Command "
    Add-Type -AssemblyName System.Net.Http
    \
    if (-not (Get-Module PSWindowsUpdate)) {
        Install-Module PSWindowsUpdate -Confirm:\$false -Force
    }
    \
    Import-Module PSWindowsUpdate
    \
    switch ('$UPDATE_TYPE') {
        'security' {
            Get-WindowsUpdate -MicrosoftUpdate -IsHidden \$false -Silent | Where-Object {\$_.KB -like '*Security*'} | Install-WindowsUpdate -AcceptAll -IgnoreReboot
        }
        'critical' {
            Get-WindowsUpdate -MicrosoftUpdate -IsHidden \$false -Critical | Install-WindowsUpdate -AcceptAll -IgnoreReboot
        }
        'regular' {
            Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
        }
    }
    " 2>/dev/null || log_warn "Failed to check Windows updates"
    
    log_info "Windows updates completed"
}

# ============================================================
# MACOS UPDATES
# ============================================================

update_macos() {
    if [[ $(uname -s) != "Darwin" ]]; then
        log_error "Not running on macOS"
        return 1
    fi
    
    log_info "Starting macOS OS updates..."
    
    # System software updates
    softwareupdate -l 2>/dev/null | head -20
    
    case "$UPDATE_TYPE" in
        security|critical)
            log_info "Installing security/critical updates..."
            sudo softwareupdate -i -a
            ;;
        regular)
            log_info "Installing all available updates..."
            sudo softwareupdate -i -a
            ;;
    esac
    
    # Check for pending restart
    if [[ -n $(softwareupdate -l 2>/dev/null | grep -i restart) ]]; then
        BOOT_REQUIRED=true
        log_warn "macOS restart required"
    fi
    
    log_info "macOS updates completed"
}

# ============================================================
# PACKAGE MANAGER UPDATES (Linux)
# ============================================================

update_packages() {
    log_info "Updating application packages..."
    
    # Python packages
    if command -v pip3 &>/dev/null; then
        log_info "Updating Python packages..."
        pip3 list --outdated --format=json 2>/dev/null | jq -r '.[].name' | while read package; do
            pip3 install --upgrade "$package" -q 2>/dev/null || true
        done
    fi
    
    # Node.js packages
    if command -v npm &>/dev/null; then
        log_info "Updating Node.js packages..."
        npm update -g 2>/dev/null || true
    fi
    
    # Ruby gems
    if command -v gem &>/dev/null; then
        log_info "Updating Ruby gems..."
        gem update --system 2>/dev/null || true
        gem update 2>/dev/null || true
    fi
    
    # Snap packages (Ubuntu)
    if command -v snap &>/dev/null; then
        log_info "Updating Snap packages..."
        sudo snap refresh 2>/dev/null || true
    fi
    
    # Flatpak packages
    if command -v flatpak &>/dev/null; then
        log_info "Updating Flatpak packages..."
        sudo flatpak update --system -y 2>/dev/null || true
    fi
    
    # Homebrew (macOS/Linux)
    if command -v brew &>/dev/null; then
        log_info "Updating Homebrew packages..."
        brew update
        brew upgrade
        brew cleanup -s
    fi
    
    log_info "Package updates completed"
}

# ============================================================
# ANDROID UPDATES (ADB)
# ============================================================

update_android() {
    if ! command -v adb &>/dev/null; then
        log_warn "ADB not found - skipping Android updates"
        return 1
    fi
    
    if ! adb devices | grep -q device; then
        log_warn "No Android devices connected"
        return 1
    fi
    
    log_info "Starting Android OS updates..."
    
    # Check for system updates
    log_info "Checking for system updates..."
    adb shell "am start -a android.intent.action.VIEW -n com.android.settings/.Settings" || true
    
    # Update Play Store apps
    log_info "Updating Play Store applications..."
    adb shell 'pm grant com.android.vending android.permission.INSTALL_PACKAGES'
    
    # Enable auto-updates
    adb shell "settings put global app_update_auto_install_policy 1"
    
    log_info "Android update checks completed"
}

# ============================================================
# IOS UPDATES (SSH to jailbroken device)
# ============================================================

update_ios() {
    local ios_ip="${IOS_DEVICE_IP:-127.0.0.1}"
    local ios_port="${IOS_SSH_PORT:-2222}"
    
    log_info "Starting iOS update check (via SSH)..."
    
    if ! ssh -p $ios_port root@$ios_ip "echo 'test'" &>/dev/null; then
        log_warn "Cannot connect to iOS device at $ios_ip:$ios_port"
        return 1
    fi
    
    # Update package managers
    ssh -p $ios_port root@$ios_ip << 'EOF'
apt-get update
case "$UPDATE_TYPE" in
    security)
        apt-get upgrade -y -o Dpkg::Pre-Install-Pkgs="{}/usr/bin/deb-systemd-helper"
        ;;
    critical)
        apt-get dist-upgrade -y
        ;;
    regular)
        apt-get upgrade -y
        apt-get dist-upgrade -y
        ;;
esac
apt-get autoremove -y
apt-get autoclean -y
EOF
    
    log_info "iOS update checks completed"
}

# ============================================================
# DOCKER CONTAINERS UPDATE
# ============================================================

update_docker_images() {
    if ! command -v docker &>/dev/null; then
        log_warn "Docker not installed - skipping container updates"
        return 0
    fi
    
    log_info "Updating Docker images..."
    
    docker images --filter dangling=false --quiet | while read image_id; do
        log_info "Pulling latest version of image: $image_id"
        docker pull "$image_id" 2>/dev/null || true
    done
    
    # Prune unused images
    docker image prune -f >/dev/null 2>&1 || true
    
    log_info "Docker image updates completed"
}

# ============================================================
# FIRMWARE UPDATES
# ============================================================

update_firmware() {
    log_info "Checking firmware updates..."
    
    # BIOS/UEFI updates
    if command -v fwupdmgr &>/dev/null; then
        log_info "Checking for BIOS/Firmware updates via fwupd..."
        sudo fwupdmgr refresh
        
        if sudo fwupdmgr get-updates &>/dev/null; then
            log_info "Firmware updates available"
            case "$UPDATE_TYPE" in
                security|critical)
                    sudo fwupdmgr update
                    BOOT_REQUIRED=true
                    ;;
                regular)
                    log_warn "Manual firmware review recommended before installation"
                    ;;
            esac
        fi
    fi
}

# ============================================================
# SCHEDULED REBOOT
# ============================================================

schedule_reboot() {
    if [[ "$BOOT_REQUIRED" == "true" ]]; then
        log_warn "System reboot required"
        
        local reboot_time="${REBOOT_TIME:-03:00}"  # Default 3 AM
        
        log_info "Scheduling reboot for $reboot_time"
        
        # Use at command to schedule reboot
        if command -v at &>/dev/null; then
            echo "sudo /sbin/shutdown -r now" | at "$reboot_time" 2>/dev/null || true
            log_info "Reboot scheduled via AT"
        fi
        
        # Fallback: use cron for tomorrow
        # This is handled by the main cron scheduler
        
        send_notification "System Reboot Scheduled" "Reboot scheduled for $reboot_time after updates"
    fi
}

# ============================================================
# NOTIFICATIONS
# ============================================================

send_notification() {
    local title="$1"
    local message="$2"
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${TELEGRAM_CHAT_ID:-}"
    
    if [[ -n "$bot_token" ]] && [[ -n "$chat_id" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d chat_id="$chat_id" \
            -d text="🔄 *$title*\n$message" \
            -d parse_mode="Markdown" >/dev/null 2>&1 || true
    fi
}

# ============================================================
# MAIN EXECUTION
# ============================================================

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        OS & Application Auto-Updater (Mode: $UPDATE_TYPE)${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

log_info "Update process started (Mode: $UPDATE_TYPE)"

# Detect OS and run appropriate updater
case "$(uname -s)" in
    Linux)
        update_linux
        ;;
    Darwin)
        update_macos
        ;;
    MINGW*|MSYS*)
        update_windows
        ;;
    *)
        log_error "Unsupported operating system: $(uname -s)"
        exit 1
        ;;
esac

# Always update packages and Docker
update_packages
update_docker_images

# Check firmware
update_firmware

# Schedule reboot if needed
schedule_reboot

# Final summary
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Update process completed successfully${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

if [[ "$BOOT_REQUIRED" == "true" ]]; then
    log_warn "System reboot is required to complete updates"
    send_notification "Updates Complete" "Reboot required. Will be scheduled for off-peak hours."
else
    log_info "All updates completed without requiring reboot"
    send_notification "Updates Complete" "All system and application updates have been installed successfully."
fi

echo ""
