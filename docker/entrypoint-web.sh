#!/bin/bash
# 简化的 Web 容器启动脚本

set -e

WG_INTERFACE=${WG_INTERFACE:-wg0}
WG_CONF="/etc/wireguard/${WG_INTERFACE}.conf"

echo "=========================================="
echo "WireGuard Web UI Container (Simple)"
echo "=========================================="
echo ""

# 检查是否以 root 运行
if [ "$(id -u)" = "0" ]; then
    echo "Running as root - good for file access"
else
    echo "Running as user $(id -u):$(id -g)"
fi

# 等待配置文件存在
TIMEOUT=30
COUNTER=0

echo "Checking for WireGuard configuration..."
while [ ! -f "$WG_CONF" ] && [ $COUNTER -lt $TIMEOUT ]; do
    echo "Waiting for $WG_CONF... ($COUNTER/$TIMEOUT)"
    sleep 2
    COUNTER=$((COUNTER + 2))
done

if [ ! -f "$WG_CONF" ]; then
    echo "⚠️  WireGuard config not found, creating placeholder..."
    mkdir -p "$(dirname "$WG_CONF")"
    cat > "$WG_CONF" <<EOF
[Interface]
# Placeholder configuration
PrivateKey = placeholder
Address = 10.8.0.1/24
ListenPort = 51820
SaveConfig = false
EOF
    echo "✓ Placeholder config created"
else
    echo "✓ WireGuard configuration found"

    # 显示文件信息用于调试
    echo "Config file info:"
    ls -la "$WG_CONF" || echo "Cannot list file"
    echo "File content preview:"
    head -5 "$WG_CONF" 2>/dev/null || echo "Cannot read file content"
fi

echo ""
echo "Starting Web UI on port 8080..."
echo "=========================================="

# 启动应用
exec "$@"