#!/bin/bash

# ============================================================
# Device Monitor - Track connected devices & MAC filtering
# Detects: New devices, MAC spoofing, bandwidth anomalies
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/device-monitor.log"
DEVICE_LIST="/var/lib/device-monitor/devices.db"
MAC_VENDOR_DB="/etc/device-monitor/mac-vendors.txt"
CONFIG_FILE="${SCRIPT_DIR}/../configs/router.conf"
HOME_NETWORK="${HOME_NETWORK:-192.168.1.0/24}"
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$DEVICE_LIST")"

# ============================================================
# LOGGING
# ============================================================

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[✓]${NC} $@"
    log "INFO" "$@"
}

log_alert() {
    echo -e "${YELLOW}[!]${NC} $@"
    log "ALERT" "$@"
}

log_error() {
    echo -e "${RED}[✗]${NC} $@" >&2
    log "ERROR" "$@"
}

# ============================================================
# MAC VENDOR LOOKUP
# ============================================================

get_mac_vendor() {
    local mac="$1"
    local vendor="Unknown"
    
    if [[ -f "$MAC_VENDOR_DB" ]]; then
        local mac_prefix=$(echo "$mac" | cut -d':' -f1-3 | tr '[:lower:]' '[:upper:]')
        vendor=$(grep "^${mac_prefix}" "$MAC_VENDOR_DB" | cut -d',' -f2 | head -1 || echo "Unknown")
    fi
    
    # Fallback to online lookup
    if [[ "$vendor" == "Unknown" ]]; then
        vendor=$(curl -s "https://api.macaddress.io/v1?apiKey=demo&search=${mac}" | jq -r '.vendorDetails.companyName' 2>/dev/null || echo "Unknown")
    fi
    
    echo "$vendor"
}

# ============================================================
# DEVICE DETECTION
# ============================================================

discover_devices() {
    log_info "Scanning for connected devices on $HOME_NETWORK..."
    
    # Use arp-scan or nmap
    if command -v arp-scan &>/dev/null; then
        arp-scan -l --localnet 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
    elif command -v nmap &>/dev/null; then
        nmap -sn "$HOME_NETWORK" 2>/dev/null | grep -E 'Nmap scan report for' | awk '{print $NF}' | tr -d '()'
    else
        # Fallback: parse arp cache
        arp -a | grep -E '\(.*\)' | awk '{print $2}' | tr -d '()'
    fi
}

discover_devices_with_mac() {
    log_info "Scanning for devices with MAC addresses..."
    
    if command -v arp-scan &>/dev/null; then
        arp-scan -l --localnet 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $1, $3, $NF}'
    elif command -v nmap &>/dev/null; then
        nmap -sn -O "$HOME_NETWORK" 2>/dev/null | grep -E 'MAC Address:' -B1 | grep 'Nmap\|MAC' | paste - - | awk '{print $NF, $NF}'
    else
        # Fallback: arp cache
        arp -an | grep -E '\[.*\]' | awk '{print $1, $3}' | tr -d '[]'
    fi
}

# ============================================================
# DATABASE MANAGEMENT
# ============================================================

init_database() {
    if [[ ! -f "$DEVICE_LIST" ]]; then
        touch "$DEVICE_LIST"
        log_info "Device database initialized at $DEVICE_LIST"
    fi
}

add_device() {
    local ip="$1"
    local mac="$2"
    local vendor="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check if device exists
    if ! grep -q "^$mac" "$DEVICE_LIST"; then
        echo "$mac|$ip|$vendor|$timestamp|ACTIVE" >> "$DEVICE_LIST"
        log_alert "🆕 NEW DEVICE DETECTED: $ip ($mac) - $vendor"
        send_alert "New Device" "IP: $ip\nMAC: $mac\nVendor: $vendor"
    fi
}

update_device() {
    local mac="$1"
    local ip="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Update device last seen
    sed -i.bak "s|^${mac}.*|${mac}|${ip}||${timestamp}|ACTIVE|" "$DEVICE_LIST"
}

get_device_count() {
    wc -l < "$DEVICE_LIST"
}

list_devices() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}           Connected Devices on $HOME_NETWORK${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    printf "${BLUE}%-20s | %-18s | %-20s | %-19s${NC}\n" "IP Address" "MAC Address" "Vendor" "Last Seen"
    echo -e "${BLUE}───────────────────┼────────────────────┼──────────────────────┼─────────────────────${NC}"
    
    while IFS='|' read -r mac ip vendor timestamp status; do
        printf "%-20s | %-18s | %-20s | %-19s\n" "$ip" "$mac" "$vendor" "$timestamp"
    done < <(sort -t'|' -k2 "$DEVICE_LIST" | uniq)
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Total Devices: $(get_device_count)${NC}"
}

# ============================================================
# MAC FILTERING
# ============================================================

load_whitelist() {
    local whitelist_file="${SCRIPT_DIR}/../configs/whitelist.conf"
    
    if [[ -f "$whitelist_file" ]]; then
        grep -v '^#' "$whitelist_file" | grep -v '^$'
    fi
}

load_blacklist() {
    local blacklist_file="${SCRIPT_DIR}/../configs/blacklist.conf"
    
    if [[ -f "$blacklist_file" ]]; then
        grep -v '^#' "$blacklist_file" | grep -v '^$'
    fi
}

