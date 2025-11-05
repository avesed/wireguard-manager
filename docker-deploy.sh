#!/bin/bash
# WireGuard Manager - 直接 Docker 部署脚本

set -e

echo "=== WireGuard 直接 Docker 部署 ==="
echo ""

# 检查 Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker 未安装"
    echo "安装: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

echo "✓ Docker 环境检查通过"
echo ""

# 停止并清理现有容器
echo "清理现有容器..."
docker stop wireguard-vpn wireguard-web-ui 2>/dev/null || true
docker rm wireguard-vpn wireguard-web-ui 2>/dev/null || true
echo "✓ 容器清理完成"
echo ""

# 创建配置目录
echo "创建配置目录..."
mkdir -p config/wireguard/clients

# 设置配置目录权限
chmod 755 config
chmod 755 config/wireguard
chmod 755 config/wireguard/clients

# 获取当前用户的 UID 和 GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

echo "当前用户: UID=$CURRENT_UID, GID=$CURRENT_GID"

# 设置配置目录所有者为当前用户
chown -R $CURRENT_UID:$CURRENT_GID config/wireguard 2>/dev/null || true
echo "✓ 配置目录权限设置完成"
echo ""

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
    1) SERVICES="all" ;;
    2) SERVICES="wireguard" ;;
    3) SERVICES="web" ;;
    *) echo "无效选项"; exit 1 ;;
esac

# 构建镜像
echo ""
echo "构建 Docker 镜像..."
if [ "$SERVICES" = "wireguard" ] || [ "$SERVICES" = "all" ]; then
    docker build -f Dockerfile.wireguard -t wireguard-manager:latest . >/dev/null
    echo "✓ WireGuard 镜像构建完成"
fi

if [ "$SERVICES" = "web" ] || [ "$SERVICES" = "all" ]; then
    docker build -f Dockerfile.web -t wireguard-web:latest . >/dev/null
    echo "✓ Web 镜像构建完成"
fi

# 启动 WireGuard 容器
if [ "$SERVICES" = "wireguard" ] || [ "$SERVICES" = "all" ]; then
    echo ""
    echo "启动 WireGuard 容器..."

    # 清理现有的 WireGuard 接口
    if ip link show wg0 >/dev/null 2>&1; then
        echo "清理现有 WireGuard 接口..."
        sudo wg-quick down wg0 2>/dev/null || true
        sleep 2
    fi

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
        -e TZ=Asia/Shanghai \
        -v "$(pwd)/config/wireguard:/etc/wireguard" \
        -v /lib/modules:/lib/modules:ro \
        wireguard-manager:latest

    echo "✓ WireGuard 容器已启动"

    # 等待 WireGuard 容器初始化
    echo "等待 WireGuard 初始化..."
    sleep 10

    # 检查 WireGuard 状态
    RETRY_COUNT=0
    MAX_RETRIES=12
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if docker exec wireguard-vpn wg show wg0 >/dev/null 2>&1; then
            echo "✓ WireGuard 初始化完成"
            break
        fi
        echo "等待 WireGuard 启动... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
        sleep 5
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done

    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "⚠️  WireGuard 启动超时，但继续部署..."
    fi
fi

# 启动 Web 容器
if [ "$SERVICES" = "web" ] || [ "$SERVICES" = "all" ]; then
    echo ""
    echo "启动 Web 管理界面..."

    docker run -d \
        --name wireguard-web-ui \
        --restart unless-stopped \
        --network host \
        --cap-add NET_ADMIN \
        --user root \
        -e WEB_PORT=8080 \
        -e TZ=Asia/Shanghai \
        -v "$(pwd)/config/wireguard:/etc/wireguard" \
        -v "$(pwd)/config/wireguard/clients:/etc/wireguard/clients" \
        wireguard-web:latest

    echo "✓ Web 管理界面已启动"

    # 等待 Web 服务启动
    echo "等待 Web 服务启动..."
    sleep 5

    # 检查 Web 服务状态
    RETRY_COUNT=0
    MAX_RETRIES=6
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -f http://localhost:8080/ >/dev/null 2>&1; then
            echo "✓ Web 服务启动完成"
            break
        fi
        echo "等待 Web 服务启动... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
        sleep 5
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done

    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "⚠️  Web 服务启动检查超时，请手动检查"
    fi
fi

echo ""
echo "=========================================="
echo "✅ 部署完成！"
echo "=========================================="

if [ "$SERVICES" != "web" ]; then
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
echo "  查看容器状态: docker ps"
echo "  查看 WireGuard 日志: docker logs -f wireguard-vpn"
echo "  查看 Web 日志: docker logs -f wireguard-web-ui"
echo "  停止 WireGuard: docker stop wireguard-vpn"
echo "  停止 Web: docker stop wireguard-web-ui"
echo "  重启 WireGuard: docker restart wireguard-vpn"
echo "  重启 Web: docker restart wireguard-web-ui"
echo "=========================================="