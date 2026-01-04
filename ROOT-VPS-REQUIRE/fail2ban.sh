#!/bin/bash
set -e
echo "=== Auto Setup Fail2Ban (Ubuntu) ==="

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan script ini sebagai root"
  exit 1
fi

echo "[1/5] Update system..."
apt update -y

echo "[2/5] Install Fail2Ban..."
apt install fail2ban -y

echo "[3/5] Konfigurasi Fail2Ban..."

if [ -f /etc/fail2ban/jail.local ]; then
  cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak
fi

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 1d
findtime = 5m
maxretry = 5
backend = systemd
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = systemd
EOF

echo "[4/5] Restart & enable Fail2Ban..."
systemctl restart fail2ban
systemctl enable fail2ban

echo "[5/5] Verifikasi status..."
fail2ban-client status

echo ""
echo "======================================"
echo "Fail2Ban berhasil di-setup"
echo "- Bantime   : 1 hari"
echo "- Findtime  : 5 menit"
echo "- Maxretry  : 5 kali"
echo "Proteksi aktif untuk SSH"
echo "======================================"
