#!/usr/bin/env python3
"""
WireGuard Web 管理界面 - Flask 后端
"""

from flask import Flask, render_template, jsonify, request, send_file
import subprocess
import os
import re
import json
from datetime import datetime
import tempfile
import base64
from io import BytesIO

app = Flask(__name__)

# 配置
WG_INTERFACE = "wg0"
WG_DIR = "/etc/wireguard"
WG_CONF = f"{WG_DIR}/{WG_INTERFACE}.conf"
CLIENT_DIR = f"{WG_DIR}/clients"


def run_command(cmd, use_sudo=True):
    """执行命令并返回结果"""
    try:
        if use_sudo and not cmd.startswith('sudo'):
            cmd = f'sudo {cmd}'
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=10
        )
        return {
            'success': result.returncode == 0,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }


def get_server_info():
    """获取服务器信息"""
    try:
        # 获取服务器配置
        result = run_command(f'cat {WG_CONF}')
        if not result['success']:
            return {'error': 'Cannot read WireGuard config'}

        config = result['stdout']

        # 解析配置
        server_info = {
            'interface': WG_INTERFACE,
            'address': re.search(r'Address\s*=\s*([^\s]+)', config).group(1) if re.search(r'Address\s*=\s*([^\s]+)', config) else 'N/A',
            'listen_port': re.search(r'ListenPort\s*=\s*(\d+)', config).group(1) if re.search(r'ListenPort\s*=\s*(\d+)', config) else 'N/A',
        }

        # 获取公网 IP
        public_ip_cmd = run_command("ip addr show $(ip route | grep default | awk '{print $5}' | head -n1) | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1", use_sudo=False)
        server_info['public_ip'] = public_ip_cmd['stdout'].strip() if public_ip_cmd['success'] else 'N/A'

        # 获取服务状态
        status_cmd = run_command(f'systemctl is-active wg-quick@{WG_INTERFACE}')
        server_info['status'] = status_cmd['stdout'].strip() if status_cmd['success'] else 'inactive'

        return server_info
    except Exception as e:
        return {'error': str(e)}


def get_clients():
    """获取所有客户端信息"""
    try:
        # 读取配置文件
        result = run_command(f'cat {WG_CONF}')
        if not result['success']:
            return []

        config = result['stdout']

        # 获取 wg show 输出（包含连接状态）
        wg_show = run_command(f'wg show {WG_INTERFACE}')
        wg_output = wg_show['stdout'] if wg_show['success'] else ''

        clients = []
        peer_blocks = re.findall(r'\[Peer\](.*?)(?=\[Peer\]|$)', config, re.DOTALL)

        for block in peer_blocks:
            # 提取客户端名称（从注释中）
            name_match = re.search(r'#\s*客户端[：:]\s*(\S+)', block)
            name = name_match.group(1) if name_match else 'Unknown'

            # 提取公钥
            pubkey_match = re.search(r'PublicKey\s*=\s*([^\s]+)', block)
            if not pubkey_match:
                continue
            pubkey = pubkey_match.group(1)

            # 提取 IP
            ip_match = re.search(r'AllowedIPs\s*=\s*([^\s]+)', block)
            ip = ip_match.group(1).replace('/32', '') if ip_match else 'N/A'

            # 从 wg show 中获取连接状态
            peer_pattern = f'peer: {re.escape(pubkey)}(.*?)(?=peer:|$)'
            peer_info = re.search(peer_pattern, wg_output, re.DOTALL)

            status = 'offline'
            last_handshake = 'Never'
            transfer_rx = '0 B'
            transfer_tx = '0 B'

            if peer_info:
                peer_data = peer_info.group(1)

                # 检查最后握手时间
                handshake_match = re.search(r'latest handshake:\s*(.+)', peer_data)
                if handshake_match:
                    last_handshake = handshake_match.group(1).strip()
                    status = 'online' if 'second' in last_handshake or 'minute' in last_handshake else 'offline'

                # 传输数据
                rx_match = re.search(r'transfer:\s*([^\s]+)\s+received', peer_data)
                tx_match = re.search(r'received,\s*([^\s]+)\s+sent', peer_data)
                if rx_match:
                    transfer_rx = rx_match.group(1)
                if tx_match:
                    transfer_tx = tx_match.group(1)

            clients.append({
                'name': name,
                'public_key': pubkey,
                'ip': ip,
                'status': status,
                'last_handshake': last_handshake,
                'transfer_rx': transfer_rx,
                'transfer_tx': transfer_tx
            })

        return clients
    except Exception as e:
        return []


