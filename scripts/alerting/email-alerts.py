#!/usr/bin/env python3

# ============================================================
# Email Alert Service - Daily reports and critical alerts
# ============================================================

import os
import sys
import json
import logging
import smtplib
from datetime import datetime
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import List, Dict

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/var/log/email-alerts.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuration
SMTP_SERVER = os.getenv('SMTP_SERVER', 'smtp.gmail.com')
SMTP_PORT = int(os.getenv('SMTP_PORT', '587'))
SMTP_USERNAME = os.getenv('SMTP_USERNAME', '')
SMTP_PASSWORD = os.getenv('SMTP_PASSWORD', '')
FROM_EMAIL = os.getenv('FROM_EMAIL', SMTP_USERNAME)
TO_EMAIL = os.getenv('TO_EMAIL', '')

class EmailAlertService:
    """Send security alerts via Email"""
    
    def __init__(self, smtp_server: str, smtp_port: int, username: str,
                 password: str, from_email: str, to_email: str):
        self.smtp_server = smtp_server
        self.smtp_port = smtp_port
        self.username = username
        self.password = password
        self.from_email = from_email
        self.to_email = to_email
        
        if not all([smtp_server, username, password, from_email, to_email]):
            logger.error('Missing email configuration')
            sys.exit(1)
    
    def send_email(self, subject: str, html_body: str, text_body: str = '') -> bool:
        """Send email with HTML and plain text"""
        try:
            msg = MIMEMultipart('alternative')
            msg['Subject'] = subject
            msg['From'] = self.from_email
            msg['To'] = self.to_email
            msg['Date'] = datetime.now().strftime('%a, %d %b %Y %H:%M:%S %z')
            
            if text_body:
                msg.attach(MIMEText(text_body, 'plain'))
            
            msg.attach(MIMEText(html_body, 'html'))
            
            with smtplib.SMTP(self.smtp_server, self.smtp_port) as server:
                server.starttls()
                server.login(self.username, self.password)
                server.send_message(msg)
            
            logger.info(f'Email sent: {subject}')
            return True
        
        except Exception as e:
            logger.error(f'Failed to send email: {e}')
            return False
    
    def send_alert(self, title: str, message: str, severity: str = 'high') -> bool:
        """Send formatted security alert"""
        severity_colors = {
            'low': '#0066cc',
            'medium': '#ff9900',
            'high': '#ff3333',
            'critical': '#cc0000'
        }
        color = severity_colors.get(severity.lower(), '#666666')
        
        html_body = f"""
        <html>
            <head>
                <style>
                    body {{ font-family: Arial, sans-serif; }}
                    .alert {{ background-color: {color}; color: white; padding: 20px; border-radius: 5px; }}
                    .title {{ font-size: 24px; font-weight: bold; margin-bottom: 10px; }}
                    .message {{ font-size: 14px; line-height: 1.6; }}
                    .footer {{ margin-top: 20px; font-size: 12px; color: #666; }}
                </style>
            </head>
            <body>
                <div class="alert">
                    <div class="title">{title}</div>
                    <div class="message">{message}</div>
                    <div class="footer">Severity: {severity.upper()}<br>Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</div>
                </div>
            </body>
        </html>
        """
        
        return self.send_email(f'[{severity.upper()}] {title}', html_body, message)
    
    def send_daily_report(self, report_data: Dict) -> bool:
        """Send daily security report"""
        html_body = f"""
        <html>
            <head>
                <style>
                    body {{ font-family: Arial, sans-serif; background-color: #f5f5f5; }}
                    .container {{ max-width: 800px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 5px; }}
                    .header {{ background-color: #003366; color: white; padding: 20px; text-align: center; border-radius: 5px; }}
                    .section {{ margin-top: 20px; padding: 15px; background-color: #f9f9f9; border-left: 4px solid #003366; }}
                    .section-title {{ font-size: 18px; font-weight: bold; margin-bottom: 10px; }}
                    .metric {{ display: flex; justify-content: space-between; padding: 5px 0; }}
                    .value {{ font-weight: bold; }}
                    .threat {{ color: #ff3333; }}
                    .footer {{ margin-top: 20px; font-size: 12px; color: #666; text-align: center; }}
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="header">
                        <h1>Daily Security Report</h1>
                        <p>{datetime.now().strftime('%A, %B %d, %Y')}</p>
                    </div>
                    
                    <div class="section">
                        <div class="section-title">📊 System Status</div>
                        <div class="metric">
                            <span>Uptime:</span>
                            <span class="value">{report_data.get('uptime', 'N/A')}</span>
                        </div>
                        <div class="metric">
                            <span>CPU Usage:</span>
                            <span class="value">{report_data.get('cpu_usage', 'N/A')}%</span>
                        </div>
                        <div class="metric">
                            <span>Memory Usage:</span>
                            <span class="value">{report_data.get('memory_usage', 'N/A')}%</span>
                        </div>
                    </div>
                    
                    <div class="section">
                        <div class="section-title">🛡️ Security Metrics</div>
                        <div class="metric">
                            <span>Threats Blocked:</span>
                            <span class="value threat">{report_data.get('threats_blocked', 0)}</span>
                        </div>
                        <div class="metric">
                            <span>Malware Detected:</span>
                            <span class="value threat">{report_data.get('malware_detected', 0)}</span>
                        </div>
                        <div class="metric">
                            <span>Blocked Domains:</span>
                            <span class="value threat">{report_data.get('blocked_domains', 0)}</span>
                        </div>
                    </div>
                    
                    <div class="section">
                        <div class="section-title">🌐 Network Activity</div>
                        <div class="metric">
                            <span>Connected Devices:</span>
                            <span class="value">{report_data.get('connected_devices', 0)}</span>
                        </div>
                        <div class="metric">
                            <span>New Devices:</span>
                            <span class="value">{report_data.get('new_devices', 0)}</span>
                        </div>
                        <div class="metric">
                            <span>Data Transferred:</span>
                            <span class="value">{report_data.get('data_transferred', 'N/A')}</span>
                        </div>
                    </div>
                    
                    <div class="section">
                        <div class="section-title">⚠️ Top Threats</div>
                        <ul>
        """
        
        if report_data.get('top_threats'):
            for threat in report_data['top_threats']:
                html_body += f"<li>{threat}</li>"
        else:
            html_body += "<li>No significant threats detected</li>"
        
        html_body += f"""
                        </ul>
                    </div>
                    
                    <div class="section">
                        <div class="section-title">✅ Recommendations</div>
                        <ul>
        """
        
        if report_data.get('recommendations'):
            for rec in report_data['recommendations']:
                html_body += f"<li>{rec}</li>"
        else:
            html_body += "<li>System is secure and up to date</li>"
        
        html_body += f"""
                        </ul>
                    </div>
                    
                    <div class="footer">
                        <p>This is an automated security report from your Firewall Automation Suite</p>
                        <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
                    </div>
                </div>
            </body>
        </html>
        """
        
        return self.send_email('Daily Security Report', html_body)
    
    def send_malware_alert(self, threat_name: str, file_path: str,
                          details: str) -> bool:
        """Malware detection alert"""
        message = f"""
        A malware threat has been detected on your system.
        
        Threat Name: {threat_name}
        File Path: {file_path}
        Details: {details}
        
        IMMEDIATE ACTION REQUIRED:
        - The file has been quarantined
        - Manual investigation is recommended
        - Do not open or execute the quarantined file
        - Check the full security report for more details
        """
        
        return self.send_alert('🦠 MALWARE ALERT', message, 'critical')
    
    def send_update_notification(self, updates: List[Dict]) -> bool:
        """Software update notification"""
        html_body = """
        <html>
            <head>
                <style>
                    body {{ font-family: Arial, sans-serif; }}
                    .update {{ background-color: #e8f4f8; padding: 15px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #0066cc; }}
                    .title {{ font-weight: bold; font-size: 16px; }}
                    .details {{ margin-top: 10px; font-size: 14px; }}
                </style>
            </head>
            <body>
                <h2>System & Application Updates Available</h2>
                <p>The following updates are ready to install:</p>
        """
        
        for update in updates:
            html_body += f"""
            <div class="update">
                <div class="title">{update.get('name', 'Unknown')} - {update.get('version', 'N/A')}</div>
                <div class="details">{update.get('description', 'No details available')}</div>
                <div class="details">Type: {update.get('type', 'Unknown')}</div>
            </div>
            """
        
        html_body += """
                <p><strong>Recommendation:</strong> Install critical and security updates as soon as possible.</p>
            </body>
        </html>
        """
        
        return self.send_email('System Updates Available', html_body)

