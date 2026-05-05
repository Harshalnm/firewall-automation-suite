# Firewall Automation Suite - Home Cybersecurity Bot

## Overview

A comprehensive, modular home cybersecurity system featuring automated router security, firewall/IDS/IPS deployment, DNS filtering, device protection, privacy automation, and real-time alerting.

### 🎯 Core Features

- **Router Security**: Automated firmware updates, WPA3/WPA2 enforcement, risky feature disabling, MAC filtering
- **Firewall & IDS/IPS**: pfSense/OPNsense + Snort/Suricata integration with dynamic blocklists
- **DNS & Tracker Blocking**: Pi-hole/AdGuard Home with 10+ threat intelligence feeds
- **Device Protection**: Automated OS/app updates, malware scanning (ClamAV, Windows Defender)
- **Privacy Automation**: Per-app firewall rules, location services control, tracker blocking
- **Alerting & Reporting**: Real-time Telegram/Email alerts + daily security reports

## 📚 Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: ROUTER SECURITY                                │
│ (Firmware Updates, WPA3/WPA2, Device Monitoring)        │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│ Layer 2: FIREWALL & IDS/IPS                             │
│ (pfSense/OPNsense + Snort/Suricata)                     │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│ Layer 3: DNS & TRACKER BLOCKING                         │
│ (Pi-hole/AdGuard Home + Blocklists)                     │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│ Layer 4: VPN ENCRYPTION                                 │
│ (WireGuard/OpenVPN)                                     │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│ Layer 5: ENDPOINT PROTECTION                            │
│ (OS Updates, Malware Scanning, MFA)                     │
└──────────────────┬──────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────┐
│ Layer 6: ALERTING & REPORTING                           │
│ (Telegram, Email, Daily Reports)                        │
└─────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- Linux server (Ubuntu 20.04+, Debian 10+, or CentOS 8+)
- Docker & Docker Compose (optional)
- Python 3.8+
- Root/sudo access

### Installation

1. **Clone repository:**
   ```bash
   git clone https://github.com/Harshalnm/firewall-automation-suite.git
   cd firewall-automation-suite
   ```

2. **Run setup script:**
   ```bash
   sudo bash scripts/install.sh
   ```

3. **Configure components:**
   ```bash
   # Copy config templates
   cp configs/router.conf.example configs/router.conf
   cp configs/dnsmasq.conf.example configs/dnsmasq.conf
   cp configs/snort/snort.conf.example configs/snort/snort.conf
   
   # Edit with your network settings
   nano configs/router.conf
   ```

4. **Deploy with Docker:**
   ```bash
   docker-compose up -d
   ```

## 📁 Directory Structure

```
firewall-automation-suite/
├── README.md                          # This file
├── ARCHITECTURE.md                    # Detailed system design
├── docker-compose.yml                 # Multi-service deployment
├── scripts/
│   ├── install.sh                     # Automated setup
│   ├── router/
│   │   ├── firmware-update.sh         # Auto firmware updates
│   │   ├── device-monitor.sh          # Device tracking & MAC filtering
│   │   └── security-check.sh          # Router security audit
│   ├── firewall/
│   │   ├── snort-rules-updater.sh     # Dynamic rule updates
│   │   └── blocklist-manager.sh       # Malicious IP/domain lists
│   ├── dns/
│   │   └── pihole-setup.sh            # Pi-hole installation
│   ├── device-protection/
│   │   ├── os-updater.sh              # OS/app updates
│   │   ├── malware-scan.sh            # ClamAV scanning
│   │   └── password-enforce.sh        # MFA & password policy
│   ├── privacy/
│   │   ├── android-firewall.sh        # NetGuard per-app rules
│   │   ├── ios-firewall.sh            # Lockdown integration
│   │   └── tracker-blocker.sh         # Global tracker blocking
│   └── alerting/
│       ├── telegram-alerts.py         # Telegram notifications
│       ├── email-alerts.py            # Email alerts
│       └── report-generator.py        # Daily security reports
├── configs/
│   ├── router.conf.example            # Router configuration
│   ├── dnsmasq.conf.example           # Pi-hole DNS config
│   ├── snort/
│   │   ├── snort.conf.example         # Snort IDS config
│   │   └── local.rules                # Custom detection rules
│   ├── wireguard/
│   │   └── wg0.conf.example           # WireGuard VPN config
│   └── openvpn/
│       └── server.conf.example        # OpenVPN config
├── blocklists/
│   ├── malware-ips.txt                # Malware IP addresses
│   ├── phishing-domains.txt           # Phishing domain list
│   └── tracker-domains.txt            # Ad/tracker domains
└── logs/
    ├── snort/                         # IDS/IPS logs
    ├── firewall/                      # Firewall logs
    └── alerts/                        # Alert logs
```

## 🔐 Security Layers Explained

