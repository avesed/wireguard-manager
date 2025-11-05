#!/bin/bash
# WireGuard 卸载脚本

set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 需要 root 权限运行"
    exit 1
fi

echo "=== WireGuard 卸载脚本 ==="
echo ""
echo "⚠️  此操作将删除所有 WireGuard 配置和密钥"
echo -n "确认继续？[y/N] "
read REPLY
echo ""

if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    echo "已取消"
    exit 0
fi

# 停止服务
echo "[1/6] 停止 WireGuard 服务..."
for iface in wg0 wg1 wg2; do
    systemctl stop "wg-quick@${iface}" 2>/dev/null || true
    systemctl disable "wg-quick@${iface}" 2>/dev/null || true
done
echo "✓ 服务已停止"

# 删除网络接口
echo "[2/6] 删除网络接口..."
for iface in $(ip link show | grep -o 'wg[0-9]*' || true); do
    ip link delete "$iface" 2>/dev/null || true
done
if [ -d "/etc/wireguard" ]; then
    for conf in /etc/wireguard/*.conf; do
        [ -f "$conf" ] && wg-quick down "$(basename "$conf" .conf)" 2>/dev/null || true
    done
fi
echo "✓ 接口已删除"

# 清理防火墙规则
echo "[3/6] 清理防火墙规则..."
iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true
iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true
iptables -D INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || true
echo "✓ 防火墙规则已清理"

# 备份并删除配置
echo "[4/6] 备份并删除配置..."
if [ -d "/etc/wireguard" ]; then
    backup_dir="/root/wireguard_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r /etc/wireguard/* "$backup_dir/" 2>/dev/null || true
    rm -rf /etc/wireguard
    echo "✓ 配置已备份到: $backup_dir"
else
    echo "✓ 配置目录不存在"
fi

# 卸载软件包
echo "[5/6] 卸载软件包..."
apt-get remove -y wireguard wireguard-tools 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
echo "✓ 软件包已卸载"

# 清理内核模块
echo "[6/6] 卸载内核模块..."
rmmod wireguard 2>/dev/null || true
echo "✓ 内核模块已卸载"

echo ""
echo "=========================================="
echo "✅ WireGuard 卸载完成！"
if [ -d "$backup_dir" ]; then
    echo "配置备份: $backup_dir"
fi
echo "=========================================="
