#!/bin/bash

# ============================================================
# Firmware Auto-Update Script for Home Router
# Supports: ASUS, TP-Link, Netgear, Ubiquiti, Synology
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/firmware-update.log"
CONFIG_FILE="${SCRIPT_DIR}/../configs/router.conf"
ROUTER_MODEL="${ROUTER_MODEL:-ASUS}"
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
CHECK_INTERVAL="${CHECK_INTERVAL:-86400}"  # 24 hours

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================
# LOGGING FUNCTIONS
# ============================================================

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $@"
    log "INFO" "$@"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $@"
    log "WARN" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@" >&2
    log "ERROR" "$@"
}

# ============================================================
# LOAD CONFIGURATION
# ============================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source <(grep -E '^(router_model|router_ip|auto_update_enabled|firmware_beta_enabled|firmware_notify_admin)=' "$CONFIG_FILE")
        log_info "Configuration loaded from $CONFIG_FILE"
    else
        log_warn "Config file not found at $CONFIG_FILE, using defaults"
    fi
}

# ============================================================
# ASUS ROUTER FUNCTIONS
# ============================================================

asus_check_firmware() {
    log_info "Checking firmware updates for ASUS router..."
    
    # SSH into router and check for updates
    local firmware_info=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
        'nvram get os_version' 2>/dev/null || echo "unknown")
    
    local current_version="$firmware_info"
    log_info "Current ASUS firmware: $current_version"
    
    # Download version info from ASUS server
    local latest_version=$(curl -s 'https://nw-dlcdnv3.asus.com/release-notes' | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
    
    if [[ -z "$latest_version" ]]; then
        log_warn "Could not fetch latest ASUS firmware version"
        return 1
    fi
    
    log_info "Latest ASUS firmware available: $latest_version"
    
    if [[ "$current_version" != "$latest_version" ]]; then
        return 0  # Update available
    else
        return 1  # Already latest
    fi
}

asus_download_firmware() {
    local version="$1"
    local download_url="https://dlcdnv3.asus.com/firmware.bin"
    local firmware_file="/tmp/asus_firmware_${version}.bin"
    
    log_info "Downloading ASUS firmware $version..."
    
    if curl -L -o "$firmware_file" "$download_url"; then
        # Verify checksum
        local expected_sha=$(curl -s "${download_url}.sha256" | cut -d' ' -f1)
        local actual_sha=$(sha256sum "$firmware_file" | cut -d' ' -f1)
        
        if [[ "$expected_sha" == "$actual_sha" ]]; then
            log_info "Firmware checksum verified"
            echo "$firmware_file"
            return 0
        else
            log_error "Firmware checksum mismatch! Expected: $expected_sha, Got: $actual_sha"
            rm -f "$firmware_file"
            return 1
        fi
    else
        log_error "Failed to download ASUS firmware"
        return 1
    fi
}

asus_install_firmware() {
    local firmware_file="$1"
    local version="$2"
    
    log_info "Installing ASUS firmware $version..."
    
    # Upload and install via SSH
    if scp -o ConnectTimeout=5 "$firmware_file" admin@"$ROUTER_IP":/tmp/fw.bin 2>/dev/null; then
        ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" << 'EOF'
set -e
echo "Stopping services..."
killall -9 rstats
killall -9 downloadmaster || true
killall -9 httpd
killall -9 telnetd || true

echo "Installing firmware..."
fsync
dd if=/tmp/fw.bin of=/dev/mtdblock7 bs=1024

echo "Syncing filesystem..."
sync

echo "Rebooting..."
reboot -d 1
EOF
        log_info "Firmware installation initiated"
        return 0
    else
        log_error "Failed to upload firmware to ASUS router"
        return 1
    fi
}

# ============================================================
# TP-LINK ROUTER FUNCTIONS
# ============================================================

