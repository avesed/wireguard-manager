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
        # 检查配置文件是否存在
        if not os.path.exists(WG_CONF):
            print(f"DEBUG: Config file {WG_CONF} does not exist")
            return {'error': 'WireGuard configuration not found'}

        # 检查文件权限
        try:
            stat_info = os.stat(WG_CONF)
            print(f"DEBUG: Config file permissions: {oct(stat_info.st_mode)[-3:]}, owner: {stat_info.st_uid}:{stat_info.st_gid}")
        except Exception as e:
            print(f"DEBUG: Cannot stat config file: {e}")

        # 获取服务器配置
        result = run_command(f'cat {WG_CONF}', use_sudo=False)
        if not result['success']:
            print(f"DEBUG: Non-sudo read failed: {result.get('stderr', 'No error message')}")
            # 尝试使用 sudo 读取
            result = run_command(f'cat {WG_CONF}')
            if not result['success']:
                print(f"DEBUG: Sudo read also failed: {result.get('stderr', 'No error message')}")
                return {'error': 'Cannot read WireGuard config'}

        config = result['stdout']

        # 检查是否是占位符配置
        if 'placeholder' in config:
            print("DEBUG: Found placeholder configuration")
            return {'error': 'WireGuard not fully initialized yet'}

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
        status_cmd = run_command(f'wg show {WG_INTERFACE}', use_sudo=False)
        server_info['status'] = 'active' if status_cmd['success'] else 'inactive'

        print(f"DEBUG: Successfully read config, server_info: {server_info}")
        return server_info
    except Exception as e:
        print(f"DEBUG: Exception in get_server_info: {e}")
        return {'error': str(e)}


def _parse_peer_data(peer_data, wg_output):
    """
    解析单个peer块的数据（包括前置注释）

    Args:
        peer_data: 包含注释和peer内容的完整文本块
        wg_output: wg show命令的输出，用于获取连接状态

    Returns:
        dict: 客户端信息字典，如果解析失败返回None
    """
    # 提取客户端名称（从注释中）- 只使用精确匹配
    name_match = None

    # 1. 标准中文格式：# 客户端: name 或 # 客户端： name
    name_match = re.search(r'#\s*客户端[：:]\s*(\S+)', peer_data)

    # 2. 英文格式：# Client: name
    if not name_match:
        name_match = re.search(r'#\s*[Cc]lient\s*[：:]\s*(\S+)', peer_data)

    # 3. 简化格式：# name （但要确保不是关键词）
    if not name_match:
        simple_match = re.search(r'#\s*([a-zA-Z0-9_-]+)\s*$', peer_data, re.MULTILINE)
        if simple_match:
            candidate_name = simple_match.group(1)
            # 排除明显的关键词，避免误匹配
            excluded_words = ['Peer', 'peer', 'PublicKey', 'AllowedIPs', 'Endpoint', 'PersistentKeepalive']
            if candidate_name not in excluded_words and len(candidate_name) > 1:
                name_match = simple_match

    # 提取公钥
    pubkey_match = re.search(r'PublicKey\s*=\s*([^\s]+)', peer_data)
    if not pubkey_match:
        return None  # 无效的peer块
    pubkey = pubkey_match.group(1)

    # 对于真正无法识别的客户端，使用公钥后8位作为标识
    if name_match:
        name = name_match.group(1)
    else:
        # 使用URL安全的公钥后缀，去除特殊字符
        safe_suffix = pubkey.replace('+', '').replace('=', '').replace('/', '')[-8:]
        name = f'Unknown-{safe_suffix}'

    # 提取 IP
    ip_match = re.search(r'AllowedIPs\s*=\s*([^\s]+)', peer_data)
    ip = ip_match.group(1).replace('/32', '') if ip_match else 'N/A'

    # 从 wg show 中获取连接状态
    peer_pattern = f'peer: {re.escape(pubkey)}(.*?)(?=peer:|$)'
    peer_info = re.search(peer_pattern, wg_output, re.DOTALL)

    status = 'offline'
    last_handshake = 'Never'
    transfer_rx = '0 B'
    transfer_tx = '0 B'

    if peer_info:
        peer_data_status = peer_info.group(1)

        # 检查最后握手时间
        handshake_match = re.search(r'latest handshake:\s*(.+)', peer_data_status)
        if handshake_match:
            last_handshake = handshake_match.group(1).strip()
            status = 'online' if 'second' in last_handshake or 'minute' in last_handshake else 'offline'

        # 传输数据
        rx_match = re.search(r'transfer:\s*([^\s]+)\s+received', peer_data_status)
        tx_match = re.search(r'received,\s*([^\s]+)\s+sent', peer_data_status)
        if rx_match:
            transfer_rx = rx_match.group(1)
        if tx_match:
            transfer_tx = tx_match.group(1)

    return {
        'name': name,
        'public_key': pubkey,
        'ip': ip,
        'status': status,
        'last_handshake': last_handshake,
        'transfer_rx': transfer_rx,
        'transfer_tx': transfer_tx
    }


