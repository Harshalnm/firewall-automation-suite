#!/bin/bash

# ============================================================
# Password Policy Enforcer & MFA Reminder
# Enforces strong passwords, MFA setup, and security policies
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/password-enforce.log"
CONFIG_FILE="${SCRIPT_DIR}/../configs/password-policy.conf"

# Password policy settings
MIN_PASSWORD_LENGTH=16
MIN_UPPERCASE=1
MIN_LOWERCASE=1
MIN_DIGITS=1
MIN_SYMBOLS=1
PASSWORD_EXPIRY_DAYS=90
PASSWORD_HISTORY=10
LOCKOUT_THRESHOLD=5
LOCKOUT_DURATION=1800  # 30 minutes

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
# LINUX PASSWORD POLICY
# ============================================================

enforce_linux_password_policy() {
    log_info "Enforcing Linux password policy..."
    
    # Install pam-pwquality for strong password enforcement
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                sudo apt-get install -y libpam-pwquality >/dev/null 2>&1
                ;;
            rhel|fedora|centos)
                sudo yum install -y libpwquality >/dev/null 2>&1
                ;;
        esac
    fi
    
    # Configure PAM password quality requirements
    pam_config="/etc/security/pwquality.conf"
    
    if [[ -f "$pam_config" ]]; then
        log_info "Updating PAM password quality requirements..."
        
        # Backup original
        sudo cp "$pam_config" "${pam_config}.backup"
        
        # Update configuration
        cat << EOF | sudo tee "$pam_config" > /dev/null
# Password quality configuration
minlen = $MIN_PASSWORD_LENGTH
dcredit = -$MIN_DIGITS
ucredit = -$MIN_UPPERCASE
lcredit = -$MIN_LOWERCASE
ocredit = -$MIN_SYMBOLS
maxrepeat = 3
maxsequence = 3
requiredcheck = 1
enforcefor = root
usertype = wheel,sudo
EOF
        
        log_info "PAM password quality configured"
    fi
    
    # Configure password aging
    log_info "Configuring password aging policy..."
    
    cat << EOF | sudo tee /etc/default/useradd > /dev/null
PASSWD_MAX_DAYS=$PASSWORD_EXPIRY_DAYS
PASSWD_MIN_DAYS=0
PASSWD_WARN_AGE=14
EOF
    
    # Apply to existing users
    for user in $(cut -f1 -d: /etc/passwd); do
        if [[ $user != "root" ]] && [[ ! $user =~ ^_ ]]; then
            sudo chage -M "$PASSWORD_EXPIRY_DAYS" -W 14 "$user" 2>/dev/null || true
        fi
    done
    
    log_info "Password aging policy applied"
    
    # Configure account lockout
    log_info "Configuring account lockout policy..."
    
    pam_common_auth="/etc/pam.d/common-auth"
    if [[ -f "$pam_common_auth" ]]; then
        # Check if pam_faillock is configured
        if ! grep -q "pam_faillock" "$pam_common_auth"; then
            # Add pam_faillock rules
            echo "auth required pam_faillock.so preauth silent audit deny=$LOCKOUT_THRESHOLD unlock_time=$LOCKOUT_DURATION" | sudo tee -a "$pam_common_auth"
            echo "auth [default=die] pam_faillock.so authfail audit deny=$LOCKOUT_THRESHOLD unlock_time=$LOCKOUT_DURATION" | sudo tee -a "$pam_common_auth"
        fi
    fi
    
    log_info "Account lockout policy configured"
}

# ============================================================
# WINDOWS PASSWORD POLICY
# ============================================================

enforce_windows_password_policy() {
    if ! command -v powershell &>/dev/null; then
        log_warn "PowerShell not available - skipping Windows policy"
        return 0
    fi
    
    log_info "Enforcing Windows password policy..."
    
    powershell -Command "
    # Configure password policy
    net accounts /maxpwage:$PASSWORD_EXPIRY_DAYS
    net accounts /minpwlen:$MIN_PASSWORD_LENGTH
    net accounts /uniquepw:$PASSWORD_HISTORY
    net accounts /lockoutthreshold:$LOCKOUT_THRESHOLD
    net accounts /lockoutduration:$((LOCKOUT_DURATION / 60))
    
    # Enable password complexity
    secedit /export /cfg C:\\secpol.cfg
    (Get-Content C:\\secpol.cfg).Replace('PasswordComplexity = 0', 'PasswordComplexity = 1') | Set-Content C:\\secpol.cfg
    secedit /import /db C:\\secpol.sdb /cfg C:\\secpol.cfg /areas SECURITYPOLICY
    " 2>/dev/null || log_warn "Failed to apply Windows password policy"
    
    log_info "Windows password policy configured"
}

# ============================================================
# MFA ENFORCEMENT
# ============================================================