def main():
    """CLI interface for sending alerts"""
    
    if not all([SMTP_USERNAME, SMTP_PASSWORD, FROM_EMAIL, TO_EMAIL]):
        logger.error('Missing email configuration')
        sys.exit(1)
    
    service = EmailAlertService(SMTP_SERVER, SMTP_PORT, SMTP_USERNAME,
                                SMTP_PASSWORD, FROM_EMAIL, TO_EMAIL)
    
    if len(sys.argv) < 2:
        logger.error('Usage: email-alerts.py <alert_type> [args]')
        sys.exit(1)
    
    alert_type = sys.argv[1]
    
    try:
        if alert_type == 'alert':
            # email-alerts.py alert <title> <message> [severity]
            severity = sys.argv[4] if len(sys.argv) > 4 else 'high'
            service.send_alert(sys.argv[2], sys.argv[3], severity)
        
        elif alert_type == 'report':
            # email-alerts.py report <json_file>
            with open(sys.argv[2], 'r') as f:
                report_data = json.load(f)
            service.send_daily_report(report_data)
        
        elif alert_type == 'malware':
            # email-alerts.py malware <name> <path> <details>
            service.send_malware_alert(sys.argv[2], sys.argv[3], sys.argv[4])
        
        else:
            logger.error(f'Unknown alert type: {alert_type}')
            sys.exit(1)
    
    except (IndexError, ValueError, FileNotFoundError) as e:
        logger.error(f'Invalid arguments: {e}')
        sys.exit(1)

if __name__ == '__main__':
    main()
