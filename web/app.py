#!/usr/bin/env python3
"""
WireGuard Web 管理界面 - Flask 后端
"""

from flask import Flask, render_template, jsonify, request, send_file, redirect, url_for, flash, session
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from flask_wtf.csrf import CSRFProtect
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import subprocess
import os
import re
import json
from datetime import datetime
import tempfile
import base64
from io import BytesIO
import bcrypt
from functools import wraps

app = Flask(__name__)

# 安全配置
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', os.urandom(24).hex())
app.config['PERMANENT_SESSION_LIFETIME'] = 3600  # 会话1小时后过期
app.config['WTF_CSRF_TIME_LIMIT'] = None  # CSRF令牌不过期（由会话控制）
app.config['WTF_CSRF_SSL_STRICT'] = False  # 允许非HTTPS环境（生产环境应使用HTTPS）

# CSRF 保护
csrf = CSRFProtect(app)

# 速率限制
limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://"
)

# Flask-Login 配置
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'
login_manager.login_message = '请先登录以访问此页面'

# 配置
WG_INTERFACE = "wg0"
WG_DIR = "/etc/wireguard"
WG_CONF = f"{WG_DIR}/{WG_INTERFACE}.conf"
CLIENT_DIR = f"{WG_DIR}/clients"

# 用户数据存储
USERS_FILE = f"{WG_DIR}/users.json"

# 流量数据存储
TRAFFIC_FILE = f"{WG_DIR}/traffic.json"

# 用户模型
class User(UserMixin):
    def __init__(self, username, password_hash=None):
        self.id = username
        self.username = username
        self.password_hash = password_hash

    def check_password(self, password):
        """验证密码"""
        if not self.password_hash:
            return False
        return bcrypt.checkpw(password.encode('utf-8'), self.password_hash.encode('utf-8'))

    @staticmethod
    def hash_password(password):
        """生成密码哈希"""
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    @staticmethod
    def validate_password(password):
        """
        验证密码强度
        要求：
        - 最少8个字符
        - 至少包含一个大写字母
        - 至少包含一个小写字母
        - 至少包含一个数字
        - 至少包含一个特殊字符
        """
        if len(password) < 8:
            return False, "密码长度至少为8个字符"

        if not re.search(r'[A-Z]', password):
            return False, "密码必须包含至少一个大写字母"

        if not re.search(r'[a-z]', password):
            return False, "密码必须包含至少一个小写字母"

        if not re.search(r'\d', password):
            return False, "密码必须包含至少一个数字"

        if not re.search(r'[!@#$%^&*()_+\-=\[\]{};:\'",.<>?/\\|`~]', password):
            return False, "密码必须包含至少一个特殊字符 (!@#$%^&* 等)"

        return True, "密码符合要求"


# 用户数据管理
def load_users():
    """加载用户数据"""
    try:
        if os.path.exists(USERS_FILE):
            result = run_command(['cat', USERS_FILE], use_sudo=False)
            if not result['success']:
                result = run_command(['cat', USERS_FILE])
            if result['success']:
                return json.loads(result['stdout'])
        return {}
    except Exception as e:
        print(f"Error loading users: {e}")
        return {}


def save_users(users_data):
    """保存用户数据"""
    try:
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            json.dump(users_data, f, indent=2)
            temp_file = f.name

        run_command(['mkdir', '-p', WG_DIR])
        result = run_command(['cp', temp_file, USERS_FILE])
        run_command(['chmod', '600', USERS_FILE])
        os.unlink(temp_file)

        return result['success']
    except Exception as e:
        print(f"Error saving users: {e}")
        return False


