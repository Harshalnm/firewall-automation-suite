#!/usr/bin/env python3

# ============================================================
# Telegram Alert Service - Real-time threat notifications
# ============================================================

import os
import sys
import json
import logging
import requests
from datetime import datetime
from typing import Dict, List, Optional

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/var/log/telegram-alerts.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuration
TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = os.getenv('TELEGRAM_CHAT_ID', '')
TELEGRAM_API_URL = f'https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}'
ALERT_LEVELS = {'low': '🔵', 'medium': '🟡', 'high': '🔴', 'critical': '🔴'}

class TelegramAlertService:
    """Send security alerts via Telegram"""
    
    def __init__(self, bot_token: str, chat_id: str):
        self.bot_token = bot_token
        self.chat_id = chat_id
        self.api_url = f'https://api.telegram.org/bot{bot_token}'
        
        if not bot_token or not chat_id:
            logger.error('Telegram bot token or chat ID not configured')
            sys.exit(1)
    
    def send_message(self, text: str, parse_mode: str = 'Markdown') -> bool:
        """Send a message to Telegram chat"""
        try:
            payload = {
                'chat_id': self.chat_id,
                'text': text,
                'parse_mode': parse_mode
            }
            
            response = requests.post(
                f'{self.api_url}/sendMessage',
                json=payload,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info('Message sent successfully')
                return True
            else:
                logger.error(f'Failed to send message: {response.text}')
                return False
        
        except requests.exceptions.RequestException as e:
            logger.error(f'Telegram API error: {e}')
            return False
    
    def send_alert(self, title: str, message: str, level: str = 'high',
                   data: Optional[Dict] = None) -> bool:
        """Send formatted security alert"""
        icon = ALERT_LEVELS.get(level.lower(), '❓')
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        alert_text = f"{icon} **{title}**\n"
        alert_text += f"_Level: {level.upper()}_\n"
        alert_text += f"_Time: {timestamp}_\n\n"
        alert_text += f"{message}\n"
        
        if data:
            alert_text += "\n```json\n"
            alert_text += json.dumps(data, indent=2)[:500]  # Limit JSON size
            alert_text += "\n```\n"
        
        return self.send_message(alert_text)
    
    def send_device_alert(self, ip: str, mac: str, vendor: str) -> bool:
        """New device detected alert"""
        message = (
            f"📱 **New Device Detected**\n"
            f"IP: `{ip}`\n"
            f"MAC: `{mac}`\n"
            f"Vendor: {vendor}\n\n"
            f"_Device has been added to network monitoring._"
        )
        return self.send_alert('New Device', message, 'medium')
    
    def send_threat_alert(self, threat_type: str, description: str,
                          ip: str = '', count: int = 1) -> bool:
        """Security threat detected"""
        message = (
            f"🚨 **{threat_type} Detected**\n"
            f"Description: {description}\n"
        )
        
        if ip:
            message += f"IP Address: `{ip}`\n"
        
        if count > 1:
            message += f"Count: {count}\n"
        
        message += f"\n_Immediate investigation recommended._"
        
        return self.send_alert(threat_type, message, 'critical')
    
    def send_firewall_alert(self, event_type: str, src_ip: str,
                           dst_ip: str, port: int) -> bool:
        """Firewall event alert"""
        message = (
            f"🛡️ **Firewall Event: {event_type}**\n"
            f"Source: `{src_ip}`\n"
            f"Destination: `{dst_ip}:{port}`\n"
            f"\n_Check firewall logs for details._"
        )
        return self.send_alert(event_type, message, 'high')
    
    def send_update_alert(self, component: str, version: str) -> bool:
        """Update available alert"""
        message = (
            f"🔄 **Update Available**\n"
            f"Component: {component}\n"
            f"Latest Version: `{version}`\n"
            f"\n_Review and install at your earliest convenience._"
        )
        return self.send_alert('Update Available', message, 'low')
    
    def send_malware_alert(self, threat_name: str, file_path: str,
                          action: str = 'quarantined') -> bool:
        """Malware detection alert"""
        message = (
            f"🦠 **Malware Detected**\n"
            f"Threat: `{threat_name}`\n"
            f"File: `{file_path}`\n"
            f"Action: _{action}_\n"
            f"\n⚠️ _CRITICAL: Manual investigation required._"
        )
        return self.send_alert('Malware Detection', message, 'critical')
    
    def send_status_report(self, uptime: str, threats_blocked: int,
                          devices_connected: int, cpu_usage: float,
                          memory_usage: float) -> bool:
        """System status report"""
        message = (
            f"📊 **Security System Status Report**\n"
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
            f"**System Health**\n"
            f"Uptime: {uptime}\n"
            f"CPU Usage: {cpu_usage:.1f}%\n"
            f"Memory Usage: {memory_usage:.1f}%\n\n"
            f"**Network Activity**\n"
            f"Threats Blocked: {threats_blocked}\n"
            f"Connected Devices: {devices_connected}\n\n"
            f"_All systems operational._"
        )
        return self.send_message(message)

def main():
    """CLI interface for sending alerts"""
    
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        logger.error('Missing Telegram configuration')
        sys.exit(1)
    
    service = TelegramAlertService(TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID)
    
    if len(sys.argv) < 2:
        logger.error('Usage: telegram-alerts.py <alert_type> [args]')
        sys.exit(1)
    
    alert_type = sys.argv[1]
    
    try:
        if alert_type == 'device':
            # telegram-alerts.py device <ip> <mac> <vendor>
            service.send_device_alert(sys.argv[2], sys.argv[3], sys.argv[4])
        
        elif alert_type == 'threat':
            # telegram-alerts.py threat <type> <description> [ip] [count]
            ip = sys.argv[4] if len(sys.argv) > 4 else ''
            count = int(sys.argv[5]) if len(sys.argv) > 5 else 1
            service.send_threat_alert(sys.argv[2], sys.argv[3], ip, count)
        
        elif alert_type == 'firewall':
            # telegram-alerts.py firewall <event> <src_ip> <dst_ip> <port>
            service.send_firewall_alert(sys.argv[2], sys.argv[3],
                                       sys.argv[4], int(sys.argv[5]))
        
        elif alert_type == 'update':
            # telegram-alerts.py update <component> <version>
            service.send_update_alert(sys.argv[2], sys.argv[3])
        
        elif alert_type == 'malware':
            # telegram-alerts.py malware <name> <path> [action]
            action = sys.argv[4] if len(sys.argv) > 4 else 'quarantined'
            service.send_malware_alert(sys.argv[2], sys.argv[3], action)
        
        elif alert_type == 'status':
            # telegram-alerts.py status <uptime> <threats> <devices> <cpu> <mem>
            service.send_status_report(
                sys.argv[2],
                int(sys.argv[3]),
                int(sys.argv[4]),
                float(sys.argv[5]),
                float(sys.argv[6])
            )
        
        else:
            logger.error(f'Unknown alert type: {alert_type}')
            sys.exit(1)
    
    except (IndexError, ValueError) as e:
        logger.error(f'Invalid arguments: {e}')
        sys.exit(1)

if __name__ == '__main__':
    main()