def get_clients():
    """获取所有客户端信息"""
    try:
        # 检查配置文件是否存在
        if not os.path.exists(WG_CONF):
            return []

        # 读取配置文件
        result = run_command(f'cat {WG_CONF}', use_sudo=False)
        if not result['success']:
            # 尝试使用 sudo 读取
            result = run_command(f'cat {WG_CONF}')
            if not result['success']:
                return []

        config = result['stdout']

        # 检查是否是占位符配置
        if 'placeholder' in config:
            return []

        # 获取 wg show 输出（包含连接状态）
        wg_show = run_command(f'wg show {WG_INTERFACE}', use_sudo=False)
        wg_output = wg_show['stdout'] if wg_show['success'] else ''

        clients = []

        # 使用状态机方法解析配置，正确捕获 [Peer] 之前的注释
        lines = config.split('\n')
        in_interface = False
        in_peer = False
        peer_comment_lines = []  # 当前peer前的注释行
        peer_content_lines = []  # 当前peer块的内容行

        for line in lines:
            stripped = line.strip()

            # 检测 [Interface]
            if stripped == '[Interface]':
                in_interface = True
                in_peer = False

            # 检测 [Peer]
            elif stripped == '[Peer]':
                # 保存之前的peer（如果存在）
                if in_peer and peer_content_lines:
                    # 处理上一个peer
                    peer_data = '\n'.join(peer_comment_lines + peer_content_lines)
                    client = _parse_peer_data(peer_data, wg_output)
                    if client:
                        clients.append(client)
                    # 重置注释列表，防止注释被关联到错误的peer
                    peer_comment_lines = []

                # 开始新的peer块
                in_interface = False
                in_peer = True
                peer_content_lines = [line]
                # peer_comment_lines 已经包含了之前收集的注释

            # 在interface块中
            elif in_interface:
                pass  # 忽略interface块的内容

            # 在peer块中
            elif in_peer:
                peer_content_lines.append(line)

            # 不在任何section中（可能是peer的注释或空行）
            else:
                if stripped.startswith('#'):
                    # 这是注释行，可能是下一个peer的注释
                    peer_comment_lines.append(line)
                elif not stripped:
                    # 空行
                    if peer_comment_lines:
                        # 如果之前有注释，这个空行属于注释部分
                        peer_comment_lines.append(line)
                # 其他行忽略

        # 处理最后一个peer块（如果存在）
        if in_peer and peer_content_lines:
            peer_data = '\n'.join(peer_comment_lines + peer_content_lines)
            client = _parse_peer_data(peer_data, wg_output)
            if client:
                clients.append(client)

        # 检测重复的公钥
        pubkey_count = {}
        for client in clients:
            pubkey = client['public_key']
            if pubkey in pubkey_count:
                pubkey_count[pubkey] += 1
            else:
                pubkey_count[pubkey] = 1

        # 标记重复的客户端
        for client in clients:
            pubkey = client['public_key']
            if pubkey_count[pubkey] > 1:
                client['is_duplicate'] = True
                client['duplicate_warning'] = f'⚠️ 此公钥有{pubkey_count[pubkey]}个重复'
            else:
                client['is_duplicate'] = False

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

        # 检查客户端名称是否已存在
        existing_clients = get_clients()
        for client in existing_clients:
            if client['name'] == client_name:
                return jsonify({
                    'success': False,
                    'error': f'客户端名称 "{client_name}" 已存在，请使用其他名称'
                })

        # 查找可用 IP
        used_ips = re.findall(r'AllowedIPs\s*=\s*' + re.escape(subnet) + r'\.(\d+)/32', config)
        used_ips = [int(ip) for ip in used_ips]

        # 提取所有已存在的公钥（用于重复检测）
        existing_pubkeys = re.findall(r'PublicKey\s*=\s*([^\s]+)', config)

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

        # 追加配置 - 使用临时文件而不是echo，避免shell解释问题
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as peer_f:
            peer_f.write(peer_config)
            peer_temp = peer_f.name

        run_command(f'cat {peer_temp} >> {WG_CONF}')
        os.unlink(peer_temp)

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

        # 保存客户端配置 - 使用临时文件
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as client_f:
            client_f.write(client_config)
            client_temp = client_f.name

        run_command(f'cp {client_temp} {CLIENT_DIR}/{client_name}.conf')
        os.unlink(client_temp)
        run_command(f'chmod 600 {CLIENT_DIR}/{client_name}.conf')

        # 重新加载配置 - 使用两步法代替进程替换
        strip_result = run_command(f'wg-quick strip {WG_INTERFACE}')
        if strip_result['success']:
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.conf') as strip_f:
                strip_f.write(strip_result['stdout'])
                strip_file = strip_f.name
            run_command(f'wg syncconf {WG_INTERFACE} {strip_file}')
            os.unlink(strip_file)

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
        original_client_name = client_name
        client_name = re.sub(r'[^a-zA-Z0-9_-]', '', client_name)

        # 验证客户端名称不为空
        if not client_name:
            return jsonify({'success': False, 'error': '客户端名称无效'})

        # 读取配置
        config_result = run_command(f'cat {WG_CONF}')
        if not config_result['success']:
            return jsonify({'success': False, 'error': '无法读取配置文件'})

        config = config_result['stdout']
        original_config = config

        # 使用安全的逐行解析方法删除peer块
        deletion_successful = False
        target_safe_suffix = None if not client_name.startswith('Unknown-') else client_name.split('-')[1]

        # 逐行安全解析 - 使用状态机
        lines = config.split('\n')
        new_lines = []

        # 状态跟踪
        in_interface = False
        in_peer = False
        peer_comment_lines = []  # 当前peer前的注释行
        peer_content_lines = []  # 当前peer块的内容行
        skip_current_peer = False

        for i, line in enumerate(lines):
            stripped = line.strip()

            # 检测 [Interface]
            if stripped == '[Interface]':
                in_interface = True
                in_peer = False
                new_lines.append(line)

            # 检测 [Peer]
            elif stripped == '[Peer]':
                # 保存之前的peer（如果不删除）
                if in_peer and not skip_current_peer:
                    # 保存上一个peer的注释和内容
                    new_lines.extend(peer_comment_lines)
                    new_lines.extend(peer_content_lines)
                    # ✅ 关键修复：重置注释列表，防止注释被关联到错误的peer
                    peer_comment_lines = []

                # 开始新的peer块
                in_interface = False
                in_peer = True
                # peer_comment_lines 保留给当前peer使用（之前收集的注释）
                peer_content_lines = [line]  # 从[Peer]行开始
                skip_current_peer = False

            # 在interface块中
            elif in_interface:
                new_lines.append(line)

            # 在peer块中
            elif in_peer:
                peer_content_lines.append(line)

                # 检测PublicKey行
                if 'PublicKey' in line and '=' in line and not skip_current_peer:
                    pubkey_match = re.search(r'PublicKey\s*=\s*([^\s]+)', line)
                    if pubkey_match:
                        pubkey = pubkey_match.group(1)

                        # 判断是否是要删除的目标
                        is_target = False

                        # 方法1：通过公钥后缀匹配（Unknown客户端）
                        if target_safe_suffix:
                            block_safe_suffix = pubkey.replace('+', '').replace('=', '').replace('/', '')[-8:]
                            if block_safe_suffix == target_safe_suffix:
                                is_target = True

                        # 方法2：通过注释中的名称匹配（命名客户端）
                        else:
                            comment_text = '\n'.join(peer_comment_lines)
                            if re.search(rf'#\s*客户端\s*[：:]\s*{re.escape(client_name)}\s*$', comment_text, re.MULTILINE):
                                is_target = True
                            elif re.search(rf'#\s*[Cc]lient\s*:\s*{re.escape(client_name)}\s*$', comment_text, re.MULTILINE):
                                is_target = True
                            elif re.search(rf'#\s*{re.escape(client_name)}\s*$', comment_text, re.MULTILINE):
                                is_target = True

                        if is_target:
                            skip_current_peer = True
                            deletion_successful = True
                            # 清空已收集的内容和注释
                            peer_content_lines = []
                            peer_comment_lines = []

            # 不在任何section中（可能是peer的注释或空行）
            else:
                if stripped.startswith('#'):
                    # 这是注释行，可能是下一个peer的注释
                    peer_comment_lines.append(line)
                elif not stripped:
                    # 空行
                    if peer_comment_lines:
                        # 如果之前有注释，这个空行属于注释部分
                        peer_comment_lines.append(line)
                    else:
                        # 否则直接添加
                        new_lines.append(line)
                else:
                    # 其他行
                    new_lines.append(line)

        # 处理最后一个peer块（如果存在且不删除）
        if in_peer and not skip_current_peer:
            new_lines.extend(peer_comment_lines)
            new_lines.extend(peer_content_lines)

        # 组装新配置
        new_config = '\n'.join(new_lines)

        # 清理多余的连续空行
        new_config = re.sub(r'\n\n\n+', '\n\n', new_config)

        # 如果所有模式都失败，返回错误
        if not deletion_successful:
            # 为调试提供更多信息
            debug_info = []
            peer_blocks = re.findall(r'\[Peer\](.*?)(?=\[Peer\]|$)', config, re.DOTALL)
            for i, block in enumerate(peer_blocks):
                pubkey_match = re.search(r'PublicKey\s*=\s*([^\s]+)', block)
                if pubkey_match:
                    pubkey = pubkey_match.group(1)
                    debug_info.append(f"Peer {i+1}: 公钥后8位={pubkey[-8:]}")

            error_msg = f'未找到客户端 "{original_client_name}"。'
            if debug_info:
                error_msg += f' 当前配置中的客户端: {", ".join(debug_info)}'

            return jsonify({
                'success': False,
                'error': error_msg
            })

        # 验证新配置的完整性
        if '[Interface]' not in new_config:
            return jsonify({
                'success': False,
                'error': '删除操作会破坏配置文件结构（缺少[Interface]），操作已取消'
            })

        # 验证配置文件基本结构
        validation_errors = []

        # 检查是否有必需的Interface配置项
        if 'PrivateKey' not in new_config:
            validation_errors.append('缺少PrivateKey')
        if 'Address' not in new_config:
            validation_errors.append('缺少Address')

        # 检查剩余的peer块是否完整
        remaining_peers = re.findall(r'\[Peer\](.*?)(?=\[Peer\]|$)', new_config, re.DOTALL)
        for i, peer in enumerate(remaining_peers):
            if 'PublicKey' not in peer:
                validation_errors.append(f'Peer {i+1} 缺少PublicKey')
            if 'AllowedIPs' not in peer:
                validation_errors.append(f'Peer {i+1} 缺少AllowedIPs')

        if validation_errors:
            return jsonify({
                'success': False,
                'error': f'删除后配置验证失败: {", ".join(validation_errors)}。操作已取消，配置未修改。'
            })

        # 备份配置
        backup_result = run_command(f'cp {WG_CONF} {WG_CONF}.backup.$(date +%Y%m%d_%H%M%S)')
        if not backup_result['success']:
            return jsonify({'success': False, 'error': '无法创建配置备份'})

        # 写入新配置
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(new_config)
            temp_file = f.name

        copy_result = run_command(f'cp {temp_file} {WG_CONF}')
        os.unlink(temp_file)

        if not copy_result['success']:
            return jsonify({'success': False, 'error': '无法写入新配置'})

        # 删除客户端文件（仅在客户端名称有效时）
        if len(client_name) > 0:
            run_command(f'rm -f {CLIENT_DIR}/{client_name}*')
            # 对于Unknown-XXXXX格式，也删除可能的原始文件
            if client_name.startswith('Unknown-'):
                run_command(f'rm -f {CLIENT_DIR}/*{client_name.split("-")[1]}*')

        # 重新加载配置并检查结果
        # 使用两步法代替进程替换，更兼容
        strip_result = run_command(f'wg-quick strip {WG_INTERFACE}')
        if strip_result['success']:
            # 将strip结果写入临时文件
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.conf') as strip_f:
                strip_f.write(strip_result['stdout'])
                strip_file = strip_f.name

            # 使用临时文件进行syncconf
            reload_result = run_command(f'wg syncconf {WG_INTERFACE} {strip_file}')
            os.unlink(strip_file)

            if not reload_result['success']:
                # 如果重新加载失败，尝试恢复最新备份
                run_command(f'ls -t {WG_CONF}.backup.* | head -1 | xargs -I {{}} cp {{}} {WG_CONF}')
                return jsonify({'success': False, 'error': f'WireGuard配置重新加载失败: {reload_result.get("stderr", "未知错误")}，已恢复备份'})
        else:
            # strip失败，恢复备份
            run_command(f'ls -t {WG_CONF}.backup.* | head -1 | xargs -I {{}} cp {{}} {WG_CONF}')
            return jsonify({'success': False, 'error': f'配置验证失败: {strip_result.get("stderr", "未知错误")}，已恢复备份'})

        return jsonify({
            'success': True,
            'message': f'客户端 "{original_client_name}" 已成功删除'
        })

    except Exception as e:
        return jsonify({'success': False, 'error': f'删除过程中发生错误: {str(e)}'})


