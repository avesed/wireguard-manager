#!/bin/bash

# WireGuard 添加客户端脚本
# 适用于 Ubuntu/Debian 系统

set -e

echo "=========================================="
echo "WireGuard 添加客户端脚本"
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
WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/$WG_INTERFACE.conf"

# 检查 WireGuard 是否已安装
if ! command -v wg >/dev/null 2>&1; then
    echo "❌ WireGuard 未安装"
    echo "请先运行安装脚本: sudo bash install_wireguard.sh"
    exit 1
fi

# 检查配置文件是否存在
if [ ! -f "$WG_CONF" ]; then
    echo "❌ WireGuard 配置文件不存在: $WG_CONF"
    echo "请先运行安装脚本: sudo bash install_wireguard.sh"
    exit 1
fi

# 检查 WireGuard 是否运行
if ! wg show "$WG_INTERFACE" >/dev/null 2>&1; then
    echo "⚠️  WireGuard 接口 $WG_INTERFACE 未运行"
    echo -n "是否启动 WireGuard？[Y/n] "
    read REPLY
    echo ""
    if [ "$REPLY" != "n" ] && [ "$REPLY" != "N" ]; then
        wg-quick up "$WG_INTERFACE"
        echo "✓ WireGuard 已启动"
    else
        echo "请手动启动: wg-quick up $WG_INTERFACE"
        exit 1
    fi
fi

echo "=== 1. 获取服务器信息 ==="
# 获取服务器公钥
SERVER_PUBLIC_KEY=$(grep "^PrivateKey" "$WG_CONF" | awk '{print $3}' | wg pubkey)

# 获取服务器监听端口
SERVER_PORT=$(grep "^ListenPort" "$WG_CONF" | awk '{print $3}')

# 获取服务器 VPN 网段
SERVER_VPN_SUBNET=$(grep "^Address" "$WG_CONF" | awk '{print $3}' | cut -d'/' -f1 | cut -d'.' -f1-3)

