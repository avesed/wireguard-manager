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

# 配置身份认证
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-}

# 如果未设置密码，生成随机密码
if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
    GENERATED_PASSWORD=true
else
    GENERATED_PASSWORD=false
fi

# 生成 SECRET_KEY
SECRET_KEY=${SECRET_KEY:-$(openssl rand -hex 32)}

echo "启动 Web 容器 (以 root 身份运行以避免权限问题)..."
docker run -d \
    --name wireguard-web-ui \
    --restart unless-stopped \
    --network host \
    --cap-add NET_ADMIN \
    --user root \
    -e WEB_PORT=8080 \
    -e ADMIN_USERNAME="$ADMIN_USERNAME" \
    -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
    -e SECRET_KEY="$SECRET_KEY" \
    -v "$(pwd)/config/wireguard:/etc/wireguard" \
    -v "$(pwd)/config/wireguard/clients:/etc/wireguard/clients" \
    wireguard-web:latest

echo "✅ Web 管理界面已启动"
echo ""
echo "访问地址: http://localhost:8080"
echo ""
echo "🔒 登录凭据:"
echo "  用户名: $ADMIN_USERNAME"
if [ "$GENERATED_PASSWORD" = "true" ]; then
    echo "  密码: $ADMIN_PASSWORD"
    echo ""
    echo "  ⚠️  这是自动生成的密码，请妥善保存！"

    # 保存凭据到文件
    mkdir -p config
    cat > config/web-credentials.txt <<EOF
WireGuard Web 管理面板登录凭据
================================
访问地址: http://localhost:8080
用户名: $ADMIN_USERNAME
密码: $ADMIN_PASSWORD
生成时间: $(date)
================================
⚠️ 请妥善保管此文件，并在首次登录后删除
EOF
    chmod 600 config/web-credentials.txt
    echo ""
    echo "  凭据已保存到: config/web-credentials.txt"
else
    echo "  密码: (使用环境变量设置的密码)"
fi
echo ""
echo "查看日志: docker logs -f wireguard-web-ui"