#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# Nginx 自动反向代理 + HTTPS
# 支持 Debian / Ubuntu
# ==========================================

if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 用户运行此脚本！"
    exit 1
fi

echo "=========================================="
echo "   Nginx 反向代理 + HTTPS 自动配置"
echo "=========================================="

# 获取用户输入
read -rp "请输入反代目标 IP 或地址: " TARGET_IP
read -rp "请输入反代目标端口: " TARGET_PORT
read -rp "请输入绑定域名: " DOMAIN
read -rp "请输入证书申请邮箱: " EMAIL

# 输入检查
if [[ -z "$TARGET_IP" || -z "$DOMAIN" || -z "$EMAIL" ]]; then
    echo "错误：输入不能为空！"
    exit 1
fi

if [[ ! "$TARGET_PORT" =~ ^[0-9]+$ ]] ||
   (( TARGET_PORT < 1 || TARGET_PORT > 65535 )); then
    echo "错误：端口必须为 1-65535！"
    exit 1
fi

if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "错误：域名格式不正确！"
    exit 1
fi

# 检查系统
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y nginx certbot python3-certbot-nginx curl
else
    echo "当前脚本仅支持 Debian / Ubuntu 系统。"
    exit 1
fi

# 启动 Nginx
systemctl enable nginx
systemctl start nginx

# WebSocket 配置
cat > /etc/nginx/conf.d/00-websocket-map.conf <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

# 创建反代配置
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${DOMAIN};

    location / {
        proxy_pass http://${TARGET_IP}:${TARGET_PORT};

        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_connect_timeout 60s;
        proxy_send_timeout 3600s;
        proxy_read_timeout 3600s;
    }
}
EOF

# 启用站点
mkdir -p /etc/nginx/sites-enabled
ln -sfn "$NGINX_CONF" "/etc/nginx/sites-enabled/${DOMAIN}"

# 检查配置
nginx -t

# 重载 Nginx
systemctl reload nginx

echo "=========================================="
echo "正在申请 HTTPS 证书..."
echo "=========================================="

# 自动申请证书并配置 HTTPS
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --redirect \
    --email "$EMAIL" \
    -d "$DOMAIN"

# 设置自动续期
systemctl enable certbot.timer 2>/dev/null || true
systemctl start certbot.timer 2>/dev/null || true

# 最终检查
nginx -t
systemctl reload nginx

echo ""
echo "=========================================="
echo "       配置完成！"
echo "=========================================="
echo "反代目标: http://${TARGET_IP}:${TARGET_PORT}"
echo "绑定域名: ${DOMAIN}"
echo "HTTPS地址: https://${DOMAIN}"
echo ""
echo "证书自动续期已配置。"
echo "=========================================="
