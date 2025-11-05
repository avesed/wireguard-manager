#!/bin/bash
# WireGuard 配置诊断脚本

echo "=========================================="
echo "WireGuard 配置诊断工具"
echo "=========================================="
echo ""

# 检查容器是否运行
if ! docker ps | grep -q wireguard-web-ui; then
    echo "❌ wireguard-web-ui 容器未运行"
    echo ""
    echo "所有 WireGuard 相关容器:"
    docker ps -a | grep wireguard || echo "  没有找到容器"
    exit 1
fi

echo "✓ 找到运行中的容器"
echo ""

# ========================================
# 1. 显示完整配置文件
# ========================================
echo "=========================================="
echo "📄 配置文件内容 (/etc/wireguard/wg0.conf)"
echo "=========================================="
docker exec wireguard-web-ui cat /etc/wireguard/wg0.conf
echo ""

# ========================================
# 2. 统计 Peer 数量
# ========================================
echo "=========================================="
echo "📊 统计信息"
echo "=========================================="
PEER_COUNT=$(docker exec wireguard-web-ui grep -c "\[Peer\]" /etc/wireguard/wg0.conf 2>/dev/null || echo "0")
echo "总 Peer 数量: $PEER_COUNT"
echo ""

# ========================================
# 3. 检测重复公钥
# ========================================
echo "=========================================="
echo "🔍 重复公钥检测"
echo "=========================================="
DUPLICATES=$(docker exec wireguard-web-ui sh -c 'grep "PublicKey" /etc/wireguard/wg0.conf | awk "{print \$3}" | sort | uniq -c | awk "\$1 > 1 {print}"')
if [ -z "$DUPLICATES" ]; then
    echo "✓ 没有重复的公钥"
else
    echo "⚠️  发现重复的公钥:"
    echo "$DUPLICATES"
fi
echo ""

# ========================================
# 4. 详细分析每个 Peer
# ========================================
echo "=========================================="
echo "📋 详细 Peer 分析"
echo "=========================================="

docker exec wireguard-web-ui sh -c '
config=$(cat /etc/wireguard/wg0.conf)

peer_num=0
comment=""
in_peer=0
pubkey=""
ip=""

