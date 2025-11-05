#!/bin/bash

# 清理无效的 sysctl 配置

echo "清理系统配置文件中的 eth1 相关配置..."

# 备份配置文件
if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d)
    echo "✓ 已备份 /etc/sysctl.conf"
fi

# 查找并注释掉 eth1 相关配置
if [ -f /etc/sysctl.conf ]; then
    sed -i 's/^\(.*eth1.*\)$/# \1/' /etc/sysctl.conf
    echo "✓ 已注释 /etc/sysctl.conf 中的 eth1 配置"
fi

# 检查 sysctl.d 目录
if [ -d /etc/sysctl.d ]; then
    for file in /etc/sysctl.d/*.conf; do
        if [ -f "$file" ] && grep -q "eth1" "$file"; then
            cp "$file" "${file}.backup.$(date +%Y%m%d)"
            sed -i 's/^\(.*eth1.*\)$/# \1/' "$file"
            echo "✓ 已处理: $file"
        fi
    done
fi

echo ""
echo "✓ 清理完成！重新加载配置..."
sysctl -p 2>&1 | grep -v "eth1" || true

echo ""
echo "✓ 配置已清理，不会再显示 eth1 相关警告"
