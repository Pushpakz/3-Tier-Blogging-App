#!/bin/bash

# ============================================
# ScriptNest Blog Platform - EC2 Setup Script
# ============================================

set -e

echo "🛤️ Setting up ScriptNest Blog Platform..."
echo "==========================================="

APP_DIR="/var/www/ScriptNest"
REPO_DIR="$HOME/3-Tier-Blogging-App"

# --- Update system ---
echo "📦 Updating system packages..."
sudo apt update -y
sudo apt upgrade -y

# --- Install Node.js 20 ---
echo "📦 Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

echo "Node version: $(node -v)"
echo "NPM version: $(npm -v)"

# --- Install PostgreSQL ---
echo "📦 Installing PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

sudo systemctl start postgresql
sudo systemctl enable postgresql

# --- Install Nginx ---
echo "📦 Installing Nginx..."
sudo apt install -y nginx
sudo systemctl enable nginx

# --- Install PM2 ---
echo "📦 Installing PM2..."
sudo npm install -g pm2

# --- Configure PostgreSQL ---
echo "🗄️ Configuring PostgreSQL..."

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='scriptnest_user'" | grep -q 1 || \
sudo -u postgres psql -c "CREATE USER scriptnest_user WITH PASSWORD 'ScriptNest_pass_2026';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='scriptnest_db'" | grep -q 1 || \
sudo -u postgres psql -c "CREATE DATABASE scriptnest_db OWNER scriptnest_user;"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE scriptnest_db TO scriptnest_user;"

echo "✅ PostgreSQL configured"

# --- Setup project directory ---
echo "📁 Preparing application directory..."

sudo mkdir -p $APP_DIR
sudo cp -r $REPO_DIR/* $APP_DIR/
sudo chown -R $USER:$USER $APP_DIR

# --- Install backend dependencies ---
echo "📦 Installing backend dependencies..."

cd $APP_DIR/backend
npm install --omit=dev

# --- Create environment file ---
echo "⚙️ Creating environment file..."

cat <<EOF > .env
PORT=5000
DB_HOST=localhost
DB_USER=scriptnest_user
DB_PASSWORD=ScriptNest_pass_2026
DB_NAME=scriptnest_db
DB_PORT=5432
EOF

# --- Build frontend ---
echo "🔨 Building frontend..."

cd $APP_DIR/frontend
npm install
npm run build

# --- Configure Nginx ---
echo "🌐 Configuring Nginx..."

sudo tee /etc/nginx/sites-available/scriptnest <<EOF
server {
    listen 80;
    server_name _;

    root $APP_DIR/frontend/dist;
    index index.html;

    location /api/ {
        proxy_pass http://localhost:5000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
    }

    location / {
        try_files \$uri /index.html;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/scriptnest /etc/nginx/sites-enabled/scriptnest
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t
sudo systemctl restart nginx

# --- Start backend with PM2 ---
echo "🚀 Starting backend..."

cd $APP_DIR/backend

pm2 delete ScriptNest-backend || true
pm2 start src/index.js --name ScriptNest-backend
pm2 save

pm2 startup systemd -u $USER --hp /home/$USER | tail -1 | sudo bash

echo ""
echo "==========================================="
echo "🎉 ScriptNest is now live!"
echo "==========================================="

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo ""
echo "Access your blog at:"
echo "http://$PUBLIC_IP"
echo ""

echo "Useful commands:"
echo "pm2 status"
echo "pm2 logs ScriptNest-backend"
echo "pm2 restart ScriptNest-backend"
echo "sudo systemctl restart nginx"