# 获取服务器公网 IP
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
SERVER_PUBLIC_IP=$(ip addr show "$DEFAULT_INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)

echo "服务器信息:"
echo "  公网IP: $SERVER_PUBLIC_IP"
echo "  监听端口: $SERVER_PORT"
echo "  VPN网段: $SERVER_VPN_SUBNET.0/24"
echo ""

# 获取已使用的 IP 地址
echo "=== 2. 查找可用的客户端 IP ==="
USED_IPS=$(grep "AllowedIPs" "$WG_CONF" | awk '{print $3}' | cut -d'/' -f1 | cut -d'.' -f4 | sort -n)

# 显示已使用的 IP
echo "已使用的客户端 IP:"
for ip_last in $USED_IPS; do
    echo "  $SERVER_VPN_SUBNET.$ip_last"
done
echo ""

# 查找下一个可用 IP（从 .2 开始，服务器是 .1）
NEXT_IP=2
for ip_last in $USED_IPS; do
    if [ "$ip_last" -ge "$NEXT_IP" ]; then
        NEXT_IP=$((ip_last + 1))
    fi
done

CLIENT_IP="$SERVER_VPN_SUBNET.$NEXT_IP"
echo "✓ 下一个可用IP: $CLIENT_IP"
echo ""

# 询问客户端名称
echo "=== 3. 客户端信息 ==="
echo -n "请输入客户端名称（如: laptop, phone, tablet）: "
read CLIENT_NAME

if [ -z "$CLIENT_NAME" ]; then
    CLIENT_NAME="client$NEXT_IP"
    echo "使用默认名称: $CLIENT_NAME"
fi

# 清理客户端名称（移除特殊字符）
CLIENT_NAME=$(echo "$CLIENT_NAME" | tr -cd '[:alnum:]_-')

echo ""
echo "客户端配置:"
echo "  名称: $CLIENT_NAME"
echo "  VPN IP: $CLIENT_IP/32"
echo ""

echo -n "确认添加此客户端？[Y/n] "
read REPLY
echo ""
if [ "$REPLY" = "n" ] || [ "$REPLY" = "N" ]; then
    echo "已取消操作"
    exit 0
fi

# 创建客户端目录
CLIENT_DIR="$WG_DIR/clients"
mkdir -p "$CLIENT_DIR"

# 客户端文件路径
CLIENT_PRIVATE_KEY_FILE="$CLIENT_DIR/${CLIENT_NAME}_private.key"
CLIENT_PUBLIC_KEY_FILE="$CLIENT_DIR/${CLIENT_NAME}_public.key"
CLIENT_CONF_FILE="$CLIENT_DIR/${CLIENT_NAME}.conf"

echo ""
echo "=== 4. 生成客户端密钥 ==="
# 生成客户端密钥对
wg genkey | tee "$CLIENT_PRIVATE_KEY_FILE" | wg pubkey > "$CLIENT_PUBLIC_KEY_FILE"
chmod 600 "$CLIENT_PRIVATE_KEY_FILE"

CLIENT_PRIVATE_KEY=$(cat "$CLIENT_PRIVATE_KEY_FILE")
CLIENT_PUBLIC_KEY=$(cat "$CLIENT_PUBLIC_KEY_FILE")

echo "✓ 密钥生成完成"
echo "  私钥: $CLIENT_DIR/${CLIENT_NAME}_private.key"
echo "  公钥: $CLIENT_DIR/${CLIENT_NAME}_public.key"
echo ""

echo "=== 5. 更新服务端配置 ==="
# 备份原配置
cp "$WG_CONF" "${WG_CONF}.backup.$(date +%Y%m%d_%H%M%S)"

# 添加客户端配置到服务端
cat >> "$WG_CONF" <<EOF

# 客户端: $CLIENT_NAME
[Peer]
# 客户端公钥
PublicKey = $CLIENT_PUBLIC_KEY
# 允许的客户端 IP
AllowedIPs = $CLIENT_IP/32
# 保持连接（可选，用于 NAT 穿透）
# PersistentKeepalive = 25
EOF

echo "✓ 服务端配置已更新"
echo ""

echo "=== 6. 生成客户端配置文件 ==="
cat > "$CLIENT_CONF_FILE" <<EOF
[Interface]
# 客户端私钥
PrivateKey = $CLIENT_PRIVATE_KEY
# 客户端 VPN 内网地址
Address = $CLIENT_IP/24
# DNS 服务器（可选，使用 Google DNS）
DNS = 8.8.8.8, 1.1.1.1

[Peer]
# 服务端公钥
PublicKey = $SERVER_PUBLIC_KEY
# 服务端地址和端口
Endpoint = $SERVER_PUBLIC_IP:$SERVER_PORT
# 允许的流量（0.0.0.0/0 表示所有流量通过 VPN）
# 如果只想访问内网，可以改为: $SERVER_VPN_SUBNET.0/24
AllowedIPs = 0.0.0.0/0, ::/0
# 保持连接（重要！用于 NAT 穿透）
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONF_FILE"

echo "✓ 客户端配置文件已生成: $CLIENT_CONF_FILE"
echo ""

echo "=== 7. 重新加载 WireGuard 配置 ==="
# 重新加载配置（不中断现有连接）
wg syncconf "$WG_INTERFACE" <(wg-quick strip "$WG_INTERFACE")

echo "✓ WireGuard 配置已重新加载"
echo ""

echo "=== 8. 验证配置 ==="
echo "当前 WireGuard 状态:"
wg show "$WG_INTERFACE"
echo ""

echo "=========================================="
echo "✓ 客户端添加完成！"
echo "=========================================="
echo ""
echo "📋 客户端信息:"
echo "----------------------------------------"
echo "名称: $CLIENT_NAME"
echo "VPN IP: $CLIENT_IP"
echo "配置文件: $CLIENT_CONF_FILE"
echo "----------------------------------------"
echo ""
echo "🔑 客户端公钥:"
echo "$CLIENT_PUBLIC_KEY"
echo ""
echo "=========================================="
echo "📱 客户端配置:"
echo "=========================================="
echo ""
cat "$CLIENT_CONF_FILE"
echo ""
echo "=========================================="
echo ""
echo "💡 使用方法："
echo "----------------------------------------"
echo "1. 将上面的配置保存为 ${CLIENT_NAME}.conf"
echo "2. Windows: 使用 WireGuard 客户端导入配置"
echo "3. Mac/Linux: wg-quick up ${CLIENT_NAME}"
echo "4. Android/iOS: 扫描二维码或手动输入配置"
echo ""

# 检查是否安装了 qrencode
if command -v qrencode >/dev/null 2>&1; then
    echo "📲 客户端配置二维码:"
    echo "----------------------------------------"
    qrencode -t ansiutf8 < "$CLIENT_CONF_FILE"
    echo "----------------------------------------"
    echo ""
    echo "保存二维码图片:"
    echo "  qrencode -o $CLIENT_DIR/${CLIENT_NAME}_qr.png < $CLIENT_CONF_FILE"
else
    echo "💡 安装 qrencode 生成二维码（适用于手机）:"
    echo "  apt-get install -y qrencode"
    echo "  qrencode -t ansiutf8 < $CLIENT_CONF_FILE"
fi
echo ""

echo "📝 管理命令:"
echo "----------------------------------------"
echo "查看所有客户端: wg show $WG_INTERFACE"
echo "查看配置文件: cat $WG_CONF"
echo "查看客户端列表: ls -la $CLIENT_DIR/"
echo "重新加载配置: wg syncconf $WG_INTERFACE <(wg-quick strip $WG_INTERFACE)"
echo "----------------------------------------"
echo ""
echo "✓ 完成！客户端可以开始连接了"