check_mfa_status() {
    log_info "Checking MFA status for user accounts..."
    
    mfa_enabled_count=0
    mfa_disabled_count=0
    
    # Check Linux users
    for user in $(cut -f1 -d: /etc/passwd); do
        if [[ $user != "root" ]] && [[ ! $user =~ ^_ ]]; then
            user_home=$(eval echo ~$user)
            
            # Check for 2FA setup
            if [[ -f "$user_home/.google_authenticator" ]] || [[ -f "$user_home/.totp" ]]; then
                ((mfa_enabled_count++))
            else
                ((mfa_disabled_count++))
                log_warn "User $user does NOT have MFA enabled"
                send_mfa_reminder "$user"
            fi
        fi
    done
    
    echo -e "${BLUE}═════════════════════════════════${NC}"
    echo -e "${BLUE}MFA Status Summary${NC}"
    echo -e "${BLUE}═════════════════════════════════${NC}"
    echo -e "MFA Enabled: ${GREEN}$mfa_enabled_count${NC}"
    echo -e "MFA Disabled: ${RED}$mfa_disabled_count${NC}"
    echo -e "${BLUE}═════════════════════════════════${NC}"
    
    log_info "MFA enabled for $mfa_enabled_count users"
    log_warn "MFA disabled for $mfa_disabled_count users"
}

setup_totp_mfa() {
    local username="$1"
    
    log_info "Setting up TOTP MFA for user: $username"
    
    if ! command -v google-authenticator &>/dev/null; then
        log_error "google-authenticator not installed"
        return 1
    fi
    
    # Generate QR code for user
    user_home=$(eval echo ~$username)
    google-authenticator -t -f -d -w 3 -W -q -i "HomeNetwork" -issuer "FirewallSuite" --secret="$user_home/.google_authenticator"
    
    # Set permissions
    chown "$username:$username" "$user_home/.google_authenticator"
    chmod 400 "$user_home/.google_authenticator"
    
    log_info "TOTP MFA setup completed for $username"
}

setup_ssh_keys() {
    local username="$1"
    
    log_info "Setting up SSH key authentication for user: $username"
    
    user_home=$(eval echo ~$username)
    ssh_dir="$user_home/.ssh"
    
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Generate SSH key pair
    if [[ ! -f "$ssh_dir/id_rsa" ]]; then
        ssh-keygen -t rsa -b 4096 -f "$ssh_dir/id_rsa" -N "" -C "$username@firewall-suite" 2>/dev/null || true
        
        cat "$ssh_dir/id_rsa.pub" >> "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
        chown -R "$username:$username" "$ssh_dir"
        
        log_info "SSH keys generated for $username"
    fi
}

# ============================================================
# PASSWORD VALIDATION
# ============================================================

validate_password() {
    local password="$1"
    
    # Check minimum length
    if [[ ${#password} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "Password too short (minimum $MIN_PASSWORD_LENGTH characters)"
        return 1
    fi
    
    # Check for uppercase
    if ! [[ "$password" =~ [A-Z] ]]; then
        log_error "Password must contain at least one uppercase letter"
        return 1
    fi
    
    # Check for lowercase
    if ! [[ "$password" =~ [a-z] ]]; then
        log_error "Password must contain at least one lowercase letter"
        return 1
    fi
    
    # Check for digits
    if ! [[ "$password" =~ [0-9] ]]; then
        log_error "Password must contain at least one digit"
        return 1
    fi
    
    # Check for special characters
    if ! [[ "$password" =~ [!@#$%^&*()_+\-=\[\]{};':",./<>?] ]]; then
        log_error "Password must contain at least one special character"
        return 1
    fi
    
    log_info "Password meets security requirements"
    return 0
}

# ============================================================
# NOTIFICATIONS
# ============================================================

send_mfa_reminder() {
    local username="$1"
    local bot_token="${TELEGRAM_BOT_TOKEN:-}"
    local chat_id="${TELEGRAM_CHAT_ID:-}"
    
    if [[ -n "$bot_token" ]] && [[ -n "$chat_id" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d chat_id="$chat_id" \
            -d text="🔐 *MFA Reminder*\nUser $username has not enabled MFA.\nPlease set up two-factor authentication ASAP." \
            -d parse_mode="Markdown" >/dev/null 2>&1 || true
    fi
}

# ============================================================
# MAIN EXECUTION
# ============================================================

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        Password Policy Enforcer & MFA Reminder${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
echo ""

log_info "Password policy enforcement started"

echo -e "\n${BLUE}Password Policy Settings:${NC}"
echo "  Minimum Length: $MIN_PASSWORD_LENGTH characters"
echo "  Uppercase Required: $MIN_UPPERCASE"
echo "  Lowercase Required: $MIN_LOWERCASE"
echo "  Digits Required: $MIN_DIGITS"
echo "  Special Chars Required: $MIN_SYMBOLS"
echo "  Password Expiry: $PASSWORD_EXPIRY_DAYS days"
echo "  Account Lockout: $LOCKOUT_THRESHOLD attempts / ${LOCKOUT_DURATION}s"

echo -e "\n${BLUE}Enforcing platform-specific policies...${NC}"

# Enforce based on OS
case "$(uname -s)" in
    Linux)
        enforce_linux_password_policy
        ;;
    Darwin)
        log_info "macOS password policy enforcement (manual configuration recommended)"
        ;;
    MINGW*|MSYS*)
        enforce_windows_password_policy
        ;;
exac

# Check MFA status
echo ""
check_mfa_status

# Interactive MFA setup if requested
if [[ "${2:-}" == "setup-mfa" ]]; then
    username="${3:-$(whoami)}"
    setup_totp_mfa "$username"
fi

if [[ "${2:-}" == "setup-ssh" ]]; then
    username="${3:-$(whoami)}"
    setup_ssh_keys "$username"
fi

echo ""
echo -e "${GREEN}✓ Password policy enforcement completed${NC}"
echo ""

log_info "Password policy enforcement completed"
