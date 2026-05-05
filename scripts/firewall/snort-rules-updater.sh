#!/bin/bash

# ============================================================
# Snort IDS/IPS Rules Auto-Updater
# Downloads & integrates latest threat detection rules
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/snort-rules-update.log"
RULES_DIR="/etc/snort/rules"
BACKUP_DIR="/backups/snort-rules"
RULE_SOURCES=(
    "https://www.snort.org/downloads/community-rules/community-rules.tar.gz"
    "https://rules.emergingthreats.net/open/snort/emerging-malware.rules"
    "https://rules.emergingthreats.net/open/snort/emerging-botcc.rules"
    "https://rules.emergingthreats.net/open/snort/emerging-ransomware.rules"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Create directories
mkdir -p "$RULES_DIR" "$BACKUP_DIR"

log_info "Starting Snort rules update..."

# Backup current rules
if [[ -d "$RULES_DIR" ]]; then
    backup_file="${BACKUP_DIR}/snort_rules_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$backup_file" -C "$RULES_DIR" . 2>/dev/null || true
    log_info "Current rules backed up to $backup_file"
fi

# Download new rules
log_info "Downloading latest rule sets..."

for rule_source in "${RULE_SOURCES[@]}"; do
    log_info "Downloading from: $rule_source"
    
    if [[ $rule_source == *.tar.gz ]]; then
        temp_file=$(mktemp)
        if curl -L -o "$temp_file" "$rule_source" 2>/dev/null; then
            tar -xzf "$temp_file" -C "$RULES_DIR" 2>/dev/null || true
            rm -f "$temp_file"
            log_info "Rules extracted successfully"
        else
            log_warn "Failed to download: $rule_source"
        fi
    else
        if curl -L -o "${RULES_DIR}/$(basename $rule_source)" "$rule_source" 2>/dev/null; then
            log_info "Downloaded: $(basename $rule_source)"
        else
            log_warn "Failed to download: $rule_source"
        fi
    fi
done

# Validate rules
log_info "Validating Snort rules..."

if command -v snort &>/dev/null; then
    if snort -c "${RULES_DIR}/snort.conf" -T 2>/dev/null; then
        log_info "✓ Snort rules validation passed"
    else
        log_error "Snort rules validation failed!"
        log_warn "Rolling back to previous rules..."
        # Restore from backup
        latest_backup=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
        if [[ -n "$latest_backup" ]]; then
            rm -rf "${RULES_DIR}"/*
            tar -xzf "$latest_backup" -C "$RULES_DIR" || true
            log_info "Rules restored from backup"
        fi
        exit 1
    fi
else
    log_warn "Snort not found - skipping validation"
fi

# Restart Snort service
log_info "Restarting Snort IDS/IPS service..."

if systemctl is-active --quiet snort; then
    if systemctl restart snort 2>/dev/null; then
        log_info "✓ Snort service restarted successfully"
    else
        log_error "Failed to restart Snort service"
        exit 1
    fi
else
    log_warn "Snort service not running"
fi

# Statistics
rule_count=$(find "$RULES_DIR" -name '*.rules' | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo 0)
log_info "Snort rules update completed. Total rules: $rule_count"

# Send notification
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="🔄 Snort Rules Updated\nTotal Rules: $rule_count\nLast Update: $(date)" >/dev/null 2>&1 || true
fi

log_info "Update process completed successfully"
