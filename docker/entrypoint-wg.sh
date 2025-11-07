#!/bin/bash

# WireGuard 容器启动脚本

set -e

WG_INTERFACE=${WG_INTERFACE:-wg0}
WG_PORT=${WG_PORT:-51820}
SERVER_VPN_IP=${SERVER_VPN_IP:-10.8.0.1/24}
WG_CONF="/etc/wireguard/${WG_INTERFACE}.conf"

echo "=========================================="
echo "WireGuard Docker Container"
echo "=========================================="
echo ""

# 加载内核模块
echo "Loading kernel modules..."
if ! modprobe wireguard 2>/dev/null; then
    echo "⚠️  Warning: Cannot load wireguard module (may already be loaded or built-in)"
fi

# 启用 IP 转发
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null

# 检查配置文件是否存在
if [ ! -f "$WG_CONF" ]; then
    echo "No WireGuard configuration found. Generating initial configuration..."

    # 获取容器外网接口
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -z "$DEFAULT_INTERFACE" ]; then
        DEFAULT_INTERFACE="eth0"
    fi

    # 生成服务端密钥
    SERVER_PRIVATE_KEY=$(wg genkey)
    SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

    # 保存密钥
    echo "$SERVER_PRIVATE_KEY" > /etc/wireguard/server_private.key
    echo "$SERVER_PUBLIC_KEY" > /etc/wireguard/server_public.key
    chmod 600 /etc/wireguard/server_private.key

    # 创建服务端配置
    cat > "$WG_CONF" <<EOF
[Interface]
# 服务端私钥
PrivateKey = $SERVER_PRIVATE_KEY
# 服务端 VPN 内网地址
Address = $SERVER_VPN_IP
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
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT || true
PostDown = iptables -D FORWARD -o $WG_INTERFACE -j ACCEPT || true
PostDown = iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE || true
PostDown = iptables -D INPUT -p udp --dport $WG_PORT -j ACCEPT || true
EOF

    chmod 600 "$WG_CONF"

    # 创建客户端配置目录
    mkdir -p /etc/wireguard/clients

    # 设置正确的权限以供 Web UI 访问
    chown -R root:1000 /etc/wireguard
    chmod -R 640 /etc/wireguard/*.conf
    chmod -R 644 /etc/wireguard/clients
    chmod 750 /etc/wireguard

    echo "✓ Initial configuration generated"
    echo ""
    echo "Server Public Key: $SERVER_PUBLIC_KEY"
    echo ""
fi

# 启动 WireGuard
echo "Starting WireGuard interface: $WG_INTERFACE"

# 检查接口是否已存在
if ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
    echo "⚠️  Interface $WG_INTERFACE already exists, bringing it down first..."
    wg-quick down "$WG_INTERFACE" 2>/dev/null || true
    sleep 2
fi

# 启动接口
if wg-quick up "$WG_INTERFACE"; then
    echo "✓ WireGuard started successfully"
else
    echo "❌ Failed to start WireGuard interface"
    exit 1
fi
echo ""

# 显示状态
echo "WireGuard Status:"
wg show "$WG_INTERFACE"
echo ""

echo "Container is ready!"
echo "=========================================="

# 保持容器运行并监控 WireGuard 状态
while true; do
    if ! wg show "$WG_INTERFACE" >/dev/null 2>&1; then
        echo "⚠️  WireGuard interface down, attempting restart..."

        # 确保接口完全关闭
        wg-quick down "$WG_INTERFACE" 2>/dev/null || true
        sleep 2

        # 重新启动接口
        if wg-quick up "$WG_INTERFACE" 2>/dev/null; then
            echo "✓ WireGuard interface restarted successfully"
        else
            echo "❌ Failed to restart WireGuard interface"
        fi
    fi
    sleep 30
done
