#!/bin/bash

# WireGuard Manager - Docker 部署脚本

set -e

echo "=========================================="
echo "WireGuard Manager - Docker 部署"
echo "=========================================="
echo ""

# 检查 Docker 是否安装
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker 未安装"
    echo ""
    echo "请先安装 Docker："
    echo "  curl -fsSL https://get.docker.com | sh"
    echo "  或访问: https://docs.docker.com/engine/install/"
    exit 1
fi

echo "✓ Docker 已安装"

# 检查 Docker Compose 是否安装
if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    echo "❌ Docker Compose 未安装"
    echo ""
    echo "请先安装 Docker Compose："
    echo "  apt-get install docker-compose-plugin"
    echo "  或访问: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✓ Docker Compose 已安装"
echo ""

# 检查是否在项目目录
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ 请在项目根目录运行此脚本"
    exit 1
fi

# 创建配置目录
echo "=== 1. 创建配置目录 ==="
mkdir -p config/wireguard
mkdir -p config/wireguard/clients

echo "✓ 配置目录创建完成"
echo ""

# 获取服务器公网 IP
echo "=== 2. 检测网络配置 ==="
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
echo "检测到服务器 IP: $SERVER_IP"

if [ "$SERVER_IP" = "YOUR_SERVER_IP" ]; then
    echo ""
    echo -n "请输入服务器公网 IP: "
    read SERVER_IP
fi

echo "✓ 服务器 IP: $SERVER_IP"
echo ""

# 询问部署选项
echo "=== 3. 部署选项 ==="
echo "请选择部署方式："
echo "  1) 完整部署 (WireGuard + Web 管理界面)"
echo "  2) 仅部署 WireGuard 服务"
echo "  3) 仅部署 Web 管理界面"
echo ""
echo -n "请选择 [1-3]: "
read DEPLOY_OPTION

case $DEPLOY_OPTION in
    1)
        SERVICES=""
        echo "✓ 将部署完整服务"
        ;;
    2)
        SERVICES="wireguard"
        echo "✓ 将仅部署 WireGuard 服务"
        ;;
    3)
        SERVICES="wireguard-web"
        echo "✓ 将仅部署 Web 管理界面"
        ;;
    *)
        echo "❌ 无效选项"
        exit 1
        ;;
esac
echo ""

# 构建镜像
echo "=== 4. 构建 Docker 镜像 ==="
echo "开始构建镜像..."
echo ""

if [ "$SERVICES" = "wireguard" ] || [ -z "$SERVICES" ]; then
    echo "构建 WireGuard 镜像..."
    docker build -f Dockerfile.wireguard -t wireguard-manager:latest .
    echo "✓ WireGuard 镜像构建完成"
    echo ""
fi

if [ "$SERVICES" = "wireguard-web" ] || [ -z "$SERVICES" ]; then
    echo "构建 Web 管理界面镜像..."
    docker build -f Dockerfile.web -t wireguard-web:latest .
    echo "✓ Web 管理界面镜像构建完成"
    echo ""
fi

# 启动服务
echo "=== 5. 启动服务 ==="
if [ -z "$SERVICES" ]; then
    docker-compose up -d
else
    docker-compose up -d $SERVICES
fi

echo "✓ 服务启动完成"
echo ""

# 等待服务启动
echo "等待服务启动..."
sleep 5

# 检查服务状态
echo "=== 6. 检查服务状态 ==="
docker-compose ps
echo ""

# 显示完成信息
echo "=========================================="
echo "✅ WireGuard Manager 部署完成！"
echo "=========================================="
echo ""

if [ "$SERVICES" != "wireguard-web" ]; then
    echo "📋 WireGuard VPN 服务："
    echo "----------------------------------------"
    echo "服务器地址: $SERVER_IP"
    echo "监听端口: 51820/udp"
    echo "配置目录: ./config/wireguard/"
    echo ""
    echo "查看服务状态:"
    echo "  docker-compose exec wireguard wg show"
    echo ""
    echo "查看日志:"
    echo "  docker-compose logs -f wireguard"
    echo "----------------------------------------"
    echo ""
fi

if [ "$SERVICES" != "wireguard" ]; then
    echo "🌐 Web 管理界面："
    echo "----------------------------------------"
    echo "访问地址: http://$SERVER_IP:8080"
    echo ""
    echo "⚠️  安全提示："
    echo "  - 建议通过 SSH 隧道访问"
    echo "  - 或配置防火墙限制访问 IP"
    echo ""
    echo "查看日志:"
    echo "  docker-compose logs -f wireguard-web"
    echo "----------------------------------------"
    echo ""
fi

echo "💡 常用管理命令:"
echo "----------------------------------------"
echo "启动服务:   docker-compose start"
echo "停止服务:   docker-compose stop"
echo "重启服务:   docker-compose restart"
echo "查看日志:   docker-compose logs -f"
echo "查看状态:   docker-compose ps"
echo "进入容器:   docker-compose exec wireguard bash"
echo "删除服务:   docker-compose down"
echo "----------------------------------------"
echo ""

echo "📝 添加客户端："
echo "----------------------------------------"
echo "方式1: 使用 Web 管理界面"
echo "  访问 http://$SERVER_IP:8080"
echo ""
echo "方式2: 使用命令行"
echo "  docker-compose exec wireguard bash /app/scripts/add_wireguard_client.sh"
echo "----------------------------------------"
echo ""

echo "✓ 部署完成！开始使用 WireGuard VPN"
