#!/bin/bash

# 简化的快速测试脚本
echo "🔍 快速流量诊断"
echo "===================="

# 检查当前流量文件
echo "1. 当前 traffic.json 内容:"
if [ -f config/wireguard/traffic.json ]; then
    cat config/wireguard/traffic.json | python3 -m json.tool 2>/dev/null || cat config/wireguard/traffic.json
else
    echo "文件不存在"
fi

echo ""
echo "2. WireGuard 实际状态:"
docker exec wireguard-vpn wg show wg0

echo ""
echo "3. 容器镜像信息:"
docker inspect wireguard-web-ui | grep -E "(Created|Image)" | head -3

echo ""
echo "4. 最近日志（查找DEBUG信息）:"
docker logs --tail 30 wireguard-web-ui | grep -E "(DEBUG|ERROR|Exception)" || echo "无DEBUG信息"