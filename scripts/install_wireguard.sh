#!/bin/bash

# WireGuard 全自动安装配置脚本
# 适用于 Ubuntu/Debian 系统

set -e

echo "=========================================="
echo "WireGuard 全自动安装配置脚本"
echo "=========================================="
echo ""

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本"
    echo "使用: sudo bash $0"
    exit 1
fi

# 配置变量
WG_INTERFACE="wg0"
WG_PORT="51820"
SERVER_WG_IP="10.8.0.1/24"
CLIENT_WG_IP="10.8.0.2/32"
WG_DIR="/etc/wireguard"

# 自动检测外网网卡
echo "=== 检测网络配置 ==="
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
SERVER_PUBLIC_IP=$(ip addr show "$DEFAULT_INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)

if [ -z "$DEFAULT_INTERFACE" ] || [ -z "$SERVER_PUBLIC_IP" ]; then
    echo "❌ 无法自动检测网络配置"
    echo -n "请输入外网网卡名称 (如 eth0): "
    read DEFAULT_INTERFACE
    echo -n "请输入服务器公网IP: "
    read SERVER_PUBLIC_IP
fi

echo "检测到的配置："
echo "  外网网卡: $DEFAULT_INTERFACE"
echo "  服务器IP: $SERVER_PUBLIC_IP"
echo ""

echo -n "配置正确？[Y/n] "
read REPLY
echo ""
if [ "$REPLY" = "n" ] || [ "$REPLY" = "N" ]; then
    echo -n "请输入外网网卡名称 (如 eth0): "
    read DEFAULT_INTERFACE
    echo -n "请输入服务器公网IP: "
    read SERVER_PUBLIC_IP
fi

echo ""
echo "=== 1. 更新系统并安装 WireGuard ==="
apt-get update
apt-get install -y wireguard wireguard-tools

echo "✓ WireGuard 安装完成"
echo ""

echo "=== 2. 启用 IP 转发 ==="
# 启用 IP 转发
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# 永久启用
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p >/dev/null

echo "✓ IP 转发已启用"
echo ""

echo "=== 3. 创建配置目录并生成密钥 ==="
mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

# 生成服务端密钥对
wg genkey | tee "$WG_DIR/server_private.key" | wg pubkey > "$WG_DIR/server_public.key"
chmod 600 "$WG_DIR/server_private.key"

# 生成客户端密钥对
wg genkey | tee "$WG_DIR/client_private.key" | wg pubkey > "$WG_DIR/client_public.key"
chmod 600 "$WG_DIR/client_private.key"

# 读取密钥
SERVER_PRIVATE_KEY=$(cat "$WG_DIR/server_private.key")
SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server_public.key")
CLIENT_PRIVATE_KEY=$(cat "$WG_DIR/client_private.key")
CLIENT_PUBLIC_KEY=$(cat "$WG_DIR/client_public.key")

echo "✓ 密钥生成完成"
echo ""

echo "=== 4. 创建服务端配置文件 ==="
cat > "$WG_DIR/$WG_INTERFACE.conf" <<EOF
[Interface]
# 服务端私钥
PrivateKey = $SERVER_PRIVATE_KEY
# 服务端 VPN 内网地址
Address = $SERVER_WG_IP
# 监听端口
ListenPort = $WG_PORT
# 不保存运行时配置
SaveConfig = false

# 启动时执行的命令
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT
PostUp = iptables -A FORWARD -o $WG_INTERFACE -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostUp = iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT

# 关闭时执行的命令
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT
PostDown = iptables -D FORWARD -o $WG_INTERFACE -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport $WG_PORT -j ACCEPT

# 客户端配置
[Peer]
# 客户端公钥
PublicKey = $CLIENT_PUBLIC_KEY
# 允许的客户端 IP
AllowedIPs = $CLIENT_WG_IP
# 保持连接（可选，用于 NAT 穿透）
# PersistentKeepalive = 25
EOF

chmod 600 "$WG_DIR/$WG_INTERFACE.conf"

echo "✓ 服务端配置文件已创建: $WG_DIR/$WG_INTERFACE.conf"
echo ""

echo "=== 5. 创建客户端配置文件 ==="
cat > "$WG_DIR/client.conf" <<EOF
[Interface]
# 客户端私钥
PrivateKey = $CLIENT_PRIVATE_KEY
# 客户端 VPN 内网地址
Address = ${CLIENT_WG_IP%/*}/24
# DNS 服务器（可选，使用 Google DNS）
DNS = 8.8.8.8, 1.1.1.1

[Peer]
# 服务端公钥
PublicKey = $SERVER_PUBLIC_KEY
# 服务端地址和端口
Endpoint = $SERVER_PUBLIC_IP:$WG_PORT
# 允许的流量（0.0.0.0/0 表示所有流量通过 VPN）
# 如果只想访问内网，可以改为: 10.8.0.0/24
AllowedIPs = 0.0.0.0/0, ::/0
# 保持连接（重要！用于 NAT 穿透）
PersistentKeepalive = 25
EOF

chmod 600 "$WG_DIR/client.conf"

echo "✓ 客户端配置文件已创建: $WG_DIR/client.conf"
echo ""

echo "=== 6. 启动 WireGuard 服务 ==="
# 启动 WireGuard
wg-quick up "$WG_INTERFACE"

# 设置开机自启
systemctl enable "wg-quick@$WG_INTERFACE"

echo "✓ WireGuard 服务已启动并设置开机自启"
echo ""

echo "=== 7. 配置防火墙规则 ==="
# 确保规则已添加（PostUp 应该已经执行）
iptables -C INPUT -p udp --dport "$WG_PORT" -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport "$WG_PORT" -j ACCEPT

echo "✓ 防火墙规则已配置"
echo ""

echo "=== 8. 验证安装 ==="
echo ""
echo "--- WireGuard 服务状态 ---"
systemctl status "wg-quick@$WG_INTERFACE" --no-pager || true
echo ""

echo "--- WireGuard 接口状态 ---"
wg show
echo ""

echo "--- 网络接口 ---"
ip addr show "$WG_INTERFACE"
echo ""

echo "=========================================="
echo "✓ WireGuard 安装配置完成！"
echo "=========================================="
echo ""
echo "📋 配置信息："
echo "----------------------------------------"
echo "服务端信息："
echo "  外网IP: $SERVER_PUBLIC_IP"
echo "  VPN内网IP: $SERVER_WG_IP"
echo "  监听端口: $WG_PORT"
echo "  外网网卡: $DEFAULT_INTERFACE"
echo ""
echo "客户端信息："
echo "  VPN内网IP: $CLIENT_WG_IP"
echo ""
echo "配置文件位置："
echo "  服务端: $WG_DIR/$WG_INTERFACE.conf"
echo "  客户端: $WG_DIR/client.conf"
echo ""
echo "密钥文件位置："
echo "  服务端私钥: $WG_DIR/server_private.key"
echo "  服务端公钥: $WG_DIR/server_public.key"
echo "  客户端私钥: $WG_DIR/client_private.key"
echo "  客户端公钥: $WG_DIR/client_public.key"
echo "----------------------------------------"
echo ""
echo "🔑 服务端公钥:"
echo "$SERVER_PUBLIC_KEY"
echo ""
echo "🔑 客户端公钥:"
echo "$CLIENT_PUBLIC_KEY"
echo ""
echo "=========================================="
echo "📱 客户端配置："
echo "=========================================="
echo ""
echo "请将以下配置复制到客户端设备："
echo ""
cat "$WG_DIR/client.conf"
echo ""
echo "=========================================="
echo ""
echo "💡 使用方法："
echo "----------------------------------------"
echo "1. 将上面的客户端配置保存为 .conf 文件"
echo "2. Windows: 使用 WireGuard 客户端导入配置"
echo "3. Mac/Linux: 使用 wg-quick up client"
echo "4. Android/iOS: 扫描二维码或手动输入配置"
echo ""
echo "生成客户端二维码（需要安装 qrencode）："
echo "  apt-get install -y qrencode"
echo "  qrencode -t ansiutf8 < $WG_DIR/client.conf"
echo ""
echo "管理命令："
echo "  启动: wg-quick up $WG_INTERFACE"
echo "  停止: wg-quick down $WG_INTERFACE"
echo "  状态: wg show"
echo "  查看日志: journalctl -u wg-quick@$WG_INTERFACE -f"
echo "----------------------------------------"
echo ""
echo "🔒 安全提示："
echo "  - 请妥善保管私钥文件"
echo "  - 定期更新系统和 WireGuard"
echo "  - 如需添加更多客户端，请生成新的密钥对"
echo ""
echo "✓ 安装完成！"