def init_default_user():
    """初始化默认管理员用户"""
    users = load_users()

    # 如果没有用户，创建默认管理员
    if not users:
        default_username = os.environ.get('ADMIN_USERNAME', 'admin')
        default_password = os.environ.get('ADMIN_PASSWORD')

        # 要求必须通过环境变量设置强密码
        if not default_password:
            print("❌ 错误: 必须通过环境变量 ADMIN_PASSWORD 设置管理员密码")
            print("   密码要求:")
            print("   - 最少8个字符")
            print("   - 至少包含一个大写字母")
            print("   - 至少包含一个小写字母")
            print("   - 至少包含一个数字")
            print("   - 至少包含一个特殊字符 (!@#$%^&* 等)")
            print("\n   示例: export ADMIN_PASSWORD='MyP@ssw0rd!'")
            raise ValueError("未设置 ADMIN_PASSWORD 环境变量")

        # 验证密码强度
        is_valid, message = User.validate_password(default_password)
        if not is_valid:
            print(f"❌ 错误: 密码不符合安全要求 - {message}")
            print("   密码要求:")
            print("   - 最少8个字符")
            print("   - 至少包含一个大写字母")
            print("   - 至少包含一个小写字母")
            print("   - 至少包含一个数字")
            print("   - 至少包含一个特殊字符 (!@#$%^&* 等)")
            raise ValueError(f"密码不符合安全要求: {message}")

        users[default_username] = {
            'username': default_username,
            'password_hash': User.hash_password(default_password)
        }

        if save_users(users):
            print(f"✅ 默认管理员账户已创建: {default_username}")
            print(f"✅ 密码已设置并符合安全要求")
        else:
            print("❌ 创建默认用户失败")
            raise RuntimeError("无法保存用户数据")

    return users


# 流量数据管理
def load_traffic_data():
    """加载流量数据"""
    try:
        if os.path.exists(TRAFFIC_FILE):
            result = run_command(['cat', TRAFFIC_FILE], use_sudo=False)
            if not result['success']:
                result = run_command(['cat', TRAFFIC_FILE])
            if result['success']:
                return json.loads(result['stdout'])
        return {}
    except Exception as e:
        print(f"Error loading traffic data: {e}")
        return {}


def save_traffic_data(traffic_data):
    """保存流量数据"""
    try:
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            json.dump(traffic_data, f, indent=2)
            temp_file = f.name

        run_command(['mkdir', '-p', WG_DIR])
        result = run_command(['cp', temp_file, TRAFFIC_FILE])
        run_command(['chmod', '600', TRAFFIC_FILE])
        os.unlink(temp_file)

        return result['success']
    except Exception as e:
        print(f"Error saving traffic data: {e}")
        return False


def parse_transfer_size(size_str):
    """将流量字符串转换为字节数（支持二进制和十进制单位）"""
    if not size_str or size_str == '0 B':
        return 0

    # 二进制单位（1024为基数）
    binary_units = {
        'B': 1,
        'KiB': 1024,
        'MiB': 1024**2,
        'GiB': 1024**3,
        'TiB': 1024**4
    }

    # 十进制单位（1000为基数）
    decimal_units = {
        'B': 1,
        'KB': 1000,
        'MB': 1000**2,
        'GB': 1000**3,
        'TB': 1000**4
    }

    match = re.match(r'([\d.]+)\s*(\w+)', size_str)
    if match:
        value = float(match.group(1))
        unit = match.group(2)
        # 优先匹配二进制单位，然后匹配十进制单位
        multiplier = binary_units.get(unit) or decimal_units.get(unit, 1)
        return int(value * multiplier)
    return 0


def format_bytes(bytes_value):
    """将字节数转换为十进制单位（MB, GB, TB）"""
    if bytes_value == 0:
        return '0 B'

    units = ['B', 'KB', 'MB', 'GB', 'TB']
    unit_index = 0
    value = float(bytes_value)

    # 使用1000为基数（十进制）
    while value >= 1000 and unit_index < len(units) - 1:
        value /= 1000
        unit_index += 1

    # 格式化输出
    if value >= 100:
        return f'{value:.1f} {units[unit_index]}'
    elif value >= 10:
        return f'{value:.2f} {units[unit_index]}'
    else:
        return f'{value:.2f} {units[unit_index]}'


@login_manager.user_loader
def load_user(username):
    """Flask-Login 用户加载回调"""
    users = load_users()
    if username in users:
        user_data = users[username]
        return User(user_data['username'], user_data['password_hash'])
    return None


