#!/bin/bash
# WireGuard 完整诊断脚本 - 检查代码和配置

echo "=========================================="
echo "WireGuard 完整诊断工具"
echo "=========================================="
echo ""

# ========================================
# 1. 检查容器状态
# ========================================
echo "1️⃣  容器状态检查"
echo "=========================================="
docker ps | grep wireguard
echo ""

# ========================================
# 2. 检查配置文件
# ========================================
echo "2️⃣  配置文件检查"
echo "=========================================="
echo "配置文件内容:"
docker exec wireguard-web-ui cat /etc/wireguard/wg0.conf
echo ""

# ========================================
# 3. 检查 Web 容器中的 app.py 代码版本
# ========================================
echo "3️⃣  检查 Web 容器中的 app.py 代码"
echo "=========================================="
echo "检查是否有 _parse_peer_data 函数（新代码的标志）:"
if docker exec wireguard-web-ui grep -q "_parse_peer_data" /app/web/app.py 2>/dev/null; then
    echo "✅ 找到 _parse_peer_data 函数 - 代码已更新"
    echo ""
    echo "函数签名:"
    docker exec wireguard-web-ui grep -A 2 "def _parse_peer_data" /app/web/app.py
else
    echo "❌ 未找到 _parse_peer_data 函数 - 代码未更新！"
    echo ""
    echo "当前 get_clients() 函数的解析方法:"
    docker exec wireguard-web-ui grep -A 5 "def get_clients" /app/web/app.py | head -20
fi
echo ""

echo "检查 get_clients() 是否使用状态机:"
if docker exec wireguard-web-ui grep -A 30 "def get_clients" /app/web/app.py | grep -q "in_interface"; then
    echo "✅ get_clients() 使用状态机方法 - 代码已更新"
else
    echo "❌ get_clients() 仍使用旧的正则表达式方法 - 代码未更新！"
fi
echo ""

# ========================================
# 4. 测试 API 返回的客户端列表
# ========================================
echo "4️⃣  测试 API 返回的客户端列表"
echo "=========================================="
echo "调用 /api/clients API:"
curl -s http://localhost:8080/api/clients | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/api/clients
echo ""

# ========================================
# 5. 直接测试 wg show 输出
# ========================================
echo "5️⃣  WireGuard 实际状态"
echo "=========================================="
docker exec wireguard-vpn wg show wg0 2>/dev/null || echo "无法获取 WireGuard 状态"
echo ""

# ========================================
# 6. 检查客户端配置目录
# ========================================
echo "6️⃣  客户端配置目录"
echo "=========================================="
docker exec wireguard-web-ui ls -la /etc/wireguard/clients/ 2>/dev/null || echo "无法访问客户端目录"
echo ""

# ========================================
# 7. 模拟解析逻辑
# ========================================
echo "7️⃣  模拟当前代码的解析逻辑"
echo "=========================================="
docker exec wireguard-web-ui sh -c '
config=$(cat /etc/wireguard/wg0.conf)

echo "使用旧的正则表达式方法 (只匹配 [Peer] 之后的内容):"
echo "$config" | awk "
/\[Peer\]/ {
    peer_block = \"\"
    in_peer = 1
    next
}
in_peer {
    if (/^\[/) {
        # 开始新的section
        if (peer_block != \"\") {
            print \"Peer块内容:\"
            print peer_block
            print \"---\"
        }
        peer_block = \"\"
        in_peer = 0
    } else {
        peer_block = peer_block \"\\n\" \$0
    }
}
END {
    if (peer_block != \"\") {
        print \"Peer块内容:\"
        print peer_block
    }
}
"

echo ""
echo "注意: 如果 Peer 块内容中没有包含注释行，说明正则表达式无法捕获 [Peer] 之前的注释"
'
echo ""

# ========================================
# 8. 问题总结
# ========================================
echo "8️⃣  问题总结"
echo "=========================================="

# 检查代码是否更新
CODE_UPDATED=0
if docker exec wireguard-web-ui grep -q "_parse_peer_data" /app/web/app.py 2>/dev/null; then
    CODE_UPDATED=1
fi

# 检查配置是否正确
CONFIG_OK=0
if docker exec wireguard-web-ui grep -q "# 客户端: default-client" /etc/wireguard/wg0.conf 2>/dev/null; then
    CONFIG_OK=1
fi

echo "诊断结果:"
echo ""

if [ $CONFIG_OK -eq 1 ]; then
    echo "✅ 配置文件格式正确（有正确的注释）"
else
    echo "❌ 配置文件格式错误（缺少客户端名称注释）"
fi

if [ $CODE_UPDATED -eq 1 ]; then
    echo "✅ Web 容器代码已更新"
else
    echo "❌ Web 容器代码未更新（这是主要问题！）"
fi

echo ""

if [ $CONFIG_OK -eq 1 ] && [ $CODE_UPDATED -eq 1 ]; then
    echo "🎉 配置和代码都正确，问题应该已经解决"
    echo ""
    echo "如果仍有问题，请重启 Web 容器:"
    echo "  docker restart wireguard-web-ui"
elif [ $CONFIG_OK -eq 1 ] && [ $CODE_UPDATED -eq 0 ]; then
    echo "⚠️  配置正确，但代码未更新"
    echo ""
    echo "解决方案:"
    echo "  1. 进入项目目录: cd ~/wireguard-manager"
    echo "  2. 拉取最新代码: git pull origin main"
    echo "  3. 复制更新后的代码到容器:"
    echo "     docker cp web/app.py wireguard-web-ui:/app/web/app.py"
    echo "  4. 重启容器:"
    echo "     docker restart wireguard-web-ui"
elif [ $CONFIG_OK -eq 0 ]; then
    echo "⚠️  配置格式错误"
    echo ""
    echo "需要修复配置文件中的注释格式"
fi

echo ""
echo "=========================================="
echo "诊断完成"
echo "=========================================="
