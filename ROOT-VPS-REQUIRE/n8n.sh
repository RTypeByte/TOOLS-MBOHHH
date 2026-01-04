#!/bin/bash
set -e

echo "======================================"
echo "  AUTO SETUP N8N - DOCKER + HTTPS"
echo "======================================"

read -p "Domain (contoh: n8n.domain.com): " DOMAIN
read -p "Email SSL (Let's Encrypt): " EMAIL
read -p "Username n8n: " N8N_USER
read -s -p "Password n8n: " N8N_PASS
echo
read -s -p "Password Database: " DB_PASS
echo

INSTALL_DIR=/opt/n8n
DATA_DIR=$INSTALL_DIR/data

echo "▶ Update system"
apt update && apt upgrade -y

echo "▶ Install dependencies"
apt install -y \
  ca-certificates curl gnupg lsb-release \
  nginx certbot python3-certbot-nginx \
  ufw

echo "▶ Install Docker"
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | bash
fi

echo "▶ Install Docker Compose"
if ! command -v docker-compose &> /dev/null; then
  curl -L https://github.com/docker/compose/releases/download/v2.25.0/docker-compose-$(uname -s)-$(uname -m) \
  -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

echo "▶ Setup firewall"
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

echo "▶ Prepare directories"
mkdir -p $DATA_DIR
chown -R 1000:1000 $INSTALL_DIR
chmod -R 755 $INSTALL_DIR

cd $INSTALL_DIR

echo "▶ Create docker-compose.yml"
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  postgres:
    image: postgres:16
    container_name: n8n_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: n8n
    volumes:
      - ./data/postgres:/var/lib/postgresql/data

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n_app
    restart: unless-stopped
    user: "1000:1000"
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${DB_PASS}

      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASS}

      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Jakarta

      - N8N_RUNNERS_ENABLED=true
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_SECURE_COOKIE=true

    volumes:
      - ./data/n8n:/home/node/.n8n
    depends_on:
      - postgres
EOF

echo "▶ Start containers"
docker-compose up -d

echo "▶ Configure Nginx"
cat > /etc/nginx/sites-available/n8n <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600;
    }
}
EOF

ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
nginx -t && systemctl reload nginx

echo "▶ Request SSL certificate"
certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos -m ${EMAIL}

echo "▶ Fix permissions (FINAL)"
chown -R 1000:1000 $INSTALL_DIR
chmod -R 700 $DATA_DIR/n8n

docker-compose restart

echo "======================================"
echo "✅ SETUP SELESAI"
echo "🌐 URL      : https://${DOMAIN}"
echo "👤 User     : ${N8N_USER}"
echo "📁 Data     : ${INSTALL_DIR}"
echo "🔒 HTTPS    : ACTIVE"
echo "======================================"