is_mac_whitelisted() {
    local mac="$1"
    local whitelist=$(load_whitelist)
    
    echo "$whitelist" | grep -i "$mac" >/dev/null 2>&1
}

is_mac_blacklisted() {
    local mac="$1"
    local blacklist=$(load_blacklist)
    
    echo "$blacklist" | grep -i "$mac" >/dev/null 2>&1
}

block_mac() {
    local mac="$1"
    
    log_alert "BLOCKING MAC: $mac"
    
    # Use iptables to block MAC
    if command -v iptables &>/dev/null; then
        iptables -I FORWARD -m mac --mac-source "$mac" -j DROP
        iptables -I FORWARD -m mac --mac-destination "$mac" -j DROP
        send_alert "Device Blocked" "MAC address $mac has been blocked"
    fi
}

unblock_mac() {
    local mac="$1"
    
    log_info "Unblocking MAC: $mac"
    
    if command -v iptables &>/dev/null; then
        iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null || true
        iptables -D FORWARD -m mac --mac-destination "$mac" -j DROP 2>/dev/null || true
    fi
}

# ============================================================
# ANOMALY DETECTION
# ============================================================

detect_mac_spoofing() {
    local ip="$1"
    local mac="$2"
    
    # Check if IP has changed MAC address recently
    if grep -q "^.*|$ip|" "$DEVICE_LIST"; then
        local previous_mac=$(grep "^.*|$ip|" "$DEVICE_LIST" | tail -1 | cut -d'|' -f1)
        
        if [[ "$previous_mac" != "$mac" ]]; then
            log_alert "⚠️  POSSIBLE MAC SPOOFING: IP $ip changed from $previous_mac to $mac"
            send_alert "Security Alert" "Possible MAC spoofing detected\nIP: $ip\nOld MAC: $previous_mac\nNew MAC: $mac"
            return 0
        fi
    fi
    
    return 1
}

detect_bandwidth_anomaly() {
    local mac="$1"
    local threshold_kbps="${BANDWIDTH_THRESHOLD:-1000000}"  # 1 Gbps default
    
    # Get interface stats
    if command -v ethtool &>/dev/null; then
        # Implementation would require monitoring interface stats
        # Simplified version shown here
        log_info "Bandwidth monitoring for $mac (threshold: $threshold_kbps kbps)"
    fi
}

# ============================================================
# NOTIFICATIONS
# ============================================================

send_alert() {
    local title="$1"
    local message="$2"
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${TELEGRAM_CHAT_ID:-}"
    
    if [[ -n "$bot_token" ]] && [[ -n "$chat_id" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d chat_id="$chat_id" \
            -d text="🔔 *$title*\n$message" \
            -d parse_mode="Markdown" >/dev/null 2>&1 || true
    fi
}

# ============================================================
# MAIN MONITORING LOOP
# ============================================================

monitor_continuous() {
    local interval="${1:-60}"
    
    log_info "Starting continuous device monitoring (interval: ${interval}s)"
    
    while true; do
        init_database
        
        # Get current devices
        while IFS=' ' read -r ip mac vendor; do
            if [[ -n "$ip" ]] && [[ -n "$mac" ]]; then
                # Get vendor if not already known
                if [[ "$vendor" == "$mac" ]]; then
                    vendor=$(get_mac_vendor "$mac")
                fi
                
                # Check filters
                if is_mac_blacklisted "$mac"; then
                    block_mac "$mac"
                elif is_mac_whitelisted "$mac"; then
                    add_device "$ip" "$mac" "$vendor"
                    update_device "$mac" "$ip"
                fi
                
                # Detect anomalies
                detect_mac_spoofing "$ip" "$mac"
            fi
        done < <(discover_devices_with_mac)
        
        sleep "$interval"
    done
}

# ============================================================
# CLI COMMANDS
# ============================================================

case "${1:-list}" in
    list)
        init_database
        list_devices
        ;;
    scan)
        init_database
        log_info "Running one-time device scan..."
        while IFS=' ' read -r ip mac vendor; do
            if [[ -n "$ip" ]] && [[ -n "$mac" ]]; then
                vendor=$(get_mac_vendor "$mac")
                add_device "$ip" "$mac" "$vendor"
            fi
        done < <(discover_devices_with_mac)
        list_devices
        ;;
    monitor)
        init_database
        monitor_continuous "${2:-60}"
        ;;
    block)
        if [[ -z "$2" ]]; then
            log_error "Usage: $0 block <MAC_ADDRESS>"
            exit 1
        fi
        block_mac "$2"
        ;;
    unblock)
        if [[ -z "$2" ]]; then
            log_error "Usage: $0 unblock <MAC_ADDRESS>"
            exit 1
        fi
        unblock_mac "$2"
        ;;
    stats)
        init_database
        echo "Total devices: $(get_device_count)"
        echo "Whitelisted: $(load_whitelist | wc -l)"
        echo "Blacklisted: $(load_blacklist | wc -l)"
        ;;
    *)
        echo "Usage: $0 {list|scan|monitor|block|unblock|stats} [args]"
        exit 1
        ;;
esac
