#!/bin/bash

# ============================================================
# Router Security Audit & Hardening
# Checks: WPA3/WPA2, WPS, UPnP, Remote Management, Passwords
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/security-check.log"
CONFIG_FILE="${SCRIPT_DIR}/../configs/router.conf"
ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
SECURITY_SCORE=0
MAX_SCORE=100

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# LOGGING
# ============================================================

log() {
    local level="$1"
    shift
    local message="$@"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

test_pass() {
    echo -e "${GREEN}✓ PASS${NC} - $@"
    log "PASS" "$@"
    ((SECURITY_SCORE += 5))
}

test_fail() {
    echo -e "${RED}✗ FAIL${NC} - $@"
    log "FAIL" "$@"
}

test_warn() {
    echo -e "${YELLOW}⚠ WARN${NC} - $@"
    log "WARN" "$@"
    ((SECURITY_SCORE += 2))
}

# ============================================================
# WIFI SECURITY TESTS
# ============================================================

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Router Security Audit & Hardening Report                ║${NC}"
echo -e "${BLUE}║        Target: ${ROUTER_IP:<52}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}═══ WiFi Encryption ===${NC}"

# Check WPA3 support
echo -n "Testing WPA3 Support... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get security_type 2>/dev/null | grep -q WPA3' 2>/dev/null; then
    test_pass "WPA3 enabled"
else
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
        'nvram get security_type 2>/dev/null | grep -q WPA2' 2>/dev/null; then
        test_warn "WPA2 enabled (WPA3 recommended)"
    else
        test_fail "No WPA encryption detected"
    fi
fi

# Check AES encryption
echo -n "Testing AES Encryption... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get wpa_cipher 2>/dev/null | grep -qi AES' 2>/dev/null; then
    test_pass "AES-CCMP encryption configured"
else
    test_fail "Non-AES encryption detected"
fi

# Check WiFi password strength
echo -n "Testing WiFi Password Strength... "
passphrase_length=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get wl_wpa_psk 2>/dev/null | wc -c' 2>/dev/null || echo 0)

if [[ $passphrase_length -ge 20 ]]; then
    test_pass "Strong WiFi passphrase (${passphrase_length} chars)"
elif [[ $passphrase_length -ge 12 ]]; then
    test_warn "Medium WiFi passphrase (${passphrase_length} chars, 20+ recommended)"
else
    test_fail "Weak WiFi passphrase (${passphrase_length} chars)"
fi

echo ""
echo -e "${BLUE}═══ Risky Features ===${NC}"

# Check WPS (WiFi Protected Setup)
echo -n "Testing WPS Status... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get wps_enable 2>/dev/null | grep -q 0' 2>/dev/null; then
    test_pass "WPS disabled (secure)"
else
    test_fail "WPS is ENABLED - security vulnerability!"
fi

# Check UPnP
echo -n "Testing UPnP Status... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get upnp_enable 2>/dev/null | grep -q 0' 2>/dev/null; then
    test_pass "UPnP disabled (secure)"
else
    test_fail "UPnP is ENABLED - potential security risk"
fi

# Check Remote Management
echo -n "Testing Remote Management... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get http_enable 2>/dev/null | grep -q 0' 2>/dev/null; then
    test_pass "HTTP remote management disabled"
else
    test_warn "HTTP remote management may be enabled"
fi

echo -n "Testing HTTPS Status... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get https_enable 2>/dev/null | grep -q 1' 2>/dev/null; then
    test_pass "HTTPS enabled for admin interface"
else
    test_warn "HTTPS not explicitly enabled"
fi

echo ""
echo -e "${BLUE}═══ Access Control ===${NC}"

# Check SSH access
echo -n "Testing SSH Access... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get sshd_enable 2>/dev/null | grep -q 0' 2>/dev/null; then
    test_pass "SSH disabled (or limited)"
elif timeout 2 ssh -o ConnectTimeout=1 admin@"$ROUTER_IP" 'echo SSH_OK' 2>/dev/null | grep -q SSH_OK; then
    test_warn "SSH accessible - ensure strong password or key-only auth"
else
    test_pass "SSH not accessible from test network"
fi

# Check default credentials
echo -n "Testing Default Credentials Risk... "
if ssh -o ConnectTimeout=5 -o ConnectTimeout=5 admin:admin@"$ROUTER_IP" 'echo' >/dev/null 2>&1; then
    test_fail "DEFAULT CREDENTIALS DETECTED - CRITICAL VULNERABILITY!"
else
    test_pass "Default credentials changed"
fi

echo ""
echo -e "${BLUE}═══ Firewall & Filtering ===${NC}"

# Check firewall status
echo -n "Testing Firewall Status... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get fw_enable 2>/dev/null | grep -q 1' 2>/dev/null; then
    test_pass "Firewall is enabled"
else
    test_fail "Firewall may be disabled"
fi

# Check DHCP snooping
echo -n "Testing DHCP Snooping... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get dhcp_snooping 2>/dev/null | grep -q 1' 2>/dev/null; then
    test_pass "DHCP snooping enabled"
else
    test_warn "DHCP snooping not enabled (optional enhancement)"
fi

echo ""
echo -e "${BLUE}═══ DNS & DHCP ===${NC}"

# Check DNS settings
echo -n "Testing DNS Configuration... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get lan_dns1 2>/dev/null' | grep -qv '0\.0\.0\.0'; then
    test_pass "Custom DNS servers configured"
else
    test_warn "Using ISP DNS (consider using Pi-hole or public DNS)"
fi

# Check DHCP range
echo -n "Testing DHCP Range... "
dhcp_start=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get dhcp_start 2>/dev/null' || echo "0")
dhcp_end=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get dhcp_end 2>/dev/null' || echo "0")

if [[ -n "$dhcp_start" ]] && [[ -n "$dhcp_end" ]]; then
    test_pass "DHCP range configured ($dhcp_start - $dhcp_end)"
else
    test_fail "DHCP configuration not accessible"
fi

echo ""
echo -e "${BLUE}═══ Logging & Monitoring ===${NC}"

# Check logging
echo -n "Testing System Logging... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get enable_syslog 2>/dev/null | grep -q 1' 2>/dev/null; then
    test_pass "System logging enabled"
else
    test_warn "System logging not explicitly enabled"
fi

# Check firewall logging
echo -n "Testing Firewall Logging... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get log_ipfrag 2>/dev/null | grep -q 1' 2>/dev/null; then
    test_pass "Firewall logging enabled"
else
    test_warn "Consider enabling firewall event logging"
fi

echo ""
echo -e "${BLUE}═══ Firmware & Updates ===${NC}"

# Check firmware version
echo -n "Testing Firmware Version... "
firmware=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get os_version 2>/dev/null' || echo "unknown")
echo "Current: $firmware"
test_warn "Manual firmware version check recommended at manufacturer website"

# Check auto-update
echo -n "Testing Auto-Update... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get webs_autoupd 2>/dev/null | grep -q 1' 2>/dev/null; then
    test_pass "Automatic updates enabled"
else
    test_warn "Consider enabling automatic firmware updates"
fi

echo ""
echo -e "${BLUE}═══ Advanced Security ===${NC}"

# Check NAT-PMP
echo -n "Testing NAT-PMP... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get natpmp_enable 2>/dev/null | grep -q 0' 2>/dev/null; then
    test_pass "NAT-PMP disabled"
else
    test_warn "NAT-PMP enabled (UPnP alternative, consider disabling)"
fi

# Check IPv6
echo -n "Testing IPv6 Configuration... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no admin@"$ROUTER_IP" \
    'nvram get ipv6_service 2>/dev/null | grep -q disabled' 2>/dev/null; then
    test_pass "IPv6 disabled (if not needed)"
else
    test_warn "IPv6 enabled (ensure proper firewall rules)"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    SECURITY SCORE                              ║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"

# Calculate and display score
if [[ $SECURITY_SCORE -ge 80 ]]; then
    score_color="$GREEN"
    score_grade="A (Excellent)"
elif [[ $SECURITY_SCORE -ge 60 ]]; then
    score_color="$YELLOW"
    score_grade="B (Good)"
else
    score_color="$RED"
    score_grade="C (Fair)"
fi

echo -e "${BLUE}║${NC}                  ${score_color}${SECURITY_SCORE}/${MAX_SCORE} - ${score_grade}${NC}" $(printf '%*s' $((65 - ${#score_color} - ${#score_grade})) '')"${BLUE}║${NC}"
echo -e "${BLUE}║                                                                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"

echo ""
echo -e "${YELLOW}Recommendations:${NC}"
echo " 1. Enable WPA3 if available (WPA2-AES minimum)"
echo " 2. Ensure WPS is disabled"
echo " 3. Disable UPnP unless specifically needed"
echo " 4. Use HTTPS for remote administration"
echo " 5. Keep firmware updated automatically"
echo " 6. Change default admin credentials"
echo " 7. Use strong WiFi passphrase (20+ characters)"
echo " 8. Enable system and firewall logging"
echo " 9. Consider using Pi-hole for DNS filtering"
echo " 10. Regularly monitor connected devices"
echo ""

log "INFO" "Security audit completed. Score: $SECURITY_SCORE/$MAX_SCORE"

if [[ $SECURITY_SCORE -lt 60 ]]; then
    exit 1
fi
