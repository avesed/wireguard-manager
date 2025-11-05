#!/bin/bash

# WireGuard 完全卸载脚本
# 适用于 Ubuntu/Debian 系统

set -e

echo "=========================================="
echo "WireGuard 完全卸载脚本"
echo "=========================================="
echo ""

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本"
    echo "使用: sudo bash $0"
    exit 1
fi

echo "⚠️  警告：此操作将："
echo "  - 停止所有 WireGuard 服务"
echo "  - 删除所有 WireGuard 配置文件和密钥"
echo "  - 卸载 WireGuard 软件包"
echo "  - 清理 iptables 规则"
echo "  - 删除网络接口"
echo ""
echo -n "确认继续？[y/N] "
read REPLY
echo ""
if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    echo "开始卸载..."
else
    echo "已取消操作"
    exit 0
fi

echo ""
echo "=== 1. 停止 WireGuard 服务 ==="
# 停止所有 wg-quick 服务
for service in $(systemctl list-units --all 'wg-quick@*' --no-legend | awk '{print $1}'); do
    echo "停止服务: $service"
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
done

# 尝试停止常见接口
for iface in wg0 wg1 wg2; do
    if systemctl is-active --quiet "wg-quick@${iface}" 2>/dev/null; then
        echo "停止 wg-quick@${iface}"
        systemctl stop "wg-quick@${iface}" 2>/dev/null || true
        systemctl disable "wg-quick@${iface}" 2>/dev/null || true
    fi
done

echo "✓ 服务已停止"
echo ""

echo "=== 2. 删除 WireGuard 网络接口 ==="
# 删除所有 WireGuard 接口
for iface in $(ip link show | grep -o 'wg[0-9]*' || true); do
    echo "删除接口: $iface"
    ip link delete "$iface" 2>/dev/null || true
done

# 使用 wg-quick 清理
if [ -d "/etc/wireguard" ]; then
    for conf in /etc/wireguard/*.conf; do
        if [ -f "$conf" ]; then
            iface=$(basename "$conf" .conf)
            echo "清理配置: $iface"
            wg-quick down "$iface" 2>/dev/null || true
        fi
    done
fi

echo "✓ 接口已删除"
echo ""

echo "=== 3. 清理 iptables 规则 ==="
# 清理 FORWARD 规则
echo "清理 FORWARD 链规则..."
iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true

# 清理 NAT 规则（尝试删除所有相关的 MASQUERADE 规则）
echo "清理 NAT 规则..."
iptables -t nat -D POSTROUTING -o eth0 -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true

# 清理 INPUT 规则
echo "清理 INPUT 链规则..."
iptables -D INPUT -p udp --dport 51820 -j ACCEPT 2>/dev/null || true

echo "✓ iptables 规则已清理"
echo ""

echo "=== 4. 备份并删除配置文件 ==="
if [ -d "/etc/wireguard" ]; then
    # 创建备份
    backup_dir="/root/wireguard_backup_$(date +%Y%m%d_%H%M%S)"
    echo "备份配置到: $backup_dir"
    mkdir -p "$backup_dir"
    cp -r /etc/wireguard/* "$backup_dir/" 2>/dev/null || true

    # 删除配置目录
    echo "删除配置目录: /etc/wireguard"
    rm -rf /etc/wireguard

    echo "✓ 配置已备份并删除"
else
    echo "✓ 配置目录不存在，跳过"
fi
echo ""

echo "=== 5. 卸载 WireGuard 软件包 ==="
# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

case $OS in
    ubuntu|debian)
        echo "检测到 Debian/Ubuntu 系统"
        apt-get remove -y wireguard wireguard-tools wireguard-dkms 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        apt-get autoclean 2>/dev/null || true
        ;;
    centos|rhel|fedora)
        echo "检测到 CentOS/RHEL/Fedora 系统"
        yum remove -y wireguard-tools wireguard-dkms 2>/dev/null || true
        ;;
    *)
        echo "⚠️  未知系统类型，请手动卸载"
        ;;
esac

echo "✓ 软件包已卸载"
echo ""

echo "=== 6. 清理内核模块 ==="
if lsmod | grep -q wireguard; then
    echo "卸载 wireguard 内核模块"
    rmmod wireguard 2>/dev/null || true
    echo "✓ 内核模块已卸载"
else
    echo "✓ 内核模块未加载"
fi
echo ""

echo "=== 7. 恢复 IP 转发设置（可选） ==="
echo -n "是否禁用 IP 转发？[y/N] "
read REPLY
echo ""
if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    echo "禁用 IP 转发"
    sysctl -w net.ipv4.ip_forward=0 >/dev/null
    # 从 sysctl.conf 中删除配置
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf 2>/dev/null || true
    echo "✓ IP 转发已禁用"
else
    echo "✓ 保持 IP 转发启用"
fi
echo ""

echo "=== 8. 验证卸载 ==="
echo "检查 WireGuard 命令..."
if command -v wg &> /dev/null; then
    echo "⚠️  wg 命令仍然存在"
else
    echo "✓ wg 命令已删除"
fi

echo "检查配置目录..."
if [ -d "/etc/wireguard" ]; then
    echo "⚠️  /etc/wireguard 目录仍然存在"
else
    echo "✓ 配置目录已删除"
fi

echo "检查网络接口..."
if ip link show | grep -q wg; then
    echo "⚠️  仍有 WireGuard 接口存在"
else
    echo "✓ 所有 WireGuard 接口已删除"
fi

echo ""
echo "=========================================="
echo "✓ WireGuard 卸载完成！"
echo ""
if [ -d "$backup_dir" ]; then
    echo "配置文件已备份到: $backup_dir"
fi
echo "=========================================="