def generate_qrcode(config_text):
    """生成二维码"""
    try:
        # 创建临时文件
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as f:
            f.write(config_text)
            temp_file = f.name

        # 生成二维码到临时文件
        png_file = temp_file + '.png'
        result = run_command(f'qrencode -o {png_file} < {temp_file}')

        if result['success'] and os.path.exists(png_file):
            with open(png_file, 'rb') as f:
                qr_data = base64.b64encode(f.read()).decode()

            # 清理临时文件
            os.unlink(temp_file)
            os.unlink(png_file)

            return qr_data
        else:
            os.unlink(temp_file)
            return None
    except Exception as e:
        return None


@app.route('/')
def index():
    """主页"""
    return render_template('index.html')


@app.route('/api/status')
def api_status():
    """获取服务器状态"""
    server_info = get_server_info()
    clients = get_clients()

    return jsonify({
        'server': server_info,
        'clients': clients,
        'client_count': len(clients),
        'online_count': len([c for c in clients if c['status'] == 'online'])
    })


@app.route('/api/clients')
def api_clients():
    """获取客户端列表"""
    clients = get_clients()
    return jsonify({'clients': clients})


@app.route('/api/client/add', methods=['POST'])
def api_add_client():
    """添加新客户端"""
    try:
        data = request.json
        client_name = data.get('name', '').strip()

        if not client_name:
            return jsonify({'success': False, 'error': 'Client name is required'})

        # 清理客户端名称
        client_name = re.sub(r'[^a-zA-Z0-9_-]', '', client_name)

        # 获取服务器信息
        server_info = get_server_info()
        config_result = run_command(f'cat {WG_CONF}')
        if not config_result['success']:
            return jsonify({'success': False, 'error': 'Cannot read config'})

        config = config_result['stdout']

        # 获取 VPN 网段
        address_match = re.search(r'Address\s*=\s*(\d+\.\d+\.\d+)\.\d+', config)
        if not address_match:
            return jsonify({'success': False, 'error': 'Cannot determine VPN subnet'})

        subnet = address_match.group(1)

        # 查找可用 IP
        used_ips = re.findall(r'AllowedIPs\s*=\s*' + re.escape(subnet) + r'\.(\d+)/32', config)
        used_ips = [int(ip) for ip in used_ips]

        next_ip = 2
        while next_ip in used_ips:
            next_ip += 1

        client_ip = f"{subnet}.{next_ip}"

        # 创建客户端目录
        run_command(f'mkdir -p {CLIENT_DIR}')

        # 生成密钥
        private_key_result = run_command('wg genkey')
        if not private_key_result['success']:
            return jsonify({'success': False, 'error': 'Failed to generate private key'})

        private_key = private_key_result['stdout'].strip()

        # 生成公钥
        public_key_result = run_command(f'echo "{private_key}" | wg pubkey', use_sudo=False)
        if not public_key_result['success']:
            return jsonify({'success': False, 'error': 'Failed to generate public key'})

        public_key = public_key_result['stdout'].strip()

        # 保存密钥
        run_command(f'echo "{private_key}" > {CLIENT_DIR}/{client_name}_private.key')
        run_command(f'echo "{public_key}" > {CLIENT_DIR}/{client_name}_public.key')
        run_command(f'chmod 600 {CLIENT_DIR}/{client_name}_private.key')

        # 获取服务器公钥
        server_private_key_result = run_command(f"grep '^PrivateKey' {WG_CONF} | awk '{{print $3}}'")
        if server_private_key_result['success']:
            server_private_key = server_private_key_result['stdout'].strip()
            server_public_key_result = run_command(f'echo "{server_private_key}" | wg pubkey', use_sudo=False)
            server_public_key = server_public_key_result['stdout'].strip()
        else:
            return jsonify({'success': False, 'error': 'Cannot get server public key'})

        # 添加 Peer 到服务器配置
        peer_config = f'''
# 客户端: {client_name}
[Peer]
PublicKey = {public_key}
AllowedIPs = {client_ip}/32
'''

        # 备份配置
        run_command(f'cp {WG_CONF} {WG_CONF}.backup.$(date +%Y%m%d_%H%M%S)')

        # 追加配置
        run_command(f"echo '{peer_config}' >> {WG_CONF}")

        # 生成客户端配置
        client_config = f'''[Interface]
PrivateKey = {private_key}
Address = {client_ip}/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = {server_public_key}
Endpoint = {server_info['public_ip']}:{server_info['listen_port']}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
'''

        # 保存客户端配置
        run_command(f"echo '{client_config}' > {CLIENT_DIR}/{client_name}.conf")
        run_command(f'chmod 600 {CLIENT_DIR}/{client_name}.conf')

        # 重新加载配置
        run_command(f'wg syncconf {WG_INTERFACE} <(wg-quick strip {WG_INTERFACE})')

        return jsonify({
            'success': True,
            'client': {
                'name': client_name,
                'ip': client_ip,
                'public_key': public_key
            }
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/client/<client_name>/config')
def api_client_config(client_name):
    """获取客户端配置"""
    try:
        # 清理客户端名称
        client_name = re.sub(r'[^a-zA-Z0-9_-]', '', client_name)

        config_file = f"{CLIENT_DIR}/{client_name}.conf"
        result = run_command(f'cat {config_file}')

        if not result['success']:
            return jsonify({'success': False, 'error': 'Config not found'})

        config_text = result['stdout']
        qr_code = generate_qrcode(config_text)

        return jsonify({
            'success': True,
            'config': config_text,
            'qrcode': qr_code
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


@app.route('/api/client/<client_name>/delete', methods=['POST'])
def api_delete_client(client_name):
    """删除客户端"""
    try:
        # 清理客户端名称
        client_name = re.sub(r'[^a-zA-Z0-9_-]', '', client_name)

        # 读取配置
        config_result = run_command(f'cat {WG_CONF}')
        if not config_result['success']:
            return jsonify({'success': False, 'error': 'Cannot read config'})

        config = config_result['stdout']

        # 查找并删除客户端配置块
        pattern = rf'# 客户端: {re.escape(client_name)}.*?\[Peer\].*?(?=# 客户端:|$)'
        new_config = re.sub(pattern, '', config, flags=re.DOTALL)

        # 备份配置
        run_command(f'cp {WG_CONF} {WG_CONF}.backup.$(date +%Y%m%d_%H%M%S)')

        # 写入新配置
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(new_config)
            temp_file = f.name

        run_command(f'cp {temp_file} {WG_CONF}')
        os.unlink(temp_file)

        # 删除客户端文件
        run_command(f'rm -f {CLIENT_DIR}/{client_name}*')

        # 重新加载配置
        run_command(f'wg syncconf {WG_INTERFACE} <(wg-quick strip {WG_INTERFACE})')

        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


if __name__ == '__main__':
    # 确保客户端目录存在
    os.makedirs(CLIENT_DIR, exist_ok=True)

    # 启动 Flask 应用
    app.run(host='0.0.0.0', port=8080, debug=False)