while IFS= read -r line; do
    stripped=$(echo "$line" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")

    # 检测 [Peer]
    if [ "$stripped" = "[Peer]" ]; then
        # 输出上一个peer
        if [ $in_peer -eq 1 ] && [ -n "$pubkey" ]; then
            peer_num=$((peer_num + 1))
            echo ""
            echo "🔹 Peer #$peer_num:"

            if [ -z "$comment" ]; then
                echo "   注释: ❌ 无注释 (会显示为 Unknown-xxx)"
            else
                echo "   注释: $comment"
            fi

            echo "   公钥: $pubkey"
            echo "   公钥后8位: ${pubkey: -8}"
            echo "   IP: $ip"
        fi

        in_peer=1
        comment=""
        pubkey=""
        ip=""

    # 在peer之前或之中收集注释
    elif echo "$stripped" | grep -q "^#"; then
        # 提取客户端名称
        if echo "$stripped" | grep -q "^# 客户端[：:]"; then
            comment=$(echo "$stripped" | sed "s/^# 客户端[：:][[:space:]]*//" | awk "{print \$1}")
        elif echo "$stripped" | grep -qi "^# Client:"; then
            comment=$(echo "$stripped" | sed "s/^# [Cc]lient:[[:space:]]*//" | awk "{print \$1}")
        elif [ -z "$comment" ] && echo "$stripped" | grep -qE "^# [a-zA-Z0-9_-]+$"; then
            candidate=$(echo "$stripped" | sed "s/^# *//" | awk "{print \$1}")
            # 排除关键词
            if ! echo "$candidate" | grep -qE "^(Peer|PublicKey|AllowedIPs|Endpoint|客户端|公钥)"; then
                comment="$candidate"
            fi
        fi

    # 提取 PublicKey
    elif [ $in_peer -eq 1 ] && echo "$stripped" | grep -q "^PublicKey"; then
        pubkey=$(echo "$stripped" | awk "{print \$3}")

    # 提取 AllowedIPs
    elif [ $in_peer -eq 1 ] && echo "$stripped" | grep -q "^AllowedIPs"; then
        ip=$(echo "$stripped" | awk "{print \$3}" | sed "s/\/32//")
    fi

done <<< "$config"

# 输出最后一个peer
if [ $in_peer -eq 1 ] && [ -n "$pubkey" ]; then
    peer_num=$((peer_num + 1))
    echo ""
    echo "🔹 Peer #$peer_num:"

    if [ -z "$comment" ]; then
        echo "   注释: ❌ 无注释 (会显示为 Unknown-xxx)"
    else
        echo "   注释: $comment"
    fi

    echo "   公钥: $pubkey"
    echo "   公钥后8位: ${pubkey: -8}"
    echo "   IP: $ip"
fi

echo ""
echo "总计: $peer_num 个 Peer"
'

echo ""

# ========================================
# 5. 问题检测总结
# ========================================
echo "=========================================="
echo "⚠️  问题检测总结"
echo "=========================================="

HAS_ISSUES=0

# 检测无注释的peer
NO_COMMENT_COUNT=$(docker exec wireguard-web-ui sh -c '
config=$(cat /etc/wireguard/wg0.conf)
count=0
in_peer=0
has_comment=0

while IFS= read -r line; do
    stripped=$(echo "$line" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")

    if [ "$stripped" = "[Peer]" ]; then
        if [ $in_peer -eq 1 ] && [ $has_comment -eq 0 ]; then
            count=$((count + 1))
        fi
        in_peer=1
        has_comment=0
    elif echo "$stripped" | grep -q "^# 客户端[：:]"; then
        has_comment=1
    elif echo "$stripped" | grep -qi "^# Client:"; then
        has_comment=1
    fi
done <<< "$config"

if [ $in_peer -eq 1 ] && [ $has_comment -eq 0 ]; then
    count=$((count + 1))
fi

echo $count
')

if [ "$NO_COMMENT_COUNT" -gt 0 ]; then
    echo "❌ 发现 $NO_COMMENT_COUNT 个无注释的 Peer（会显示为 Unknown-xxx）"
    HAS_ISSUES=1
fi

# 检测重复公钥
if [ -n "$DUPLICATES" ]; then
    echo "❌ 发现重复的公钥"
    HAS_ISSUES=1
fi

if [ $HAS_ISSUES -eq 0 ]; then
    echo "✓ 没有发现明显问题"
fi

echo ""

# ========================================
# 6. 建议操作
# ========================================
echo "=========================================="
echo "💡 建议操作"
echo "=========================================="

if [ "$NO_COMMENT_COUNT" -gt 0 ]; then
    echo ""
    echo "问题: 有 $NO_COMMENT_COUNT 个无注释的 Peer"
    echo "原因: 这些 Peer 没有正确的注释格式，无法识别名称"
    echo "解决方案："
    echo "  选项1: 通过 Web 界面删除这些 Unknown-xxx 客户端"
    echo "  选项2: 手动编辑配置文件添加注释:"
    echo "         docker exec -it wireguard-web-ui nano /etc/wireguard/wg0.conf"
    echo "         在 [Peer] 上方添加: # 客户端: your-name"
    echo ""
fi

if [ -n "$DUPLICATES" ]; then
    echo ""
    echo "问题: 有重复的公钥"
    echo "原因: 同一个客户端被添加了多次"
    echo "解决方案："
    echo "  通过 Web 界面删除重复的客户端，只保留一个"
    echo ""
fi

echo ""
echo "查看实时状态:"
echo "  Web 界面: http://23.252.107.171:8080"
echo "  容器日志: docker logs -f wireguard-web-ui"
echo "  WireGuard 状态: docker exec wireguard-vpn wg show"
echo ""

echo "=========================================="
echo "诊断完成"
echo "=========================================="
