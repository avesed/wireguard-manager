# WireGuard Manager

🔒 基于 Docker 的 WireGuard VPN 管理工具，支持一键部署和Web管理界面。

## 🚀 快速开始

### 前提条件

- Docker 20.10+
- 公网IP地址
- Ubuntu 18.04+ / Debian 10+ / CentOS 8+ / RHEL 8+

### 一键部署

```bash
# 克隆项目
git clone https://github.com/avesed/wireguard-manager.git
cd wireguard-manager

# 一键部署（自动生成密码）
sudo bash docker-deploy.sh
```

部署完成后，登录凭据会显示在终端并保存到 `config/web-credentials.txt`

### 使用自定义密码部署（推荐）

```bash
# 设置环境变量
export ADMIN_USERNAME="admin"
export ADMIN_PASSWORD="your_strong_password"
export SECRET_KEY="$(openssl rand -hex 32)"

# 部署
sudo -E bash docker-deploy.sh
```

### 分步部署

```bash
# 1. 启动 WireGuard 容器
sudo bash start-wireguard.sh

# 2. 配置认证信息
export ADMIN_USERNAME="admin"
export ADMIN_PASSWORD="your_strong_password"
export SECRET_KEY="$(openssl rand -hex 32)"

# 3. 启动 Web 管理界面
sudo -E bash start-web.sh
```

## 🌐 访问Web界面

部署完成后访问：`http://YOUR_SERVER_IP:8080`

**默认凭据**：
- 用户名：`admin`
- 密码：部署时生成（查看终端或 `config/web-credentials.txt`）

## 🔧 管理命令

### 查看状态

```bash
# 查看容器
docker ps

# 查看日志
docker logs -f wireguard-vpn       # WireGuard
docker logs -f wireguard-web-ui     # Web界面
```

### 重启服务

```bash
# 重启Web界面
sudo docker restart wireguard-web-ui

# 重启WireGuard
sudo docker restart wireguard-vpn
```

### 修改密码

```bash
# 停止容器
sudo docker stop wireguard-web-ui

# 删除用户数据
sudo rm config/wireguard/users.json

# 设置新密码并重启
export ADMIN_PASSWORD="new_strong_password"
sudo -E bash start-web.sh
```

### 清理环境

```bash
sudo bash cleanup-wireguard.sh
```

## 🔐 安全建议

### 1. 使用强密码

- 至少12位字符
- 包含大小写字母、数字和特殊字符
- 不使用常见密码

生成强密码：
```bash
openssl rand -base64 16
```

### 2. 配置防火墙

```bash
# 限制Web界面访问IP
sudo ufw allow from YOUR_IP to any port 8080

# 允许WireGuard端口
sudo ufw allow 51820/udp

# 启用防火墙
sudo ufw enable
```

## 📂 配置文件

- **WireGuard配置**：`config/wireguard/wg0.conf`
- **客户端配置**：`config/wireguard/clients/`
- **用户数据**：`config/wireguard/users.json`
- **登录凭据**：`config/web-credentials.txt`

## 🔐 身份认证

### 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `ADMIN_USERNAME` | 管理员用户名 | `admin` |
| `ADMIN_PASSWORD` | 管理员密码 | 自动生成 |
| `SECRET_KEY` | Flask会话密钥 | 自动生成 |

### 使用.env文件配置

```bash
# 复制示例文件
cp .env.example .env

# 编辑配置
nano .env

# 加载环境变量并部署
source .env
sudo -E bash docker-deploy.sh
```

## 🐛 故障排除

### Web界面无法访问

```bash
# 检查容器状态
docker ps

# 查看日志
docker logs wireguard-web-ui

# 重启容器
sudo docker restart wireguard-web-ui
```

### 忘记密码

```bash
# 删除用户数据
sudo rm config/wireguard/users.json

# 重启容器
sudo docker restart wireguard-web-ui

# 查看新密码
sudo docker logs wireguard-web-ui | grep -A 5 "credentials"
```

### WireGuard连接失败

```bash
# 查看WireGuard状态
docker exec wireguard-vpn wg show

# 查看日志
docker logs wireguard-vpn

# 重启WireGuard
sudo docker restart wireguard-vpn
```

## 📚 详细文档

- **[Docker部署指南](DOCKER_DEPLOY.md)** - 完整的Docker部署说明
- **[身份认证说明](web/AUTH_README.md)** - 认证系统详细文档
- **[环境变量配置](.env.example)** - 配置示例文件

## 📋 系统要求

- Ubuntu 18.04+ / Debian 10+ / CentOS 8+ / RHEL 8+
- Docker 20.10+
- 最低配置：1核CPU、512MB内存、1GB存储
- 需要公网IP地址