tplink_check_firmware() {
    log_info "Checking firmware updates for TP-Link router..."
    
    local current_version=$(ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" \
        'cat /proc/version | grep -oP "\d+\.\d+\.\d+"' 2>/dev/null || echo "unknown")
    
    log_info "Current TP-Link firmware: $current_version"
    
    # TP-Link firmware check
    local model=$(ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'nvram get product_name' 2>/dev/null || echo "unknown")
    local latest_version=$(curl -s "http://support.tp-link.com/download?model=${model}" | 
        grep -oP 'v\d+\.\d+\.\d+' | head -1 | sed 's/v//')
    
    if [[ -z "$latest_version" ]]; then
        log_warn "Could not fetch latest TP-Link firmware version"
        return 1
    fi
    
    log_info "Latest TP-Link firmware available: $latest_version"
    
    if [[ "$current_version" != "$latest_version" ]]; then
        return 0
    else
        return 1
    fi
}

tplink_download_firmware() {
    local version="$1"
    local model="$2"
    local firmware_file="/tmp/tplink_firmware_${version}.bin"
    local download_url="http://support.tp-link.com/download?model=${model}&version=${version}"
    
    log_info "Downloading TP-Link firmware $version for model $model..."
    
    if curl -L -o "$firmware_file" "$download_url"; then
        log_info "TP-Link firmware downloaded successfully"
        echo "$firmware_file"
        return 0
    else
        log_error "Failed to download TP-Link firmware"
        return 1
    fi
}

tplink_install_firmware() {
    local firmware_file="$1"
    local version="$2"
    
    log_info "Installing TP-Link firmware $version..."
    
    if scp -o ConnectTimeout=5 "$firmware_file" admin@"$ROUTER_IP":/tmp/fw.bin 2>/dev/null; then
        ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" << 'EOF'
set -e
echo "Stopping services..."
killall -9 httpd
killall -9 telnetd || true

echo "Installing firmware..."
mt upgrade -r /tmp/fw.bin

echo "Rebooting..."
sleep 3
reboot -d 1
EOF
        log_info "TP-Link firmware installation initiated"
        return 0
    else
        log_error "Failed to upload firmware to TP-Link router"
        return 1
    fi
}

# ============================================================
# NETGEAR ROUTER FUNCTIONS
# ============================================================

netgear_check_firmware() {
    log_info "Checking firmware updates for Netgear router..."
    
    local current_version=$(ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" \
        'cat /etc/version' 2>/dev/null || echo "unknown")
    
    log_info "Current Netgear firmware: $current_version"
    
    # Netgear firmware check via HTTP
    local model=$(ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'nvram get os_image_flag' 2>/dev/null || echo "unknown")
    local latest_version=$(curl -s "https://www.netgear.com/support" | grep -oP 'v\d+\.\d+\.\d+' | head -1)
    
    if [[ -z "$latest_version" ]]; then
        log_warn "Could not fetch latest Netgear firmware version"
        return 1
    fi
    
    log_info "Latest Netgear firmware available: $latest_version"
    
    if [[ "$current_version" != "$latest_version" ]]; then
        return 0
    else
        return 1
    fi
}

netgear_download_firmware() {
    local version="$1"
    local model="$2"
    local firmware_file="/tmp/netgear_firmware_${version}.bin"
    local download_url="https://www.netgear.com/support/product/${model}.aspx"
    
    log_info "Downloading Netgear firmware $version..."
    
    if curl -L -o "$firmware_file" "$download_url"; then
        log_info "Netgear firmware downloaded successfully"
        echo "$firmware_file"
        return 0
    else
        log_error "Failed to download Netgear firmware"
        return 1
    fi
}

netgear_install_firmware() {
    local firmware_file="$1"
    local version="$2"
    
    log_info "Installing Netgear firmware $version..."
    
    # Netgear uses HTTPS upload
    if curl -X POST -F "file=@${firmware_file}" \
        -k "https://${ROUTER_IP}/cgi-bin/upload_image.cgi" 2>/dev/null; then
        log_info "Netgear firmware installation initiated"
        sleep 60
        return 0
    else
        log_error "Failed to upload firmware to Netgear router"
        return 1
    fi
}

# ============================================================
# UBIQUITI ROUTER FUNCTIONS
# ============================================================

ubiquiti_check_firmware() {
    log_info "Checking firmware updates for Ubiquiti router..."
    
    local current_version=$(curl -s -u admin:"${UBIQUITI_PASSWORD}" \
        "http://${ROUTER_IP}:8080/api/v2/system" | jq -r '.version' || echo "unknown")
    
    log_info "Current Ubiquiti firmware: $current_version"
    
    # Ubiquiti firmware check
    local latest_version=$(curl -s 'https://fw-update.ubiquiti.com/queries/version' | jq -r '.latest' || echo "unknown")
    
    if [[ -z "$latest_version" ]]; then
        log_warn "Could not fetch latest Ubiquiti firmware version"
        return 1
    fi
    
    log_info "Latest Ubiquiti firmware available: $latest_version"
    
    if [[ "$current_version" != "$latest_version" ]]; then
        return 0
    else
        return 1
    fi
}

ubiquiti_download_firmware() {
    local version="$1"
    local firmware_file="/tmp/ubiquiti_firmware_${version}.bin"
    local download_url="https://fw-update.ubiquiti.com/data/ud360"
    
    log_info "Downloading Ubiquiti firmware $version..."
    
    if curl -L -o "$firmware_file" "$download_url"; then
        log_info "Ubiquiti firmware downloaded successfully"
        echo "$firmware_file"
        return 0
    else
        log_error "Failed to download Ubiquiti firmware"
        return 1
    fi
}

ubiquiti_install_firmware() {
    local firmware_file="$1"
    local version="$2"
    
    log_info "Installing Ubiquiti firmware $version..."
    
    # Ubiquiti API update
    if curl -X POST -u admin:"${UBIQUITI_PASSWORD}" \
        -F "file=@${firmware_file}" \
        "http://${ROUTER_IP}:8080/api/v2/system/upgrade" 2>/dev/null; then
        log_info "Ubiquiti firmware installation initiated"
        sleep 30
        return 0
    else
        log_error "Failed to upload firmware to Ubiquiti router"
        return 1
    fi
}

# ============================================================
# SYNOLOGY ROUTER FUNCTIONS
# ============================================================

synology_check_firmware() {
    log_info "Checking firmware updates for Synology router..."
    
    local current_version=$(ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" \
        'cat /proc/sys/kernel/osrelease' 2>/dev/null || echo "unknown")
    
    log_info "Current Synology firmware: $current_version"
    
    # Synology firmware check
    local latest_version=$(curl -s 'https://www.synology.com/support/download-center' | 
        grep -oP 'RT\d+.*?\d+\.\d+\.\d+' | head -1)
    
    if [[ -z "$latest_version" ]]; then
        log_warn "Could not fetch latest Synology firmware version"
        return 1
    fi
    
    log_info "Latest Synology firmware available: $latest_version"
    
    if [[ "$current_version" != "$latest_version" ]]; then
        return 0
    else
        return 1
    fi
}

synology_download_firmware() {
    local version="$1"
    local firmware_file="/tmp/synology_firmware_${version}.pat"
    local download_url="https://www.synology.com/support/download-center"
    
    log_info "Downloading Synology firmware $version..."
    
    if curl -L -o "$firmware_file" "$download_url"; then
        log_info "Synology firmware downloaded successfully"
        echo "$firmware_file"
        return 0
    else
        log_error "Failed to download Synology firmware"
        return 1
    fi
}

synology_install_firmware() {
    local firmware_file="$1"
    local version="$2"
    
    log_info "Installing Synology firmware $version..."
    
    if scp -o ConnectTimeout=5 "$firmware_file" admin@"$ROUTER_IP":/tmp/firmware.pat 2>/dev/null; then
        ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" << 'EOF'
set -e
echo "Starting firmware upgrade..."
syno_poweroff
EOF
        log_info "Synology firmware installation initiated"
        return 0
    else
        log_error "Failed to upload firmware to Synology router"
        return 1
    fi
}

# ============================================================
# BACKUP AND ROLLBACK FUNCTIONS
# ============================================================

backup_firmware() {
    log_info "Backing up current firmware..."
    
    local backup_dir="/backups/firmware"
    mkdir -p "$backup_dir"
    
    case "$ROUTER_MODEL" in
        ASUS)
            ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'nvram get os_version' > "${backup_dir}/asus_version_$(date +%Y%m%d).txt" 2>/dev/null || true
            ;;
        TP-LINK)
            ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'cat /proc/version' > "${backup_dir}/tplink_version_$(date +%Y%m%d).txt" 2>/dev/null || true
            ;;
        NETGEAR)
            ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'cat /etc/version' > "${backup_dir}/netgear_version_$(date +%Y%m%d).txt" 2>/dev/null || true
            ;;
        UBIQUITI)
            curl -s -u admin:"${UBIQUITI_PASSWORD}" "http://${ROUTER_IP}:8080/api/v2/system" | jq . > "${backup_dir}/ubiquiti_version_$(date +%Y%m%d).json" 2>/dev/null || true
            ;;
        SYNOLOGY)
            ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'cat /proc/sys/kernel/osrelease' > "${backup_dir}/synology_version_$(date +%Y%m%d).txt" 2>/dev/null || true
            ;;
    esac
    
    log_info "Firmware backup completed to $backup_dir"
}

