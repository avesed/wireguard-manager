#!/bin/bash

# WireGuard Web 管理界面 - 一键部署脚本
# 此脚本会自动安装并配置 Web 管理界面

set -e

echo "=========================================="
echo "WireGuard Web 管理界面 - 一键部署"
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

echo "=== 6. 下载应用文件 ==="
# 这里需要用户手动上传文件或从 GitHub 下载
# 为了演示，我们创建一个提示信息
cat > "$WEB_DIR/README.txt" <<EOF
请将以下文件复制到对应目录：

1. wireguard_web_app.py -> $WEB_DIR/app.py
2. wireguard_web_index.html -> $WEB_DIR/templates/index.html

然后运行部署脚本继续安装。
EOF

echo "⚠️  请手动上传应用文件"
echo "  1. 将 wireguard_web_app.py 重命名为 app.py 并上传到: $WEB_DIR/"
echo "  2. 将 wireguard_web_index.html 重命名为 index.html 并上传到: $WEB_DIR/templates/"
echo ""
echo -n "文件已上传？按回车继续，或按 Ctrl+C 取消..."
read

# 检查文件是否存在
if [ ! -f "$WEB_DIR/app.py" ]; then
    echo "❌ 未找到 app.py 文件"
    exit 1
fi

if [ ! -f "$WEB_DIR/templates/index.html" ]; then
    echo "❌ 未找到 templates/index.html 文件"
    exit 1
fi

echo "✓ 应用文件已就位"
echo ""

echo "=== 7. 配置文件权限 ==="
chown -R $WEB_USER:$WEB_USER "$WEB_DIR"
chmod 755 "$WEB_DIR/app.py"

echo "✓ 文件权限配置完成"
echo ""

echo "=== 8. 配置 sudo 权限 ==="
if [ ! -f /etc/sudoers.d/wireguard-web ]; then
    cat > /etc/sudoers.d/wireguard-web <<EOF
# WireGuard Web 管理界面权限
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
    echo "✓ sudo 权限配置完成"
else
    echo "✓ sudo 权限已配置"
fi
echo ""

echo "=== 9. 创建 systemd 服务 ==="
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

echo "=== 10. 启动服务 ==="
systemctl daemon-reload
systemctl enable wireguard-web
systemctl start wireguard-web

# 等待服务启动
sleep 3

# 检查服务状态
if systemctl is-active --quiet wireguard-web; then
    echo "✓ 服务启动成功"
else
    echo "❌ 服务启动失败"
    echo "查看日志: journalctl -u wireguard-web -n 50"
    exit 1
fi
echo ""

echo "=== 11. 配置防火墙 ==="
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
        ufw allow $WEB_PORT/tcp
        echo "✓ UFW 防火墙规则已添加"
    else
        echo "ℹ️  UFW 未启用，跳过防火墙配置"
    fi
else
    iptables -C INPUT -p tcp --dport $WEB_PORT -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport $WEB_PORT -j ACCEPT
    echo "✓ iptables 防火墙规则已添加"
fi
echo ""

# 获取服务器 IP
SERVER_IP=$(ip addr show $(ip route | grep default | awk '{print $5}' | head -n1) | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)

echo "=========================================="
echo "✅ WireGuard Web 管理界面安装完成！"
echo "=========================================="
echo ""
echo "📋 访问信息："
echo "----------------------------------------"
echo "管理界面: http://$SERVER_IP:$WEB_PORT"
echo "端口: $WEB_PORT"
echo ""
echo "⚠️  安全提示："
echo "  - 当前界面无身份验证，请确保只在可信网络访问"
echo "  - 建议使用反向代理（如 Nginx）添加 HTTPS 和身份验证"
echo "  - 或者使用 SSH 隧道访问: ssh -L 8080:localhost:8080 user@$SERVER_IP"
echo "----------------------------------------"
echo ""
echo "💡 管理命令:"
echo "  查看状态: systemctl status wireguard-web"
echo "  启动服务: systemctl start wireguard-web"
echo "  停止服务: systemctl stop wireguard-web"
echo "  重启服务: systemctl restart wireguard-web"
echo "  查看日志: journalctl -u wireguard-web -f"
echo ""
echo "✓ 安装完成！请在浏览器中访问管理界面"
