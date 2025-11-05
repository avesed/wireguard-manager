# WireGuard 管理器

🔒 完整的 WireGuard VPN 服务器管理工具，支持自动化安装、Web 界面和客户端管理。

## 🚀 快速开始

### 🐳 Docker 部署（推荐）

```bash
git clone https://github.com/avesed/wireguard-manager.git
cd wireguard-manager

# 设置脚本权限
chmod +x setup-permissions.sh && ./setup-permissions.sh

# 一键部署
sudo ./docker-deploy.sh
```

**或者分步部署：**

```bash
# 1. 先启动 WireGuard 容器
sudo ./start-wireguard.sh

# 2. 等待 WireGuard 启动完成，然后启动 Web 界面
sudo ./start-web.sh
```

访问：`http://YOUR_SERVER_IP:8080`

### 📜 脚本部署

```bash
# 1. 安装 WireGuard
sudo bash scripts/install_wireguard.sh

# 2. 部署 Web 界面（可选）
sudo bash deploy_wireguard_web.sh

# 3. 添加客户端
sudo bash scripts/add_wireguard_client.sh
```

访问：`http://YOUR_SERVER_IP:8080`

## 📋 功能特性

### 核心脚本
- **install_wireguard.sh** - 自动安装、配置防火墙和 IP 转发
- **add_wireguard_client.sh** - 智能 IP 分配、生成密钥和二维码
- **uninstall_wireguard.sh** - 完全清理并备份配置
- **wg_diagnostic.sh** - 系统检查和网络诊断

### Web 管理界面
- 实时监控服务器和客户端状态
- 添加/删除客户端、查看配置
- 生成二维码、一键复制配置
- 响应式设计，支持移动端

## 🔧 管理命令

### Docker 容器管理

```bash
# 查看容器状态
docker ps

# 查看日志
docker logs -f wireguard-vpn      # WireGuard 日志
docker logs -f wireguard-web-ui   # Web 界面日志

# 重启容器
docker restart wireguard-vpn
docker restart wireguard-web-ui

# 停止容器
docker stop wireguard-vpn wireguard-web-ui

# 进入容器调试
docker exec -it wireguard-vpn bash
docker exec -it wireguard-web-ui bash

# 清理环境
./cleanup-wireguard.sh
```

### 传统服务管理

```bash
# WireGuard 服务
sudo systemctl start/stop/restart wg-quick@wg0
sudo wg show

# Web 界面
sudo systemctl start/stop/restart wireguard-web
sudo journalctl -u wireguard-web -f

# 诊断
sudo bash scripts/wg_diagnostic.sh
```

## 📂 配置文件

- 服务端：`/etc/wireguard/wg0.conf`
- 客户端：`/etc/wireguard/clients/`

## 🔒 安全建议

```bash
# 使用 SSH 隧道访问（推荐）
ssh -L 8080:localhost:8080 user@your_server

# 限制 Web 界面访问 IP
sudo ufw allow from YOUR_IP to any port 8080

# 只开放必要端口
sudo ufw allow 51820/udp
```

- 定期更新系统和 WireGuard
- 删除未使用的客户端
- 定期备份配置文件

## 🐛 故障排除

```bash
# 运行诊断脚本
sudo bash scripts/wg_diagnostic.sh

# 检查服务状态
sudo systemctl status wg-quick@wg0
sudo systemctl status wireguard-web

# 查看日志
sudo journalctl -u wireguard-web -n 50

# 检查权限
sudo chown -R root:root /etc/wireguard/
sudo chmod 600 /etc/wireguard/*.conf
```

## 📝 系统要求

- Ubuntu 18.04+ / Debian 10+ / CentOS 8+ / RHEL 8+
- 最低配置：1 核 CPU、512MB 内存、1GB 存储
- 需要公网 IP 地址
