#!/bin/bash
# WireGuard Manager - Docker 部署脚本

set -e

echo "=== WireGuard Docker 部署 ==="
echo ""

# 检查 Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker 未安装"
    echo "安装: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    echo "❌ Docker Compose 未安装"
    exit 1
fi

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ 请在项目根目录运行此脚本"
    exit 1
fi

echo "✓ Docker 环境检查通过"
echo ""

# 创建配置目录
mkdir -p config/wireguard/clients

# 检测服务器 IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "")
if [ -z "$SERVER_IP" ]; then
    echo -n "请输入服务器公网 IP: "
    read SERVER_IP
fi

echo "服务器 IP: $SERVER_IP"
echo ""

# 选择部署方式
echo "部署选项:"
echo "  1) 完整部署 (WireGuard + Web)"
echo "  2) 仅 WireGuard"
echo "  3) 仅 Web"
echo ""
echo -n "选择 [1-3]: "
read OPTION

case $OPTION in
    1) SERVICES="" ;;
    2) SERVICES="wireguard" ;;
    3) SERVICES="wireguard-web" ;;
    *) echo "无效选项"; exit 1 ;;
esac

# 构建镜像
echo ""
echo "构建 Docker 镜像..."
if [ "$SERVICES" = "wireguard" ] || [ -z "$SERVICES" ]; then
    docker build -f Dockerfile.wireguard -t wireguard-manager:latest . >/dev/null
    echo "✓ WireGuard 镜像构建完成"
fi

if [ "$SERVICES" = "wireguard-web" ] || [ -z "$SERVICES" ]; then
    docker build -f Dockerfile.web -t wireguard-web:latest . >/dev/null
    echo "✓ Web 镜像构建完成"
fi

# 启动服务
echo ""
echo "启动服务..."
if [ -z "$SERVICES" ]; then
    docker-compose up -d
else
    docker-compose up -d $SERVICES
fi

sleep 5

echo ""
echo "=========================================="
echo "✅ 部署完成！"
echo "=========================================="

if [ "$SERVICES" != "wireguard-web" ]; then
    echo "WireGuard VPN:"
    echo "  服务器: $SERVER_IP:51820"
    echo "  配置: ./config/wireguard/"
    echo ""
fi

if [ "$SERVICES" != "wireguard" ]; then
    echo "Web 管理界面:"
    echo "  地址: http://$SERVER_IP:8080"
    echo ""
fi

echo "管理命令:"
echo "  查看状态: docker-compose ps"
echo "  查看日志: docker-compose logs -f"
echo "  停止服务: docker-compose stop"
echo "  重启服务: docker-compose restart"
echo "=========================================="
