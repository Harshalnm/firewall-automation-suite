#!/bin/bash

# ============================================================
# Malicious IP/Domain Blocklist Manager
# Downloads & maintains dynamic threat intelligence feeds
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/blocklist-manager.log"
BLOCKLIST_DIR="/etc/blocklists"
BACKUP_DIR="/backups/blocklists"

# Threat intelligence feeds
declare -A BLOCKLISTS=(
    [malware]="https://rules.emergingthreats.net/blockids/malware-dns.txt"
    [botcc]="https://rules.emergingthreats.net/blockids/botcc-dns.txt"
    [ransomware]="https://ransomwaretracker.abuse.ch/downloads/RW_DOMBL.txt"
    [phishing]="https://phishing.army/download/phishing_army_blocklist_extended.txt"
    [spamhaus]="https://www.spamhaus.org/drop/drop.txt"
    [honeypot]="http://www.projecthoneypot.org/list_of_ips.php?t=h&rss=1"
    [abusech]="https://urlhaus-api.abuse.ch/v1/urls/recent/"
    [malwaredomains]="https://malware-filter.gitlab.io/malware-filter/vomba-domains.txt"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

mkdir -p "$BLOCKLIST_DIR" "$BACKUP_DIR"

log_info "Starting blocklist update..."

# Backup current blocklists
if [[ -d "$BLOCKLIST_DIR" ]]; then
    backup_file="${BACKUP_DIR}/blocklists_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$backup_file" -C "$BLOCKLIST_DIR" . 2>/dev/null || true
    log_info "Blocklists backed up"
fi

# Initialize combined blocklists
> "${BLOCKLIST_DIR}/all-malware.txt"
> "${BLOCKLIST_DIR}/all-phishing.txt"
> "${BLOCKLIST_DIR}/all-spam.txt"

total_ips=0
total_domains=0

# Download and process each blocklist
for name in "${!BLOCKLISTS[@]}"; do
    url="${BLOCKLISTS[$name]}"
    output_file="${BLOCKLIST_DIR}/${name}.txt"
    
    log_info "Downloading $name blocklist from $url"
    
    temp_file=$(mktemp)
    
    if curl -L -s --connect-timeout 10 -m 30 -o "$temp_file" "$url" 2>/dev/null; then
        # Parse different formats
        case "$name" in
            malware|botcc|ransomware|phishing|malwaredomains)
                # Format: domain.com or ip.address
                grep -v '^#' "$temp_file" | grep -v '^$' | sed 's/^0.0.0.0 //' | sed 's/^127.0.0.1 //' > "$output_file" || true
                ;;
            spamhaus)
                # Format: CIDR blocks
                grep -v '^;' "$temp_file" | grep -v '^$' > "$output_file" || true
                ;;
            honeypot)
                # RSS/XML format - extract IPs
                grep -oP '(?<=<title>)\d+\.\d+\.\d+\.\d+(?=</title>)' "$temp_file" > "$output_file" || true
                ;;
            abusech)
                # JSON format
                jq -r '.urls[] | select(.status=="online") | .url' "$temp_file" 2>/dev/null > "$output_file" || true
                ;;
        esac
        
        # Count entries
        entry_count=$(wc -l < "$output_file")
        log_info "$name: $entry_count entries"
        
        # Categorize
        if [[ "$name" == *malware* ]] || [[ "$name" == *botcc* ]] || [[ "$name" == *ransomware* ]]; then
            cat "$output_file" >> "${BLOCKLIST_DIR}/all-malware.txt"
            ((total_ips += entry_count))
        fi
        
        if [[ "$name" == *phishing* ]]; then
            cat "$output_file" >> "${BLOCKLIST_DIR}/all-phishing.txt"
            ((total_domains += entry_count))
        fi
        
        if [[ "$name" == *spam* ]] || [[ "$name" == *honeypot* ]]; then
            cat "$output_file" >> "${BLOCKLIST_DIR}/all-spam.txt"
            ((total_ips += entry_count))
        fi
    else
        log_warn "Failed to download $name blocklist"
    fi
    
    rm -f "$temp_file"
done

# Deduplicate and sort combined lists
log_info "Deduplicating and sorting blocklists..."
for list in all-malware all-phishing all-spam; do
    if [[ -f "${BLOCKLIST_DIR}/${list}.txt" ]]; then
        sort -u "${BLOCKLIST_DIR}/${list}.txt" -o "${BLOCKLIST_DIR}/${list}.txt"
    fi
done

# Validate IP format
log_info "Validating IP addresses..."
if [[ -f "${BLOCKLIST_DIR}/all-malware.txt" ]]; then
    grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' "${BLOCKLIST_DIR}/all-malware.txt" > "${BLOCKLIST_DIR}/malware-ips.txt" || true
    grep -vE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' "${BLOCKLIST_DIR}/all-malware.txt" > "${BLOCKLIST_DIR}/malware-domains.txt" || true
fi

# Generate statistics
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}              Blocklist Update Statistics${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

for list_file in "${BLOCKLIST_DIR}"/*.txt; do
    if [[ -f "$list_file" ]]; then
        count=$(wc -l < "$list_file")
        name=$(basename "$list_file")
        printf "${BLUE}%-30s${NC}: %10d entries\n" "$name" "$count"
    fi
done

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Update firewall rules (pfSense/OPNsense)
if command -v pfctl &>/dev/null; then
    log_info "Updating pfSense firewall blocklists..."
    
    # Create pfSense table
    if [[ -f "${BLOCKLIST_DIR}/all-malware.txt" ]]; then
        pfctl -t malware_ips -T replace -f "${BLOCKLIST_DIR}/all-malware.txt" 2>/dev/null || true
        log_info "pfSense malware IP table updated"
    fi
else
    log_warn "pfSense not detected - manual firewall rule update may be needed"
fi

# Update Pi-hole (if running in Docker)
if command -v docker &>/dev/null; then
    if docker ps | grep -q pihole; then
        log_info "Updating Pi-hole blocklists..."
        
        # Copy to Pi-hole volume
        docker cp "${BLOCKLIST_DIR}/all-phishing.txt" pihole:/etc/blocklists/ 2>/dev/null || true
        docker cp "${BLOCKLIST_DIR}/all-malware.txt" pihole:/etc/blocklists/ 2>/dev/null || true
        
        # Force Pi-hole update
        docker exec pihole pihole -g 2>/dev/null || true
        log_info "Pi-hole updated"
    fi
fi

# Send notifications
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    message="📋 Blocklists Updated\nMalware IPs: $(wc -l < ${BLOCKLIST_DIR}/all-malware.txt || echo 0)\nPhishing: $(wc -l < ${BLOCKLIST_DIR}/all-phishing.txt || echo 0)\nSpam: $(wc -l < ${BLOCKLIST_DIR}/all-spam.txt || echo 0)"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="$message" >/dev/null 2>&1 || true
fi

log_info "Blocklist update completed successfully"
