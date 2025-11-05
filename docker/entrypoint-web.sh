#!/bin/bash

# WireGuard Web UI 启动脚本

set -e

WG_INTERFACE=${WG_INTERFACE:-wg0}
WG_CONF="/etc/wireguard/${WG_INTERFACE}.conf"

echo "=========================================="
echo "WireGuard Web UI Container"
echo "=========================================="
echo ""

echo "Waiting for WireGuard configuration..."

# 等待配置文件创建，最多等待60秒
TIMEOUT=60
COUNTER=0

while [ ! -f "$WG_CONF" ] && [ $COUNTER -lt $TIMEOUT ]; do
    echo "Waiting for $WG_CONF... ($COUNTER/$TIMEOUT)"
    sleep 2
    COUNTER=$((COUNTER + 2))
done

if [ ! -f "$WG_CONF" ]; then
    echo "❌ Timeout waiting for WireGuard configuration"
    echo "Creating placeholder configuration for web UI to start..."

    # 确保目录存在且有写权限
    sudo mkdir -p "$(dirname "$WG_CONF")" || mkdir -p "$(dirname "$WG_CONF")" 2>/dev/null || true

    # 创建一个基本的配置文件以允许 Web UI 启动
    if command -v sudo >/dev/null 2>&1; then
        sudo tee "$WG_CONF" > /dev/null <<EOF
[Interface]
# Placeholder configuration - will be replaced by WireGuard container
PrivateKey = placeholder
Address = 10.8.0.1/24
ListenPort = 51820
SaveConfig = false
EOF
        sudo chown root:1000 "$WG_CONF" 2>/dev/null || true
        sudo chmod 640 "$WG_CONF" 2>/dev/null || true
    else
        cat > "$WG_CONF" <<EOF
[Interface]
# Placeholder configuration - will be replaced by WireGuard container
PrivateKey = placeholder
Address = 10.8.0.1/24
ListenPort = 51820
SaveConfig = false
EOF
    fi

    echo "⚠️  Web UI starting with placeholder config"
else
    echo "✓ WireGuard configuration found"
fi

echo ""
echo "Starting Web UI..."
echo "=========================================="

# 执行传入的命令
exec "$@"