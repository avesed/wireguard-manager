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

# 检查 Docker Compose 并设置命令
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
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

# 设置配置目录权限
chmod 755 config
chmod 755 config/wireguard
chmod 755 config/wireguard/clients

# 如果运行用户不是 root，设置合适的所有者
if [ "$(id -u)" != "0" ]; then
    # 当前用户拥有配置目录
    echo "✓ 配置目录已创建，权限设置完成"
else
    # root 用户，设置 1000:1000 权限以便容器访问
    chown -R 1000:1000 config/wireguard 2>/dev/null || true
    echo "✓ 配置目录已创建，权限设置完成"
fi

# 启用 IP 转发 (WireGuard 需要)
echo "启用 IP 转发..."
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf >/dev/null 2>&1 || true
    echo "✓ IP 转发已启用"
else
    echo "✓ IP 转发已启用"
fi
echo ""

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
    $DOCKER_COMPOSE up -d
else
    $DOCKER_COMPOSE up -d $SERVICES
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
echo "  查看状态: $DOCKER_COMPOSE ps"
echo "  查看日志: $DOCKER_COMPOSE logs -f"
echo "  停止服务: $DOCKER_COMPOSE stop"
echo "  重启服务: $DOCKER_COMPOSE restart"
echo "=========================================="
