#!/bin/bash

# WireGuard 流量显示问题诊断脚本
# 用于诊断为什么流量数据显示为 0B

echo "=========================================="
echo "🔍 WireGuard 流量诊断脚本"
echo "=========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# 1. 检查 Docker 环境
log_info "1. 检查 Docker 环境"
echo "----------------------------------------"

if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker 未安装"
    exit 1
fi

# 检查容器状态
if docker ps | grep -q wireguard-web-ui; then
    log_success "wireguard-web-ui 容器正在运行"
    WEB_CONTAINER_ID=$(docker ps | grep wireguard-web-ui | awk '{print $1}')
    echo "容器 ID: $WEB_CONTAINER_ID"

    # 检查镜像信息
    IMAGE_ID=$(docker inspect $WEB_CONTAINER_ID | grep '"Image"' | head -1 | sed 's/.*"Image": "\([^"]*\)".*/\1/')
    echo "使用镜像: $IMAGE_ID"

    # 检查容器创建时间
    CREATED=$(docker inspect $WEB_CONTAINER_ID | grep '"Created"' | head -1 | sed 's/.*"Created": "\([^"]*\)".*/\1/')
    echo "容器创建时间: $CREATED"
else
    log_error "wireguard-web-ui 容器未运行"
    exit 1
fi

if docker ps | grep -q wireguard-vpn; then
    log_success "wireguard-vpn 容器正在运行"
else
    log_error "wireguard-vpn 容器未运行"
fi

echo ""

# 2. 检查 WireGuard 配置
log_info "2. 检查 WireGuard 配置"
echo "----------------------------------------"

# 检查配置文件
if docker exec wireguard-web-ui test -f /etc/wireguard/wg0.conf; then
    log_success "WireGuard 配置文件存在"

    echo "配置文件内容:"
    docker exec wireguard-web-ui cat /etc/wireguard/wg0.conf
    echo ""

    # 提取客户端信息
    echo "检测到的客户端:"
    docker exec wireguard-web-ui grep -E "(^#|PublicKey)" /etc/wireguard/wg0.conf | grep -A1 "^#"
    echo ""
else
    log_error "WireGuard 配置文件不存在"
fi

echo ""

# 3. 检查 WireGuard 状态
log_info "3. 检查 WireGuard 状态"
echo "----------------------------------------"

WG_OUTPUT=$(docker exec wireguard-vpn wg show wg0 2>/dev/null)
if [ $? -eq 0 ]; then
    log_success "WireGuard 状态获取成功"
    echo "$WG_OUTPUT"
    echo ""

    # 提取 peer 信息
    echo "检测到的 peers:"
    echo "$WG_OUTPUT" | grep -E "(peer:|transfer:)" | head -10
    echo ""
else
    log_error "无法获取 WireGuard 状态"
fi

echo ""

# 4. 检查 traffic.json
log_info "4. 检查流量数据文件"
echo "----------------------------------------"

if docker exec wireguard-web-ui test -f /etc/wireguard/traffic.json; then
    log_success "traffic.json 文件存在"
    echo "当前内容:"
    docker exec wireguard-web-ui cat /etc/wireguard/traffic.json | python3 -m json.tool 2>/dev/null || docker exec wireguard-web-ui cat /etc/wireguard/traffic.json
    echo ""
else
    log_warning "traffic.json 文件不存在（将在首次运行时创建）"
fi

echo ""

# 5. 完整流程测试
log_info "5. 完整流程测试"
echo "----------------------------------------"

# 在容器中运行完整的解析测试
docker exec wireguard-web-ui python3 << 'EOF'
import re
import json
import subprocess
from datetime import datetime

print("🧪 开始完整流程测试...")
print()

# 1. 获取 WireGuard 状态
try:
    result = subprocess.run(['wg', 'show', 'wg0'], capture_output=True, text=True)
    if result.returncode == 0:
        wg_output = result.stdout
        print("✅ WireGuard 状态获取成功")
        print("WG 输出:")
        print(wg_output)
        print()
    else:
        print("❌ 无法获取 WireGuard 状态")
        exit(1)
