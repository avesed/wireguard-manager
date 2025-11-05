#!/bin/bash

echo "=========================================="
echo "WireGuard 服务器诊断脚本"
echo "=========================================="
echo ""

echo "=== 1. 系统信息 ==="
echo "操作系统: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "内核版本: $(uname -r)"
echo ""

echo "=== 2. WireGuard 安装状态 ==="
if command -v wg &> /dev/null; then
    echo "✓ WireGuard 已安装"
    wg --version
else
    echo "✗ WireGuard 未安装"
fi
echo ""

echo "=== 3. WireGuard 配置文件 ==="
if [ -d "/etc/wireguard" ]; then
    echo "配置目录存在: /etc/wireguard"
    echo "配置文件列表:"
    ls -la /etc/wireguard/ 2>/dev/null
    echo ""

    for conf in /etc/wireguard/*.conf; do
        if [ -f "$conf" ]; then
            echo "--- 配置文件: $conf ---"
            # 隐藏私钥显示配置
            cat "$conf" | sed 's/\(PrivateKey = \).*/\1[已隐藏]/'
            echo ""
        fi
    done
else
    echo "✗ /etc/wireguard 目录不存在"
fi
echo ""

echo "=== 4. WireGuard 接口状态 ==="
if command -v wg &> /dev/null; then
    sudo wg show 2>/dev/null || echo "无法获取 WireGuard 状态（可能需要 sudo）"
else
    echo "WireGuard 未安装"
fi
echo ""

echo "=== 5. WireGuard 服务状态 ==="
if systemctl list-unit-files | grep -q "wg-quick@"; then
    for service in /etc/systemd/system/wg-quick@*.service /lib/systemd/system/wg-quick@*.service; do
        if [ -f "$service" ]; then
            interface=$(basename "$service" | sed 's/wg-quick@\(.*\)\.service/\1/')
            echo "检查接口: $interface"
            systemctl status "wg-quick@$interface" --no-pager 2>/dev/null || echo "服务未运行"
            echo ""
        fi
    done

    # 检查常见接口名
    for iface in wg0 wg1; do
        if [ -f "/etc/wireguard/${iface}.conf" ]; then
            echo "检查 wg-quick@${iface} 服务:"
            systemctl status "wg-quick@${iface}" --no-pager 2>/dev/null || echo "服务未运行"
            echo ""
        fi
    done
else
    echo "未找到 wg-quick 服务"
fi
echo ""

echo "=== 6. 网络接口 ==="
ip addr show 2>/dev/null | grep -E "^[0-9]+:|inet " || ifconfig
echo ""

echo "=== 7. IP 转发状态 ==="
echo "IPv4 转发: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "IPv6 转发: $(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo '不适用')"
if grep -q "net.ipv4.ip_forward" /etc/sysctl.conf 2>/dev/null; then
    echo "sysctl.conf 配置:"
    grep "net.ipv4.ip_forward" /etc/sysctl.conf
fi
echo ""

echo "=== 8. 防火墙状态 (UFW) ==="
if command -v ufw &> /dev/null; then
    echo "UFW 状态:"
    sudo ufw status verbose 2>/dev/null || echo "无法获取 UFW 状态"
else
    echo "UFW 未安装"
fi
echo ""

echo "=== 9. 防火墙规则 (iptables) ==="
echo "--- NAT 规则 ---"
sudo iptables -t nat -L -n -v 2>/dev/null || echo "无法获取 iptables NAT 规则"
echo ""
echo "--- FILTER 规则 ---"
sudo iptables -L -n -v 2>/dev/null || echo "无法获取 iptables 规则"
echo ""

echo "=== 10. 监听端口 ==="
echo "UDP 端口监听状态:"
sudo ss -ulnp | grep -E "51820|wireguard" || echo "未找到 WireGuard 监听端口"
echo ""
echo "所有 UDP 监听端口:"
sudo ss -ulnp | head -20
echo ""

echo "=== 11. 路由表 ==="
ip route show 2>/dev/null || route -n
echo ""

echo "=== 12. 最近的系统日志 (WireGuard 相关) ==="
echo "journalctl 日志:"
sudo journalctl -u wg-quick@* --no-pager -n 50 2>/dev/null || echo "无法获取 journalctl 日志"
echo ""
echo "dmesg 日志:"
sudo dmesg | grep -i wireguard | tail -20 2>/dev/null || echo "无日志"
echo ""

echo "=== 13. 网络连接测试 ==="
echo "外网 IP 地址:"
curl -4 -s ifconfig.me 2>/dev/null || wget -qO- ifconfig.me 2>/dev/null || echo "无法获取外网IP"
echo ""

echo "=== 14. SELinux/AppArmor 状态 ==="
if command -v getenforce &> /dev/null; then
    echo "SELinux: $(getenforce)"
elif command -v aa-status &> /dev/null; then
    echo "AppArmor: $(sudo aa-status --enabled 2>/dev/null && echo 'enabled' || echo 'disabled')"
else
    echo "未使用 SELinux 或 AppArmor"
fi
echo ""

echo "=========================================="
echo "诊断完成！请将以上输出复制给我分析"
echo "=========================================="
