#!/bin/bash

# WireGuard Web 管理界面安装脚本

set -e

echo "=========================================="
echo "WireGuard Web 管理界面安装脚本"
echo "=========================================="
echo ""

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本"
    echo "使用: sudo bash $0"
    exit 1
fi

# 配置变量
WEB_DIR="/opt/wireguard-web"
WEB_PORT="8080"
WEB_USER="www-data"

echo "=== 1. 检查 WireGuard 是否已安装 ==="
if ! command -v wg >/dev/null 2>&1; then
    echo "❌ WireGuard 未安装"
    echo "请先运行: sudo bash install_wireguard.sh"
    exit 1
fi
echo "✓ WireGuard 已安装"
echo ""

echo "=== 2. 安装依赖包 ==="
apt-get update
apt-get install -y python3 python3-pip python3-venv qrencode

echo "✓ 依赖包安装完成"
echo ""

echo "=== 3. 创建应用目录 ==="
mkdir -p "$WEB_DIR"
mkdir -p "$WEB_DIR/templates"
mkdir -p "$WEB_DIR/static"
mkdir -p "$WEB_DIR/static/css"
mkdir -p "$WEB_DIR/static/js"

echo "✓ 目录创建完成"
echo ""

echo "=== 4. 创建 Python 虚拟环境 ==="
cd "$WEB_DIR"
python3 -m venv venv
source venv/bin/activate

echo "✓ 虚拟环境创建完成"
echo ""

echo "=== 5. 安装 Python 依赖 ==="
pip install --upgrade pip
pip install flask qrcode[pil] pillow

echo "✓ Python 依赖安装完成"
echo ""

echo "=== 6. 配置文件将在下一步创建 ==="
echo "请确保将以下文件上传到服务器："
echo "  - $WEB_DIR/app.py"
echo "  - $WEB_DIR/templates/index.html"
echo "  - $WEB_DIR/static/css/style.css"
echo "  - $WEB_DIR/static/js/main.js"
echo ""

echo "=== 7. 配置 sudo 权限 ==="
# 允许 Web 应用执行 WireGuard 命令
if [ ! -f /etc/sudoers.d/wireguard-web ]; then
    cat > /etc/sudoers.d/wireguard-web <<EOF
# WireGuard Web 管理界面权限
$WEB_USER ALL=(ALL) NOPASSWD: /usr/bin/wg
$WEB_USER ALL=(ALL) NOPASSWD: /usr/bin/wg-quick
$WEB_USER ALL=(ALL) NOPASSWD: /bin/cat /etc/wireguard/*
$WEB_USER ALL=(ALL) NOPASSWD: /bin/systemctl status wg-quick@*
$WEB_USER ALL=(ALL) NOPASSWD: /usr/bin/qrencode
EOF
    chmod 440 /etc/sudoers.d/wireguard-web
    echo "✓ sudo 权限配置完成"
else
    echo "✓ sudo 权限已配置"
fi
echo ""

echo "=== 8. 创建 systemd 服务 ==="
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

echo "✓ systemd 服务配置完成"
echo ""

echo "=== 9. 配置防火墙 ==="
if command -v ufw >/dev/null 2>&1; then
    ufw allow $WEB_PORT/tcp
    echo "✓ UFW 防火墙规则已添加"
else
    iptables -A INPUT -p tcp --dport $WEB_PORT -j ACCEPT
    echo "✓ iptables 防火墙规则已添加"
fi
echo ""

echo "=========================================="
echo "✓ 安装准备完成！"
echo "=========================================="
echo ""
echo "📋 下一步操作："
echo "----------------------------------------"
echo "1. 上传应用文件到: $WEB_DIR"
echo "   - app.py"
echo "   - templates/index.html"
echo "   - static/css/style.css"
echo "   - static/js/main.js"
echo ""
echo "2. 设置文件权限:"
echo "   chown -R $WEB_USER:$WEB_USER $WEB_DIR"
echo ""
echo "3. 启动服务:"
echo "   systemctl daemon-reload"
echo "   systemctl start wireguard-web"
echo "   systemctl enable wireguard-web"
echo ""
echo "4. 访问管理界面:"
echo "   http://YOUR_SERVER_IP:$WEB_PORT"
echo "----------------------------------------"
echo ""
echo "💡 管理命令:"
echo "  启动: systemctl start wireguard-web"
echo "  停止: systemctl stop wireguard-web"
echo "  状态: systemctl status wireguard-web"
echo "  日志: journalctl -u wireguard-web -f"
echo ""