except Exception as e:
    print(f"❌ 执行 wg show 失败: {e}")
    exit(1)

# 2. 读取配置文件
try:
    with open('/etc/wireguard/wg0.conf', 'r') as f:
        config = f.read()
    print("✅ 配置文件读取成功")
except Exception as e:
    print(f"❌ 读取配置文件失败: {e}")
    exit(1)

# 3. 解析客户端
print("🔍 解析客户端信息...")

# 简化的客户端解析逻辑
peer_blocks = re.findall(r'(\[Peer\].*?)(?=\[Peer\]|$)', config, re.DOTALL)
print(f"找到 {len(peer_blocks)} 个 Peer 块")

for i, peer_block in enumerate(peer_blocks):
    print(f"\n--- Peer {i+1} ---")

    # 查找注释（客户端名称）
    lines_before_peer = config.split(peer_block)[0].split('\n')
    name = f"Unknown-{i+1}"

    # 从后往前查找最近的注释
    for line in reversed(lines_before_peer[-10:]):
        line = line.strip()
        if line.startswith('#'):
            # 尝试提取客户端名称
            if '客户端:' in line or 'Client:' in line:
                name_match = re.search(r'[客户端Client]:\s*(\S+)', line)
                if name_match:
                    name = name_match.group(1)
                    break
            elif re.match(r'^#\s*[a-zA-Z0-9_-]+\s*$', line):
                name = line[1:].strip()
                break

    print(f"客户端名称: {name}")

    # 提取公钥
    pubkey_match = re.search(r'PublicKey\s*=\s*([^\s]+)', peer_block)
    if pubkey_match:
        pubkey = pubkey_match.group(1)
        print(f"公钥: {pubkey}")

        # 在 wg show 输出中查找对应的 peer
        peer_pattern = f'peer: {re.escape(pubkey)}(.*?)(?=peer:|$)'
        peer_info = re.search(peer_pattern, wg_output, re.DOTALL)

        if peer_info:
            peer_data_status = peer_info.group(1)
            print("✅ 在 wg show 中找到对应 peer")
            print(f"Peer 数据: {repr(peer_data_status)}")

            # 解析流量数据
            rx_match = re.search(r'transfer:\s*([\d.]+\s+\w+)\s+received', peer_data_status)
            tx_match = re.search(r'received,\s*([\d.]+\s+\w+)\s+sent', peer_data_status)

            if rx_match and tx_match:
                transfer_rx = rx_match.group(1)
                transfer_tx = tx_match.group(1)
                print(f"✅ 流量解析成功:")
                print(f"   接收: {transfer_rx}")
                print(f"   发送: {transfer_tx}")

                # 测试 parse_transfer_size 函数
                def parse_transfer_size(size_str):
                    if not size_str or size_str == '0 B':
                        return 0

                    binary_units = {
                        'B': 1, 'KiB': 1024, 'MiB': 1024**2, 'GiB': 1024**3, 'TiB': 1024**4
                    }
                    decimal_units = {
                        'B': 1, 'KB': 1000, 'MB': 1000**2, 'GB': 1000**3, 'TB': 1000**4
                    }

                    match = re.match(r'([\d.]+)\s*(\w+)', size_str)
                    if match:
                        value = float(match.group(1))
                        unit = match.group(2)
                        multiplier = binary_units.get(unit) or decimal_units.get(unit, 1)
                        return int(value * multiplier)
                    return 0

                def format_bytes(bytes_value):
                    if bytes_value == 0:
                        return '0 B'
                    units = ['B', 'KB', 'MB', 'GB', 'TB']
                    unit_index = 0
                    value = float(bytes_value)
                    while value >= 1000 and unit_index < len(units) - 1:
                        value /= 1000
                        unit_index += 1
                    if value >= 100:
                        return f'{value:.1f} {units[unit_index]}'
                    elif value >= 10:
                        return f'{value:.2f} {units[unit_index]}'
                    else:
                        return f'{value:.2f} {units[unit_index]}'

                # 转换为字节
                rx_bytes = parse_transfer_size(transfer_rx)
                tx_bytes = parse_transfer_size(transfer_tx)
                total_bytes = rx_bytes + tx_bytes

                print(f"✅ 字节转换成功:")
                print(f"   接收字节: {rx_bytes:,}")
                print(f"   发送字节: {tx_bytes:,}")
                print(f"   总字节: {total_bytes:,}")
                print(f"   格式化总流量: {format_bytes(total_bytes)}")

                # 模拟 traffic_data 更新
                traffic_data = {}
                if name not in traffic_data:
                    traffic_data[name] = {
                        'accumulated_rx': 0,
                        'accumulated_tx': 0,
                        'last_rx': 0,
                        'last_tx': 0,
                        'last_update': datetime.now().isoformat()
                    }

                client_traffic = traffic_data[name]

                # 检测重置
                if rx_bytes < client_traffic['last_rx']:
                    client_traffic['accumulated_rx'] += client_traffic['last_rx']
                if tx_bytes < client_traffic['last_tx']:
                    client_traffic['accumulated_tx'] += client_traffic['last_tx']

                # 计算总流量
                total_rx = client_traffic['accumulated_rx'] + rx_bytes
                total_tx = client_traffic['accumulated_tx'] + tx_bytes
                final_total = total_rx + total_tx

                # 更新记录
                client_traffic['last_rx'] = rx_bytes
                client_traffic['last_tx'] = tx_bytes
                client_traffic['last_update'] = datetime.now().isoformat()

                print(f"✅ 最终计算结果:")
                print(f"   累计接收: {total_rx:,} bytes")
                print(f"   累计发送: {total_tx:,} bytes")
                print(f"   总流量: {final_total:,} bytes")
                print(f"   显示为: {format_bytes(final_total)}")

                # 输出应该保存的数据
                print(f"✅ 应该保存到 traffic.json:")
                print(json.dumps({name: client_traffic}, indent=2))

            else:
                print("❌ 流量数据解析失败")
                print(f"   rx_match: {rx_match.group(1) if rx_match else 'None'}")
                print(f"   tx_match: {tx_match.group(1) if tx_match else 'None'}")
        else:
            print("❌ 在 wg show 中未找到对应 peer")
            print(f"   查找的公钥: {pubkey}")
            print("   可能的原因:")
            print("   1. 客户端未连接")
            print("   2. 公钥不匹配")
            print("   3. WireGuard 配置问题")
    else:
        print("❌ 无法提取公钥")

