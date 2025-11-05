#!/bin/bash
# 仅启动 WireGuard 容器的脚本

set -e

echo "=== 启动 WireGuard 容器 ==="
echo ""

# 检查 Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker 未安装"
    exit 1
fi

# 停止现有容器
docker stop wireguard-vpn 2>/dev/null || true
docker rm wireguard-vpn 2>/dev/null || true

# 创建配置目录
mkdir -p config/wireguard/clients
chmod 755 config/wireguard
chown -R $(id -u):$(id -g) config/wireguard 2>/dev/null || true

# 启用 IP 转发
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null 2>&1 || true

# 清理现有接口
if ip link show wg0 >/dev/null 2>&1; then
    sudo wg-quick down wg0 2>/dev/null || true
fi

echo "构建 WireGuard 镜像..."
docker build -f Dockerfile.wireguard -t wireguard-manager:latest . >/dev/null

echo "启动 WireGuard 容器..."
docker run -d \
    --name wireguard-vpn \
    --restart unless-stopped \
    --network host \
    --privileged \
    --cap-add NET_ADMIN \
    --cap-add SYS_MODULE \
    -e WG_INTERFACE=wg0 \
    -e WG_PORT=51820 \
    -e SERVER_VPN_IP=10.8.0.1/24 \
    -v "$(pwd)/config/wireguard:/etc/wireguard" \
    -v /lib/modules:/lib/modules:ro \
    wireguard-manager:latest

echo "✅ WireGuard 容器已启动"
echo ""
echo "查看日志: docker logs -f wireguard-vpn"
echo "检查状态: docker exec wireguard-vpn wg show"