def run_command(cmd, use_sudo=True, shell=False):
    """
    执行命令并返回结果

    Args:
        cmd: 命令列表 (推荐) 或字符串 (仅用于需要shell的复杂命令)
        use_sudo: 是否使用sudo
        shell: 是否使用shell (仅在必要时使用)

    Returns:
        dict: 包含success, stdout, stderr, returncode的字典
    """
    try:
        # 如果是字符串且不需要shell，转换为列表
        if isinstance(cmd, str) and not shell:
            cmd = cmd.split()

        # 如果需要sudo且cmd是列表
        if use_sudo and isinstance(cmd, list):
            if cmd[0] != 'sudo':
                cmd = ['sudo'] + cmd
        elif use_sudo and isinstance(cmd, str):
            if not cmd.startswith('sudo'):
                cmd = f'sudo {cmd}'

        result = subprocess.run(
            cmd,
            shell=shell,
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
        result = run_command(['cat', WG_CONF], use_sudo=False)
        if not result['success']:
            print(f"DEBUG: Non-sudo read failed: {result.get('stderr', 'No error message')}")
            # 尝试使用 sudo 读取
            result = run_command(['cat', WG_CONF])
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

        # 获取公网 IP (这个命令需要shell来处理管道和命令替换)
        public_ip_cmd = run_command(
            "ip addr show $(ip route | grep default | awk '{print $5}' | head -n1) | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1",
            use_sudo=False,
            shell=True
        )
        server_info['public_ip'] = public_ip_cmd['stdout'].strip() if public_ip_cmd['success'] else 'N/A'

        # 获取服务状态
        status_cmd = run_command(['wg', 'show', WG_INTERFACE], use_sudo=False)
        server_info['status'] = 'active' if status_cmd['success'] else 'inactive'

        print(f"DEBUG: Successfully read config, server_info: {server_info}")
        return server_info
    except Exception as e:
        print(f"DEBUG: Exception in get_server_info: {e}")
        return {'error': str(e)}


def _parse_peer_data(peer_data, wg_output, traffic_data):
    """
    解析单个peer块的数据（包括前置注释）

    Args:
        peer_data: 包含注释和peer内容的完整文本块
        wg_output: wg show命令的输出，用于获取连接状态
        traffic_data: 流量数据字典（会被修改）

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
        rx_match = re.search(r'transfer:\s*([\d.]+\s+\w+)\s+received', peer_data_status)
        tx_match = re.search(r'received,\s*([\d.]+\s+\w+)\s+sent', peer_data_status)
        if rx_match:
            transfer_rx = rx_match.group(1)
        if tx_match:
            transfer_tx = tx_match.group(1)

    # 流量持久化和累计计算
    # 注意：traffic_data 作为参数传入，不再在这里加载

    # 解析当前流量为字节数
    current_rx_bytes = parse_transfer_size(transfer_rx)
    current_tx_bytes = parse_transfer_size(transfer_tx)

    # 获取或初始化该客户端的流量记录
    if name not in traffic_data:
        traffic_data[name] = {
            'accumulated_rx': 0,
            'accumulated_tx': 0,
            'last_rx': 0,
            'last_tx': 0,
            'last_update': datetime.now().isoformat()
        }

    client_traffic = traffic_data[name]

    # 检测流量重置（当前流量小于上次记录的流量）
    # 这通常发生在系统重启或 WireGuard 接口重启时
    if current_rx_bytes < client_traffic['last_rx']:
        # 发生重置，将上次的流量值累加到累计值中
        client_traffic['accumulated_rx'] += client_traffic['last_rx']

    if current_tx_bytes < client_traffic['last_tx']:
        # 发生重置，将上次的流量值累加到累计值中
        client_traffic['accumulated_tx'] += client_traffic['last_tx']

    # 计算总流量（累计 + 当前）
    total_rx_bytes = client_traffic['accumulated_rx'] + current_rx_bytes
    total_tx_bytes = client_traffic['accumulated_tx'] + current_tx_bytes
    total_bytes = total_rx_bytes + total_tx_bytes

    # 更新记录
    client_traffic['last_rx'] = current_rx_bytes
    client_traffic['last_tx'] = current_tx_bytes
    client_traffic['last_update'] = datetime.now().isoformat()

    # 更新 traffic_data（引用传递，会修改外部的字典）
    traffic_data[name] = client_traffic

    # 格式化总流量（使用十进制单位）
    transfer_total = format_bytes(total_bytes)

    return {
        'name': name,
        'public_key': pubkey,
        'ip': ip,
        'status': status,
        'last_handshake': last_handshake,
        'transfer_rx': transfer_rx,
        'transfer_tx': transfer_tx,
        'transfer_total': transfer_total
    }


def get_clients():
    """获取所有客户端信息"""
    try:
        # 检查配置文件是否存在
        if not os.path.exists(WG_CONF):
            return []

        # 读取配置文件
        result = run_command(['cat', WG_CONF], use_sudo=False)
        if not result['success']:
            # 尝试使用 sudo 读取
            result = run_command(['cat', WG_CONF])
            if not result['success']:
                return []

        config = result['stdout']

        # 检查是否是占位符配置
        if 'placeholder' in config:
            return []

        # 获取 wg show 输出（包含连接状态）
        wg_show = run_command(['wg', 'show', WG_INTERFACE], use_sudo=False)
        wg_output = wg_show['stdout'] if wg_show['success'] else ''

        # 加载流量数据（整个函数只加载一次）
        traffic_data = load_traffic_data()

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
                    client = _parse_peer_data(peer_data, wg_output, traffic_data)
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
                # 检查是否是 Peer 的注释（用于识别客户端名称）
                if stripped.startswith('#'):
                    # 检查是否是客户端注释格式
                    if (re.search(r'#\s*客户端[：:]', stripped) or
                        re.search(r'#\s*[Cc]lient\s*:', stripped) or
                        (re.search(r'^#\s*[a-zA-Z0-9_-]+\s*$', stripped) and
                         not any(keyword in stripped for keyword in ['服务端', '监听', '启动', '关闭', 'Interface', 'Server']))):
                        # 这是一个 Peer 的注释，结束 Interface 块
                        in_interface = False
                        peer_comment_lines.append(line)
                    # 否则忽略（Interface 块内的注释）
                else:
                    pass  # 忽略 Interface 块的其他内容

            # 在peer块中
            elif in_peer:
                # 检查是否是下一个 Peer 的注释
                if stripped.startswith('#'):
                    # 检查是否是客户端注释格式
                    if (re.search(r'#\s*客户端[：:]', stripped) or
                        re.search(r'#\s*[Cc]lient\s*:', stripped) or
                        (re.search(r'^#\s*[a-zA-Z0-9_-]+\s*$', stripped) and
                         not any(keyword in stripped for keyword in ['服务端', '监听', '启动', '关闭', 'Interface', 'Server']))):
                        # 这是下一个 Peer 的注释，结束当前 peer
                        if peer_content_lines:
                            # 处理当前peer
                            peer_data = '\n'.join(peer_comment_lines + peer_content_lines)
                            client = _parse_peer_data(peer_data, wg_output, traffic_data)
                            if client:
                                clients.append(client)

                        # 开始收集新的注释
                        in_peer = False
                        peer_comment_lines = [line]
                        peer_content_lines = []
                    else:
                        # peer 内部的注释，添加到内容中
                        peer_content_lines.append(line)
                else:
                    # peer 的配置行
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
            client = _parse_peer_data(peer_data, wg_output, traffic_data)
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

        # 保存流量数据（整个函数只保存一次）
        save_traffic_data(traffic_data)

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

        # 生成二维码到临时文件 (需要shell进行输入重定向)
        png_file = temp_file + '.png'
        result = run_command(f'qrencode -o {png_file} < {temp_file}', shell=True)

        if result['success'] and os.path.exists(png_file):
            with open(png_file, 'rb') as f:
                qr_data = base64.b64encode(f.read()).decode()

            # 清理临时文件
            os.unlink(temp_file)
            os.unlink(png_file)

            return qr_data
        else:
            if os.path.exists(temp_file):
                os.unlink(temp_file)
            return None
    except Exception as e:
        return None


@app.route('/login', methods=['GET', 'POST'])
@limiter.limit("5 per minute")  # 限制登录尝试：每分钟最多5次
def login():
    """登录页面"""
    # 如果已登录，重定向到主页
    if current_user.is_authenticated:
        return redirect(url_for('index'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')

        if not username or not password:
            flash('请输入用户名和密码', 'error')
            return render_template('login.html')

        users = load_users()
        if username in users:
            user_data = users[username]
            user = User(user_data['username'], user_data['password_hash'])

            if user.check_password(password):
                login_user(user, remember=True)
                flash('登录成功！', 'success')

                # 重定向到原始请求页面或主页
                next_page = request.args.get('next')
                return redirect(next_page) if next_page else redirect(url_for('index'))
            else:
                flash('用户名或密码错误', 'error')
        else:
            flash('用户名或密码错误', 'error')

    return render_template('login.html')


@app.route('/logout')
@login_required
def logout():
    """注销"""
    logout_user()
    flash('已成功注销', 'success')
    return redirect(url_for('login'))


@app.route('/')
@login_required
def index():
    """主页"""
    return render_template('index.html')


@app.route('/api/status')
@login_required
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
@login_required
def api_clients():
    """获取客户端列表"""
    clients = get_clients()
    return jsonify({'clients': clients})


@app.route('/api/client/add', methods=['POST'])
@login_required
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
        config_result = run_command(['cat', WG_CONF])
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
        run_command(['mkdir', '-p', CLIENT_DIR])

        # 生成密钥
        private_key_result = run_command(['wg', 'genkey'])
        if not private_key_result['success']:
            return jsonify({'success': False, 'error': 'Failed to generate private key'})

        private_key = private_key_result['stdout'].strip()

        # 生成公钥 (需要shell来处理管道)
        public_key_result = run_command(f'echo "{private_key}" | wg pubkey', use_sudo=False, shell=True)
        if not public_key_result['success']:
            return jsonify({'success': False, 'error': 'Failed to generate public key'})

        public_key = public_key_result['stdout'].strip()

        # 保存密钥 - 使用Python文件操作代替echo命令
        private_key_file = os.path.join(CLIENT_DIR, f'{client_name}_private.key')
        public_key_file = os.path.join(CLIENT_DIR, f'{client_name}_public.key')

        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(private_key)
            temp_priv = f.name
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(public_key)
            temp_pub = f.name

        run_command(['cp', temp_priv, private_key_file])
        run_command(['cp', temp_pub, public_key_file])
        run_command(['chmod', '600', private_key_file])

        os.unlink(temp_priv)
        os.unlink(temp_pub)

        # 获取服务器公钥 (需要shell来处理grep和awk管道)
        server_private_key_result = run_command(f"grep '^PrivateKey' {WG_CONF} | awk '{{print $3}}'", shell=True)
        if server_private_key_result['success']:
            server_private_key = server_private_key_result['stdout'].strip()
            # 使用shell管道生成公钥
            server_public_key_result = run_command(f'echo "{server_private_key}" | wg pubkey', use_sudo=False, shell=True)
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

        # 备份配置 (需要shell来处理date命令替换)
        backup_name = f'{WG_CONF}.backup.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
        run_command(['cp', WG_CONF, backup_name])

        # 追加配置 - 使用临时文件而不是echo，避免shell解释问题
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as peer_f:
            peer_f.write(peer_config)
            peer_temp = peer_f.name

        # 使用shell重定向来追加内容
        run_command(f'cat {peer_temp} >> {WG_CONF}', shell=True)
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

        client_conf_path = os.path.join(CLIENT_DIR, f'{client_name}.conf')
        run_command(['cp', client_temp, client_conf_path])
        os.unlink(client_temp)
        run_command(['chmod', '600', client_conf_path])

        # 重新加载配置 - 使用两步法代替进程替换
        strip_result = run_command(['wg-quick', 'strip', WG_INTERFACE])
        if strip_result['success']:
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.conf') as strip_f:
                strip_f.write(strip_result['stdout'])
                strip_file = strip_f.name
            run_command(['wg', 'syncconf', WG_INTERFACE, strip_file])
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
@login_required
def api_client_config(client_name):
    """获取客户端配置"""
    try:
        # 清理客户端名称
        client_name = re.sub(r'[^a-zA-Z0-9_-]', '', client_name)

        # 验证路径以防止路径遍历攻击
        config_file = os.path.join(CLIENT_DIR, f"{client_name}.conf")
        config_file = os.path.normpath(config_file)

        # 确保文件在CLIENT_DIR中
        if not config_file.startswith(os.path.normpath(CLIENT_DIR)):
            return jsonify({'success': False, 'error': 'Invalid client name'})

        result = run_command(['cat', config_file])

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
@login_required
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
        config_result = run_command(['cat', WG_CONF])
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
                # 检查是否是 Peer 的注释（用于识别客户端名称）
                if stripped.startswith('#'):
                    # 检查是否是客户端注释格式
                    if (re.search(r'#\s*客户端[：:]', stripped) or
                        re.search(r'#\s*[Cc]lient\s*:', stripped) or
                        (re.search(r'^#\s*[a-zA-Z0-9_-]+\s*$', stripped) and
                         not any(keyword in stripped for keyword in ['服务端', '监听', '启动', '关闭', 'Interface', 'Server']))):
                        # 这是一个 Peer 的注释，结束 Interface 块
                        in_interface = False
                        peer_comment_lines.append(line)
                    else:
                        # Interface 块内的注释，保留
                        new_lines.append(line)
                else:
                    # Interface 块的其他内容，保留
                    new_lines.append(line)

            # 在peer块中
            elif in_peer:
                # 检查是否是下一个 Peer 的注释
                if stripped.startswith('#'):
                    # 检查是否是客户端注释格式
                    if (re.search(r'#\s*客户端[：:]', stripped) or
                        re.search(r'#\s*[Cc]lient\s*:', stripped) or
                        (re.search(r'^#\s*[a-zA-Z0-9_-]+\s*$', stripped) and
                         not any(keyword in stripped for keyword in ['服务端', '监听', '启动', '关闭', 'Interface', 'Server']))):
                        # 这是下一个 Peer 的注释，结束当前 peer
                        if not skip_current_peer:
                            # 保存当前peer的注释和内容
                            new_lines.extend(peer_comment_lines)
                            new_lines.extend(peer_content_lines)

                        # 开始收集新的注释
                        in_peer = False
                        peer_comment_lines = [line]
                        peer_content_lines = []
                        skip_current_peer = False
                    else:
                        # peer 内部的注释，添加到内容中
                        peer_content_lines.append(line)
                else:
                    # peer 的配置行
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
        backup_name = f'{WG_CONF}.backup.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
        backup_result = run_command(['cp', WG_CONF, backup_name])
        if not backup_result['success']:
            return jsonify({'success': False, 'error': '无法创建配置备份'})

        # 写入新配置
        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(new_config)
            temp_file = f.name

        copy_result = run_command(['cp', temp_file, WG_CONF])
        os.unlink(temp_file)

        if not copy_result['success']:
            return jsonify({'success': False, 'error': '无法写入新配置'})

        # 删除客户端文件（仅在客户端名称有效时）
        if len(client_name) > 0:
            # 使用shell通配符来删除相关文件
            client_pattern = os.path.join(CLIENT_DIR, f'{client_name}*')
            run_command(f'rm -f {client_pattern}', shell=True)
            # 对于Unknown-XXXXX格式，也删除可能的原始文件
            if client_name.startswith('Unknown-'):
                suffix_pattern = os.path.join(CLIENT_DIR, f'*{client_name.split("-")[1]}*')
                run_command(f'rm -f {suffix_pattern}', shell=True)

        # 重新加载配置并检查结果
        # 使用两步法代替进程替换，更兼容
        strip_result = run_command(['wg-quick', 'strip', WG_INTERFACE])
        if strip_result['success']:
            # 将strip结果写入临时文件
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.conf') as strip_f:
                strip_f.write(strip_result['stdout'])
                strip_file = strip_f.name

            # 使用临时文件进行syncconf
            reload_result = run_command(['wg', 'syncconf', WG_INTERFACE, strip_file])
            os.unlink(strip_file)

            if not reload_result['success']:
                # 如果重新加载失败，尝试恢复最新备份 (需要shell来处理管道)
                run_command(f'ls -t {WG_CONF}.backup.* | head -1 | xargs -I {{}} cp {{}} {WG_CONF}', shell=True)
                return jsonify({'success': False, 'error': f'WireGuard配置重新加载失败: {reload_result.get("stderr", "未知错误")}，已恢复备份'})
        else:
            # strip失败，恢复备份 (需要shell来处理管道)
            run_command(f'ls -t {WG_CONF}.backup.* | head -1 | xargs -I {{}} cp {{}} {WG_CONF}', shell=True)
            return jsonify({'success': False, 'error': f'配置验证失败: {strip_result.get("stderr", "未知错误")}，已恢复备份'})

        # 删除流量记录
        traffic_data = load_traffic_data()
        if client_name in traffic_data:
            del traffic_data[client_name]
            save_traffic_data(traffic_data)

        return jsonify({
            'success': True,
            'message': f'客户端 "{original_client_name}" 已成功删除'
        })

    except Exception as e:
        return jsonify({'success': False, 'error': f'删除过程中发生错误: {str(e)}'})


@app.route('/api/debug/config', methods=['GET'])
@login_required
def api_debug_config():
    """调试接口：查看配置文件结构"""
    try:
        # 读取配置文件
        config_result = run_command(['cat', WG_CONF])
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
    # 确保必要目录存在
    os.makedirs(CLIENT_DIR, exist_ok=True)

    # 初始化默认用户
    init_default_user()

    # 启动 Flask 应用
    print("\n" + "="*50)
    print("🔒 WireGuard Web 管理面板")
    print("="*50)
    print(f"访问地址: http://0.0.0.0:8080")
    print(f"默认用户名: {os.environ.get('ADMIN_USERNAME', 'admin')}")
    if not os.environ.get('ADMIN_PASSWORD'):
        print(f"默认密码: admin123")
        print("⚠️  请在生产环境中修改默认密码！")
    print("="*50 + "\n")

    app.run(host='0.0.0.0', port=8080, debug=False)
