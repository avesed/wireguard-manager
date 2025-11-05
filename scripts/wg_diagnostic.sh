#!/bin/bash
# WireGuard 诊断脚本

echo "=== WireGuard 诊断 ==="
echo ""

# 系统信息
echo "[系统]"
echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo ""

# WireGuard 状态
echo "[WireGuard 状态]"
if command -v wg &> /dev/null; then
    echo "✓ 已安装: $(wg --version 2>&1 | head -1)"
    echo ""
    sudo wg show 2>/dev/null || echo "无法获取状态"
else
    echo "✗ 未安装"
fi
echo ""

# 配置文件
echo "[配置文件]"
if [ -d "/etc/wireguard" ]; then
    ls -la /etc/wireguard/*.conf 2>/dev/null || echo "无配置文件"
    echo ""
    if [ -f "/etc/wireguard/wg0.conf" ]; then
        cat /etc/wireguard/wg0.conf | sed 's/\(PrivateKey = \).*/\1[HIDDEN]/' | head -30
    fi
else
    echo "✗ 配置目录不存在"
fi
echo ""

# 网络配置
echo "[网络]"
echo "IP 转发: $(cat /proc/sys/net/ipv4/ip_forward)"
echo ""
ip addr show | grep -E "^[0-9]+: |inet " | head -15
echo ""

# 防火墙
echo "[防火墙]"
sudo iptables -t nat -L POSTROUTING -n | head -10 2>/dev/null || echo "无法获取 NAT 规则"
echo ""
sudo iptables -L INPUT -n | grep -E "51820|wg" 2>/dev/null || echo "无 WireGuard 规则"
echo ""

# 监听端口
echo "[监听端口]"
sudo ss -ulnp | grep -E "51820|wireguard" || echo "未监听"
echo ""

# 日志
echo "[最近日志]"
sudo journalctl -u wg-quick@* --no-pager -n 15 2>/dev/null || echo "无日志"
echo ""

echo "=== 诊断完成 ==="
echo "提示: 将此输出发送给管理员以获取帮助"