### Layer 1: Router Security
- Firmware auto-update checker
- WPA3/WPA2-AES encryption enforcement
- Disable WPS, UPnP, remote management
- MAC address filtering
- Connected device monitoring

### Layer 2: Firewall & IDS/IPS
- pfSense/OPNsense deployment
- Snort/Suricata threat detection
- Dynamic malicious IP/domain blocklists
- Suspicious traffic logging and alerting

### Layer 3: DNS & Tracker Blocking
- Pi-hole/AdGuard Home DNS sinkhole
- 10+ threat intelligence feeds
- Ad/tracker/malware blocking
- Dashboard with statistics

### Layer 4: VPN Encryption
- WireGuard for performance
- OpenVPN for compatibility
- Kill switch to prevent DNS leaks

### Layer 5: Endpoint Protection
- Automated OS updates (Linux/Windows/macOS)
- App update scheduling
- ClamAV malware scanning
- Windows Defender integration
- MFA enforcement and reminders

### Layer 6: Privacy Automation
- Android: NetGuard per-app firewall rules
- iOS: Lockdown integration
- Location services toggle
- App permission revocation
- Global tracker blocking

## 🚨 Alerting System

### Real-Time Alerts Triggered By:
- New device joining Wi-Fi
- Suspicious traffic patterns detected
- Malware/botnet communication attempt
- Port scanning detected
- SSH brute force attempts
- Firmware/OS updates available

### Alert Channels:
- **Telegram**: Instant mobile notifications
- **Email**: Formatted HTML messages
- **Dashboard**: Web UI with real-time stats

### Daily Reports Include:
- New devices detected
- Blocked malicious requests
- Top threat types
- Vulnerable services
- Recommended actions

## ⚙️ Configuration

All components are configured via simple text files:

1. **Router Config** (`configs/router.conf`)
   ```ini
   [network]
   home_network = 192.168.1.0/24
   router_ip = 192.168.1.1
   router_model = ASUS
   
   [security]
   encryption = WPA3
   wps_enabled = false
   upnp_enabled = false
   remote_mgmt = false
   ```

2. **DNS Config** (`configs/dnsmasq.conf`)
   ```
   address=/ad.doubleclick.net/127.0.0.1
   address=/ads.google.com/127.0.0.1
   addn-hosts=/etc/dnsmasq.d/blocklists/ads.txt
   ```

3. **Alerts Config** (`configs/alerts.conf`)
   ```ini
   [telegram]
   bot_token = YOUR_BOT_TOKEN
   chat_id = YOUR_CHAT_ID
   
   [email]
   smtp_server = smtp.gmail.com
   from_addr = your-email@gmail.com
   to_addr = your-email@gmail.com
   ```

## 📊 Monitoring Dashboard

Access the web dashboard:
- **Pi-hole Dashboard**: http://192.168.1.10/admin
- **pfSense Dashboard**: https://192.168.1.1
- **Custom Dashboard**: http://192.168.1.10:8080

## 🔧 Advanced Usage

### Custom Snort Rules
Add detection rules to `configs/snort/local.rules`:
```
alert tcp $HOME_NET any -> $EXTERNAL_NET 445 \
  (msg:"SMB Ransomware Activity"; sid:10010; rev:1;)
```

### Custom Blocklists
Add domains to `blocklists/custom-domains.txt`:
```
ad.doubleclick.net
ads.google.com
analytics.google.com
```

### Scheduled Tasks
Edit crontab for automated tasks:
```bash
0 2 * * * /opt/firewall-suite/scripts/router/firmware-update.sh
*/5 * * * * /opt/firewall-suite/scripts/router/device-monitor.sh
0 */6 * * * /opt/firewall-suite/scripts/alerting/report-generator.py
```

## 🐛 Troubleshooting

### High CPU Usage
- Reduce Snort rule verbosity
- Disable verbose logging
- Scale Docker resources

### Blocked Legitimate Traffic
- Add to whitelist: `configs/whitelist.conf`
- Disable specific Snort rules
- Adjust firewall policies

### Missing Alerts
- Check Telegram/Email credentials
- Verify network connectivity
- Review alert logs: `tail -f logs/alerts/alert.log`

## 📝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add feature'`
4. Push to branch: `git push origin feature/my-feature`
5. Submit pull request

## 📄 License

MIT License - See LICENSE file for details

## 🤝 Support

For issues, questions, or suggestions:
- Open GitHub Issue: https://github.com/Harshalnm/firewall-automation-suite/issues
- Email: security@example.com
- Telegram: @FirewallBot

## 📚 Additional Resources

- [pfSense Documentation](https://docs.netgate.com/pfsense/)
- [Snort User Manual](https://www.snort.org/documents)
- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [WireGuard Quickstart](https://www.wireguard.com/quickstart/)

---

**Made with ❤️ for home network security**
