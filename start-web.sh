#!/bin/bash
# 仅启动 Web 容器的脚本

set -e

echo "=== 启动 Web 管理界面 ==="
echo ""

# 检查 Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker 未安装"
    exit 1
fi

# 检查配置目录是否存在
if [ ! -d "config/wireguard" ]; then
    echo "❌ WireGuard 配置目录不存在，请先启动 WireGuard 容器"
    exit 1
fi

# 停止现有容器
docker stop wireguard-web-ui 2>/dev/null || true
docker rm wireguard-web-ui 2>/dev/null || true

echo "构建 Web 镜像..."
docker build -f Dockerfile.web -t wireguard-web:latest . >/dev/null

echo "启动 Web 容器 (以 root 身份运行以避免权限问题)..."
docker run -d \
    --name wireguard-web-ui \
    --restart unless-stopped \
    --network host \
    --cap-add NET_ADMIN \
    --user root \
    -e WEB_PORT=8080 \
    -v "$(pwd)/config/wireguard:/etc/wireguard" \
    -v "$(pwd)/config/wireguard/clients:/etc/wireguard/clients" \
    wireguard-web:latest

echo "✅ Web 管理界面已启动"
echo ""
echo "访问地址: http://localhost:8080"
echo "查看日志: docker logs -f wireguard-web-ui"