print("\n🏁 测试完成")
EOF

echo ""

# 6. 容器日志检查
log_info "6. 检查容器日志"
echo "----------------------------------------"

echo "最近的容器日志 (最后20行):"
docker logs --tail 20 wireguard-web-ui

echo ""

# 7. API 测试
log_info "7. API 测试"
echo "----------------------------------------"

echo "测试 /api/status 端点:"
if command -v curl >/dev/null 2>&1; then
    curl -s http://localhost:8080/api/status | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8080/api/status
else
    log_warning "curl 未安装，跳过 API 测试"
fi

echo ""
echo ""

# 8. 建议和总结
log_info "8. 诊断总结和建议"
echo "----------------------------------------"

echo "🔧 如果流量仍显示 0B，请尝试以下步骤："
echo ""
echo "1. 强制重新构建 Docker 镜像:"
echo "   docker stop wireguard-web-ui"
echo "   docker rm wireguard-web-ui"
echo "   docker rmi wireguard-web:latest"
echo "   sudo bash start-web.sh"
echo ""
echo "2. 清理流量数据文件:"
echo "   rm -f config/wireguard/traffic.json"
echo ""
echo "3. 查看实时日志:"
echo "   docker logs -f wireguard-web-ui"
echo ""
echo "4. 手动触发数据刷新:"
echo "   访问 Web 界面并刷新页面"
echo ""

log_success "诊断脚本执行完成！"
echo "请将以上输出发送给开发人员进行进一步分析。"