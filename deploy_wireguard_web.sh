#!/bin/bash
# WireGuard Web 管理界面 - 部署脚本

set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 需要 root 权限运行"
    exit 1
fi

# 配置变量
WEB_DIR="/opt/wireguard-web"
WEB_PORT="8080"
WEB_USER="www-data"

echo "=== WireGuard Web 管理界面部署 ==="
echo ""

# 检查 WireGuard
if ! command -v wg >/dev/null 2>&1; then
    echo "❌ WireGuard 未安装"
    exit 1
fi

# 安装依赖
echo "[1/5] 安装依赖..."
apt-get update -qq
apt-get install -y python3 python3-pip python3-venv qrencode >/dev/null 2>&1
echo "✓ 依赖安装完成"

# 创建目录
echo "[2/5] 创建应用目录..."
mkdir -p "$WEB_DIR/templates"
cd "$WEB_DIR"
echo "✓ 目录创建完成"

# 创建虚拟环境
echo "[3/5] 配置 Python 环境..."
python3 -m venv venv
source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet flask qrcode[pil] pillow
echo "✓ Python 环境配置完成"

echo "[4/5] 上传应用文件..."
echo "请将以下文件上传到服务器:"
echo "  - web/app.py -> $WEB_DIR/app.py"
echo "  - web/templates/index.html -> $WEB_DIR/templates/index.html"
echo ""
echo -n "文件已上传？按回车继续..."
read

if [ ! -f "$WEB_DIR/app.py" ] || [ ! -f "$WEB_DIR/templates/index.html" ]; then
    echo "❌ 文件未找到"
    exit 1
fi

# 配置权限
chown -R $WEB_USER:$WEB_USER "$WEB_DIR"
chmod 755 "$WEB_DIR/app.py"

# 配置 sudo 权限
cat > /etc/sudoers.d/wireguard-web <<EOF
$WEB_USER ALL=(ALL) NOPASSWD: /usr/bin/wg
$WEB_USER ALL=(ALL) NOPASSWD: /usr/bin/wg-quick
$WEB_USER ALL=(ALL) NOPASSWD: /bin/cat /etc/wireguard/*
$WEB_USER ALL=(ALL) NOPASSWD: /bin/systemctl status wg-quick@*
$WEB_USER ALL=(ALL) NOPASSWD: /usr/bin/qrencode
$WEB_USER ALL=(ALL) NOPASSWD: /bin/cp /etc/wireguard/*
$WEB_USER ALL=(ALL) NOPASSWD: /bin/rm -f /etc/wireguard/clients/*
$WEB_USER ALL=(ALL) NOPASSWD: /bin/mkdir -p /etc/wireguard/clients
$WEB_USER ALL=(ALL) NOPASSWD: /bin/chmod * /etc/wireguard/clients/*
EOF
chmod 440 /etc/sudoers.d/wireguard-web

echo "✓ 权限配置完成"

# 创建 systemd 服务
echo "[5/5] 配置系统服务..."
cat > /etc/systemd/system/wireguard-web.service <<EOF
[Unit]
Description=WireGuard Web Management Interface
After=network.target wg-quick@wg0.service

[Service]
Type=simple
User=$WEB_USER
Group=$WEB_USER
WorkingDirectory=$WEB_DIR
Environment="PATH=$WEB_DIR/venv/bin"
ExecStart=$WEB_DIR/venv/bin/python $WEB_DIR/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wireguard-web >/dev/null 2>&1
systemctl start wireguard-web

# 配置防火墙
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow $WEB_PORT/tcp >/dev/null 2>&1
fi

sleep 3

if systemctl is-active --quiet wireguard-web; then
    echo "✓ 服务启动成功"
else
    echo "❌ 服务启动失败"
    journalctl -u wireguard-web -n 20
    exit 1
fi

SERVER_IP=$(ip addr show $(ip route | grep default | awk '{print $5}' | head -n1) | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)

echo ""
echo "=========================================="
echo "✅ Web 管理界面部署完成！"
echo "=========================================="
echo "访问地址: http://$SERVER_IP:$WEB_PORT"
echo ""
echo "管理命令:"
echo "  状态: systemctl status wireguard-web"
echo "  日志: journalctl -u wireguard-web -f"
echo "=========================================="
