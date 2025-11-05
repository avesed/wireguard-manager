#!/bin/bash
# WireGuard 添加客户端脚本

set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 需要 root 权限运行"
    exit 1
fi

# 配置变量
WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/$WG_INTERFACE.conf"
CLIENT_DIR="$WG_DIR/clients"

# 检查 WireGuard 是否已安装
if ! command -v wg >/dev/null 2>&1; then
    echo "❌ WireGuard 未安装"
    exit 1
fi

if [ ! -f "$WG_CONF" ]; then
    echo "❌ 配置文件不存在: $WG_CONF"
    exit 1
fi

# 检查并启动 WireGuard
if ! wg show "$WG_INTERFACE" >/dev/null 2>&1; then
    echo "⚠️  WireGuard 未运行，正在启动..."
    wg-quick up "$WG_INTERFACE"
fi

echo "=== 添加 WireGuard 客户端 ==="
echo ""

# 获取服务器信息
SERVER_PUBLIC_KEY=$(grep "^PrivateKey" "$WG_CONF" | awk '{print $3}' | wg pubkey)
SERVER_PORT=$(grep "^ListenPort" "$WG_CONF" | awk '{print $3}')
SERVER_VPN_SUBNET=$(grep "^Address" "$WG_CONF" | awk '{print $3}' | cut -d'/' -f1 | cut -d'.' -f1-3)
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
SERVER_PUBLIC_IP=$(ip addr show "$DEFAULT_INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)

# 查找可用 IP
USED_IPS=$(grep "AllowedIPs" "$WG_CONF" | awk '{print $3}' | cut -d'/' -f1 | cut -d'.' -f4 | sort -n)
NEXT_IP=2
for ip_last in $USED_IPS; do
    [ "$ip_last" -ge "$NEXT_IP" ] && NEXT_IP=$((ip_last + 1))
done
CLIENT_IP="$SERVER_VPN_SUBNET.$NEXT_IP"

echo "服务器: $SERVER_PUBLIC_IP:$SERVER_PORT"
echo "可用 IP: $CLIENT_IP"
echo ""

# 输入客户端名称
echo -n "客户端名称: "
read CLIENT_NAME

if [ -z "$CLIENT_NAME" ]; then
    CLIENT_NAME="client$NEXT_IP"
fi

CLIENT_NAME=$(echo "$CLIENT_NAME" | tr -cd '[:alnum:]_-')

echo ""
echo "创建客户端: $CLIENT_NAME ($CLIENT_IP)"
echo ""

# 创建客户端目录
mkdir -p "$CLIENT_DIR"

# 生成密钥
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

echo "$CLIENT_PRIVATE_KEY" > "$CLIENT_DIR/${CLIENT_NAME}_private.key"
echo "$CLIENT_PUBLIC_KEY" > "$CLIENT_DIR/${CLIENT_NAME}_public.key"
chmod 600 "$CLIENT_DIR/${CLIENT_NAME}_private.key"

# 更新服务端配置
cp "$WG_CONF" "${WG_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

cat >> "$WG_CONF" <<EOF

# 客户端: $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP/32
EOF

# 创建客户端配置文件
cat > "$CLIENT_DIR/${CLIENT_NAME}.conf" <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_DIR/${CLIENT_NAME}.conf"

# 重新加载配置
wg syncconf "$WG_INTERFACE" <(wg-quick strip "$WG_INTERFACE")

echo "=========================================="
echo "✅ 客户端创建完成！"
echo "=========================================="
echo "名称: $CLIENT_NAME"
echo "IP: $CLIENT_IP"
echo "配置文件: $CLIENT_DIR/${CLIENT_NAME}.conf"
echo ""
echo "客户端配置:"
echo "----------------------------------------"
cat "$CLIENT_DIR/${CLIENT_NAME}.conf"
echo "----------------------------------------"
echo ""

# 生成二维码（如果安装了 qrencode）
if command -v qrencode >/dev/null 2>&1; then
    echo "二维码:"
    qrencode -t ansiutf8 < "$CLIENT_DIR/${CLIENT_NAME}.conf"
    echo ""
else
    echo "💡 安装 qrencode 生成二维码: apt-get install qrencode"
fi

echo "查看状态: wg show"
