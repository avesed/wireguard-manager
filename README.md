# WireGuard 管理器

🔒 一个完整的 WireGuard VPN 服务器管理工具集，包含自动化安装、Web 管理界面和客户端管理功能。

## 🚀 快速开始

### 🐳 方式1：Docker 部署（推荐）

**最简单快速的部署方式，无需手动配置环境！**

```bash
# 1. 克隆项目
git clone https://github.com/your-repo/wireguard-manager.git
cd wireguard-manager

# 2. 一键部署
chmod +x docker-deploy.sh
sudo bash docker-deploy.sh

# 3. 访问管理界面
# http://YOUR_SERVER_IP:8080
```

**✅ Docker 部署优势：**
- ✨ 一键安装，自动配置
- 🔒 环境隔离，更安全
- 📦 易于备份和迁移
- 🔄 快速更新升级

📖 **详细文档：** [Docker 部署指南](DOCKER.md)

---

### 📜 方式2：传统脚本部署

#### 第一步：安装 WireGuard 服务端

```bash
# 进入项目目录
cd wireguard-manager

# 安装 WireGuard VPN 服务器
sudo bash scripts/install_wireguard.sh
```

#### 第二步：部署 Web 管理界面（可选）

```bash
# 一键部署 Web 管理界面
sudo bash deploy_wireguard_web.sh
```

**需要手动上传这两个文件到服务器：**
- `web/app.py` → `/opt/wireguard-web/app.py`
- `web/templates/index.html` → `/opt/wireguard-web/templates/index.html`

#### 第三步：管理客户端

#### 命令行方式
```bash
# 添加新客户端
sudo bash scripts/add_wireguard_client.sh
```

#### Web 界面方式
访问 `http://您的服务器IP:8080` 使用图形界面管理

## 📋 功能特性

### 🔧 核心脚本功能

#### ✅ 安装脚本 (`scripts/install_wireguard.sh`)
- 自动检测网络配置
- 一键安装 WireGuard
- 自动生成服务端和客户端配置
- 配置防火墙和 IP 转发
- 设置开机自启动

#### 🗑️ 卸载脚本 (`scripts/uninstall_wireguard.sh`)
- 完全清理 WireGuard
- 备份配置文件
- 清理防火墙规则
- 恢复系统设置

#### 👥 客户端管理 (`scripts/add_wireguard_client.sh`)
- 智能 IP 分配
- 自动生成密钥对
- 热重载配置
- 二维码支持

#### 🔍 诊断工具 (`scripts/wg_diagnostic.sh`)
- 全面系统检查
- 配置验证
- 网络状态诊断
- 日志分析

### 🌐 Web 管理界面

#### 📊 实时监控
- 服务器状态监控
- 客户端在线状态
- 流量统计

#### 👥 客户端管理
- 添加/删除客户端
- 查看配置文件
- 生成二维码
- 一键复制配置

#### 📱 移动端支持
- 响应式设计
- 二维码扫描
- 移动端优化

## 💻 使用示例

### 1. 基本安装
```bash
# 克隆或下载项目
cd wireguard-manager

# 安装 WireGuard 服务端
sudo bash scripts/install_wireguard.sh

# 添加第一个客户端
sudo bash scripts/add_wireguard_client.sh
```

### 2. Web 界面部署
```bash
# 部署 Web 管理界面
sudo bash deploy_wireguard_web.sh

# 访问管理界面
# http://YOUR_SERVER_IP:8080
```

### 3. 系统诊断
```bash
# 如果遇到问题，运行诊断脚本
sudo bash scripts/wg_diagnostic.sh
```

## 🔧 管理命令

### WireGuard 服务管理
```bash
# 启动/停止/重启 WireGuard
sudo wg-quick up wg0
sudo wg-quick down wg0
sudo systemctl restart wg-quick@wg0

# 查看状态
sudo wg show
sudo systemctl status wg-quick@wg0
```

### Web 界面管理
```bash
# 启动/停止/重启 Web 界面
sudo systemctl start wireguard-web
sudo systemctl stop wireguard-web
sudo systemctl restart wireguard-web

# 查看日志
sudo journalctl -u wireguard-web -f
```

## 📂 配置文件位置

### 服务端配置
- 主配置：`/etc/wireguard/wg0.conf`
- 服务端密钥：`/etc/wireguard/server_*.key`

### 客户端配置
- 客户端目录：`/etc/wireguard/clients/`
- 配置文件：`/etc/wireguard/clients/客户端名.conf`
- 密钥文件：`/etc/wireguard/clients/客户端名_*.key`

## 🔒 安全建议

### 1. Web 界面安全
```bash
# 使用 SSH 隧道访问（推荐）
ssh -L 8080:localhost:8080 user@your_server

# 限制访问 IP
sudo ufw allow from YOUR_IP to any port 8080
```

### 2. 定期维护
- 定期更新系统和 WireGuard
- 删除不使用的客户端配置
- 监控客户端连接状态
- 备份配置文件

### 3. 防火墙配置
- 只开放必要端口（51820/udp, 8080/tcp）
- 使用 fail2ban 防止暴力攻击
- 定期检查连接日志

## 🐛 故障排除

### 常见问题

#### 1. 客户端无法连接
```bash
# 运行诊断脚本
sudo bash scripts/wg_diagnostic.sh

# 检查防火墙
sudo ufw status
sudo iptables -L

# 检查服务状态
sudo systemctl status wg-quick@wg0
```

#### 2. Web 界面无法访问
```bash
# 检查服务状态
sudo systemctl status wireguard-web

# 查看日志
sudo journalctl -u wireguard-web -n 50

# 检查端口
sudo ss -tlnp | grep 8080
```

#### 3. 权限问题
```bash
# 检查文件权限
ls -la /etc/wireguard/
sudo chown -R root:root /etc/wireguard/
sudo chmod 600 /etc/wireguard/*.conf
```

## 📝 系统要求

### 支持的系统
- Ubuntu 18.04+ ✅
- Debian 10+ ✅
- CentOS 8+ ✅
- RHEL 8+ ✅

### 最低配置
- CPU: 1 核心
- 内存: 512MB
- 存储: 1GB 可用空间
- 网络: 公网 IP 地址