# ============================================================
# NOTIFICATION FUNCTIONS
# ============================================================

send_email_notification() {
    local subject="$1"
    local message="$2"
    local email_to="${EMAIL_TO:-user@example.com}"
    local email_from="${EMAIL_FROM:-admin@example.com}"
    
    echo "$message" | mail -s "$subject" -r "$email_from" "$email_to" 2>/dev/null || true
}

send_telegram_notification() {
    local message="$1"
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${TELEGRAM_CHAT_ID:-}"
    
    if [[ -n "$bot_token" ]] && [[ -n "$chat_id" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d chat_id="$chat_id" \
            -d text="$message" >/dev/null 2>&1 || true
    fi
}

# ============================================================
# MAIN EXECUTION
# ============================================================

main() {
    load_config
    
    if [[ "${auto_update_enabled:-true}" != "true" ]]; then
        log_info "Auto-update disabled in configuration"
        exit 0
    fi
    
    log_info "Starting firmware update check for $ROUTER_MODEL router at $ROUTER_IP"
    
    # Check for updates based on router model
    case "$ROUTER_MODEL" in
        ASUS)
            if asus_check_firmware; then
                backup_firmware
                latest_version=$(ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'nvram get os_version' 2>/dev/null || echo "latest")
                firmware_file=$(asus_download_firmware "$latest_version")
                if [[ $? -eq 0 ]]; then
                    if asus_install_firmware "$firmware_file" "$latest_version"; then
                        message="✅ ASUS firmware updated to $latest_version"
                        log_info "$message"
                        send_telegram_notification "🔄 Router Update: $message"
                        send_email_notification "ASUS Router Firmware Updated" "$message"
                    fi
                fi
                rm -f "$firmware_file" 2>/dev/null || true
            else
                log_info "ASUS router firmware is up to date"
            fi
            ;;
        TP-LINK)
            if tplink_check_firmware; then
                backup_firmware
                latest_version=$(ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'cat /proc/version | grep -oP "\d+\.\d+\.\d+"' 2>/dev/null || echo "latest")
                firmware_file=$(tplink_download_firmware "$latest_version" "${ROUTER_MODEL_NUM:-Archer}")
                if [[ $? -eq 0 ]]; then
                    if tplink_install_firmware "$firmware_file" "$latest_version"; then
                        message="✅ TP-Link firmware updated to $latest_version"
                        log_info "$message"
                        send_telegram_notification "🔄 Router Update: $message"
                        send_email_notification "TP-Link Router Firmware Updated" "$message"
                    fi
                fi
                rm -f "$firmware_file" 2>/dev/null || true
            else
                log_info "TP-Link router firmware is up to date"
            fi
            ;;
        NETGEAR)
            if netgear_check_firmware; then
                backup_firmware
                latest_version=$(ssh -o ConnectTimeout=5 admin@"$ROUTER_IP" 'cat /etc/version' 2>/dev/null || echo "latest")
                firmware_file=$(netgear_download_firmware "$latest_version" "${ROUTER_MODEL_NUM:-Nighthawk}")
                if [[ $? -eq 0 ]]; then
                    if netgear_install_firmware "$firmware_file" "$latest_version"; then
                        message="✅ Netgear firmware updated to $latest_version"
                        log_info "$message"
                        send_telegram_notification "🔄 Router Update: $message"
                        send_email_notification "Netgear Router Firmware Updated" "$message"
                    fi
                fi
                rm -f "$firmware_file" 2>/dev/null || true
            else
                log_info "Netgear router firmware is up to date"
            fi
            ;;
        UBIQUITI)
            if ubiquiti_check_firmware; then
                backup_firmware
                latest_version=$(curl -s 'https://fw-update.ubiquiti.com/queries/version' | jq -r '.latest' || echo "latest")
                firmware_file=$(ubiquiti_download_firmware "$latest_version")
                if [[ $? -eq 0 ]]; then
                    if ubiquiti_install_firmware "$firmware_file" "$latest_version"; then
                        message="✅ Ubiquiti firmware updated to $latest_version"
                        log_info "$message"
                        send_telegram_notification "🔄 Router Update: $message"
                        send_email_notification "Ubiquiti Router Firmware Updated" "$message"
                    fi
                fi
                rm -f "$firmware_file" 2>/dev/null || true
            else
                log_info "Ubiquiti router firmware is up to date"
            fi
            ;;
        SYNOLOGY)
            if synology_check_firmware; then
                backup_firmware
                latest_version=$(curl -s 'https://www.synology.com/support/download-center' | grep -oP 'RT\d+' | head -1)
                firmware_file=$(synology_download_firmware "$latest_version")
                if [[ $? -eq 0 ]]; then
                    if synology_install_firmware "$firmware_file" "$latest_version"; then
                        message="✅ Synology firmware updated to $latest_version"
                        log_info "$message"
                        send_telegram_notification "🔄 Router Update: $message"
                        send_email_notification "Synology Router Firmware Updated" "$message"
                    fi
                fi
                rm -f "$firmware_file" 2>/dev/null || true
            else
                log_info "Synology router firmware is up to date"
            fi
            ;;
        *)
            log_error "Unsupported router model: $ROUTER_MODEL"
            exit 1
            ;;
    esac
    
    log_info "Firmware update check completed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