@app.route('/api/debug/config', methods=['GET'])
def api_debug_config():
    """调试接口：查看配置文件结构"""
    try:
        # 读取配置文件
        config_result = run_command(f'cat {WG_CONF}')
        if not config_result['success']:
            return jsonify({'success': False, 'error': '无法读取配置文件'})

        config = config_result['stdout']

        # 解析peer块
        peer_blocks = re.findall(r'\[Peer\](.*?)(?=\[Peer\]|$)', config, re.DOTALL)

        debug_info = {
            'total_peers': len(peer_blocks),
            'peers': []
        }

        for i, block in enumerate(peer_blocks):
            peer_info = {
                'index': i + 1,
                'raw_block': block.strip(),
                'extracted_info': {}
            }

            # 尝试提取各种信息
            # 1. 标准中文格式
            name_match = re.search(r'#\s*客户端[：:]\s*(\S+)', block)
            if name_match:
                peer_info['extracted_info']['standard_chinese'] = name_match.group(1)

            # 2. 英文格式
            name_match = re.search(r'#\s*[Cc]lient\s*[：:]\s*(\S+)', block)
            if name_match:
                peer_info['extracted_info']['english'] = name_match.group(1)

            # 3. 简化格式
            simple_match = re.search(r'#\s*([a-zA-Z0-9_-]+)\s*$', block, re.MULTILINE)
            if simple_match:
                peer_info['extracted_info']['simple'] = simple_match.group(1)

            # 4. 公钥
            pubkey_match = re.search(r'PublicKey\s*=\s*([^\s]+)', block)
            if pubkey_match:
                pubkey = pubkey_match.group(1)
                peer_info['extracted_info']['public_key'] = pubkey
                peer_info['extracted_info']['public_key_suffix'] = pubkey[-8:]

            # 5. IP
            ip_match = re.search(r'AllowedIPs\s*=\s*([^\s]+)', block)
            if ip_match:
                peer_info['extracted_info']['allowed_ips'] = ip_match.group(1)

            debug_info['peers'].append(peer_info)

        return jsonify({'success': True, 'data': debug_info})

    except Exception as e:
        return jsonify({'success': False, 'error': f'调试过程中发生错误: {str(e)}'})


if __name__ == '__main__':
    # 确保客户端目录存在
    os.makedirs(CLIENT_DIR, exist_ok=True)

    # 启动 Flask 应用
    app.run(host='0.0.0.0', port=8080, debug=False)
