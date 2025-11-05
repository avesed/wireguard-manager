#!/bin/bash
# WireGuard Web 代码快速更新脚本

set -e

echo "=========================================="
echo "WireGuard Web 代码快速更新"
echo "=========================================="
echo ""

# 检查是否在项目目录
if [ ! -f "web/app.py" ]; then
    echo "❌ 错误: 找不到 web/app.py"
    echo "请在项目根目录运行此脚本"
    echo "例如: cd ~/wireguard-manager && bash quick-fix.sh"
    exit 1
fi

# 检查容器是否运行
if ! docker ps | grep -q wireguard-web-ui; then
    echo "❌ 错误: wireguard-web-ui 容器未运行"
    echo ""
    echo "请先启动容器:"
    echo "  ./start-web.sh"
    exit 1
fi

echo "✓ 检查通过"
echo ""

# ========================================
# 步骤 1: 拉取最新代码
# ========================================
echo "步骤 1/4: 拉取最新代码"
echo "=========================================="
if git pull origin main 2>/dev/null; then
    echo "✓ 代码已更新"
else
    echo "⚠️  Git 拉取失败，使用本地文件"
fi
echo ""

# ========================================
# 步骤 2: 验证本地代码
# ========================================
echo "步骤 2/4: 验证本地代码"
echo "=========================================="
if grep -q "_parse_peer_data" web/app.py; then
    echo "✓ 本地 app.py 包含修复代码"
else
    echo "❌ 错误: 本地 app.py 不包含修复代码"
    echo "请确保已经合并了最新的修复"
    exit 1
fi
echo ""

# ========================================
# 步骤 3: 备份容器中的旧文件
# ========================================
echo "步骤 3/4: 备份容器中的旧文件"
echo "=========================================="
BACKUP_NAME="app.py.backup.$(date +%Y%m%d_%H%M%S)"
docker exec wireguard-web-ui cp /app/web/app.py /app/web/$BACKUP_NAME
echo "✓ 已备份到容器内: /app/web/$BACKUP_NAME"
echo ""

# ========================================
# 步骤 4: 更新容器中的代码
# ========================================
echo "步骤 4/4: 更新容器中的代码"
echo "=========================================="
docker cp web/app.py wireguard-web-ui:/app/web/app.py
echo "✓ 已复制新代码到容器"
echo ""

# ========================================
# 步骤 5: 重启容器
# ========================================
echo "步骤 5/4: 重启容器"
echo "=========================================="
echo "重启 Web 容器..."
docker restart wireguard-web-ui
echo "✓ 容器已重启"
echo ""

echo "等待服务启动..."
sleep 5

# ========================================
# 步骤 6: 验证更新
# ========================================
echo "步骤 6/4: 验证更新"
echo "=========================================="
if docker exec wireguard-web-ui grep -q "_parse_peer_data" /app/web/app.py; then
    echo "✅ 容器中的代码已更新"
else
    echo "❌ 更新失败"
    exit 1
fi
echo ""

# 测试 API
echo "测试 API 响应:"
API_RESPONSE=$(curl -s http://localhost:8080/api/clients)
if echo "$API_RESPONSE" | grep -q "clients"; then
    echo "✓ API 响应正常"
    echo ""
    echo "客户端列表:"
    echo "$API_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$API_RESPONSE"
else
    echo "⚠️  API 响应异常"
    echo "响应内容: $API_RESPONSE"
fi

echo ""
echo "=========================================="
echo "✅ 更新完成！"
echo "=========================================="
echo ""
echo "现在请访问 Web 界面测试:"
echo "  http://23.252.107.171:8080"
echo ""
echo "预期结果:"
echo "  - 客户端显示为 'default-client'（而不是 Unknown-xxx）"
echo "  - 可以正常添加和删除客户端"
echo "  - 新添加的客户端显示正确的名称"
echo ""
echo "查看日志:"
echo "  docker logs -f wireguard-web-ui"
echo ""
echo "=========================================="
