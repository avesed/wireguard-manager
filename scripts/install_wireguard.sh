#!/bin/bash
# WireGuard 自动安装脚本

set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 需要 root 权限运行"
    exit 1
fi

# 配置变量
WG_INTERFACE="wg0"
WG_PORT="51820"
SERVER_VPN_IP="10.8.0.1/24"
CLIENT_VPN_IP="10.8.0.2/32"
WG_DIR="/etc/wireguard"

echo "=== WireGuard 安装脚本 ==="
echo ""

# 检测网络配置
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
SERVER_PUBLIC_IP=$(ip addr show "$DEFAULT_INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)

if [ -z "$DEFAULT_INTERFACE" ] || [ -z "$SERVER_PUBLIC_IP" ]; then
    echo -n "请输入外网网卡名称: "
    read DEFAULT_INTERFACE
    echo -n "请输入服务器公网IP: "
    read SERVER_PUBLIC_IP
fi

echo "配置: $DEFAULT_INTERFACE - $SERVER_PUBLIC_IP"
echo ""

# 安装 WireGuard
echo "[1/5] 安装 WireGuard..."
apt-get update -qq
apt-get install -y wireguard wireguard-tools qrencode >/dev/null 2>&1
echo "✓ 安装完成"

# 启用 IP 转发
echo "[2/5] 配置 IP 转发..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
echo "✓ IP 转发已启用"

# 生成密钥
echo "[3/5] 生成密钥..."
mkdir -p "$WG_DIR/clients"
chmod 700 "$WG_DIR"

SERVER_PRIVATE_KEY=$(wg genkey)
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

echo "$SERVER_PRIVATE_KEY" > "$WG_DIR/server_private.key"
echo "$SERVER_PUBLIC_KEY" > "$WG_DIR/server_public.key"
echo "$CLIENT_PRIVATE_KEY" > "$WG_DIR/client_private.key"
echo "$CLIENT_PUBLIC_KEY" > "$WG_DIR/client_public.key"
chmod 600 "$WG_DIR"/*.key
echo "✓ 密钥生成完成"

# 创建服务端配置
echo "[4/5] 创建配置文件..."
cat > "$WG_DIR/$WG_INTERFACE.conf" <<EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $SERVER_VPN_IP
ListenPort = $WG_PORT
SaveConfig = false

PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT
PostUp = iptables -A FORWARD -o $WG_INTERFACE -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostUp = iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT

PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT
PostDown = iptables -D FORWARD -o $WG_INTERFACE -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport $WG_PORT -j ACCEPT

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_VPN_IP
EOF

chmod 600 "$WG_DIR/$WG_INTERFACE.conf"

# 创建客户端配置
cat > "$WG_DIR/client.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = ${CLIENT_VPN_IP%/*}/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "$WG_DIR/client.conf"
echo "✓ 配置文件创建完成"

# 启动 WireGuard
echo "[5/5] 启动服务..."
wg-quick up "$WG_INTERFACE"
systemctl enable "wg-quick@$WG_INTERFACE" >/dev/null 2>&1
echo "✓ 服务已启动"

echo ""
echo "=========================================="
echo "✅ 安装完成！"
echo "=========================================="
echo "服务器: $SERVER_PUBLIC_IP:$WG_PORT"
echo "服务端 IP: $SERVER_VPN_IP"
echo "客户端 IP: $CLIENT_VPN_IP"
echo ""
echo "配置文件:"
echo "  服务端: $WG_DIR/$WG_INTERFACE.conf"
echo "  客户端: $WG_DIR/client.conf"
echo ""
echo "客户端配置:"
cat "$WG_DIR/client.conf"
echo ""
echo "管理命令:"
echo "  查看状态: wg show"
echo "  添加客户端: bash scripts/add_wireguard_client.sh"
echo "=========================================="
