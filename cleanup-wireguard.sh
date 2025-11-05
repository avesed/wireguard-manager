#!/bin/bash
# WireGuard 清理脚本 - 清理现有接口和配置

set -e

WG_INTERFACE=${WG_INTERFACE:-wg0}

echo "=== WireGuard 清理工具 ==="
echo ""

# 停止现有的 WireGuard 接口
if ip link show "$WG_INTERFACE" >/dev/null 2>&1; then
    echo "发现现有接口 $WG_INTERFACE，正在停止..."
    sudo wg-quick down "$WG_INTERFACE" 2>/dev/null || true
    echo "✓ 接口 $WG_INTERFACE 已停止"
else
    echo "✓ 未发现现有接口 $WG_INTERFACE"
fi

# 清理系统服务
if systemctl is-active wg-quick@$WG_INTERFACE >/dev/null 2>&1; then
    echo "停止系统服务 wg-quick@$WG_INTERFACE..."
    sudo systemctl stop wg-quick@$WG_INTERFACE || true
    sudo systemctl disable wg-quick@$WG_INTERFACE || true
    echo "✓ 系统服务已停止并禁用"
fi

# 清理容器
echo "清理现有容器..."
docker stop wireguard-vpn wireguard-web-ui 2>/dev/null || true
docker rm wireguard-vpn wireguard-web-ui 2>/dev/null || true
echo "✓ 容器已清理"

# 清理配置文件（可选）
echo ""
echo "是否要清理配置文件? (y/N)"
read -r CLEAN_CONFIG
if [[ "$CLEAN_CONFIG" =~ ^[Yy]$ ]]; then
    sudo rm -rf ./config/wireguard
    echo "✓ 配置文件已清理"
else
    echo "✓ 保留现有配置文件"
fi

echo ""
echo "=========================================="
echo "✅ 清理完成！现在可以重新部署。"
echo "=========================================="