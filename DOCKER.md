# WireGuard Manager - Docker 部署指南

## 🐳 Docker 快速部署

使用 Docker 可以快速部署 WireGuard VPN 服务和 Web 管理界面，无需手动配置环境。

## 📋 前置要求

### 系统要求
- Linux 系统（推荐 Ubuntu 20.04+, Debian 11+, CentOS 8+）
- 内核版本 >= 5.6（内置 WireGuard 支持）
- Docker 20.10+
- Docker Compose 2.0+

### 安装 Docker

```bash
# 一键安装 Docker
curl -fsSL https://get.docker.com | sh

# 启动 Docker 服务
sudo systemctl start docker
sudo systemctl enable docker

# 验证安装
docker --version
```

### 安装 Docker Compose

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install docker-compose-plugin

# 或使用独立版本
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 验证安装
docker-compose --version
```

## 🚀 快速部署

### 方式1：一键部署（推荐）

```bash
# 1. 克隆项目
git clone https://github.com/your-repo/wireguard-manager.git
cd wireguard-manager

# 2. 赋予执行权限
chmod +x docker-deploy.sh

# 3. 运行部署脚本
sudo bash docker-deploy.sh
```

脚本会自动：
- ✅ 检查 Docker 和 Docker Compose
- ✅ 创建配置目录
- ✅ 检测服务器 IP
- ✅ 构建 Docker 镜像
- ✅ 启动所有服务

### 方式2：手动部署

```bash
# 1. 创建配置目录
mkdir -p config/wireguard

# 2. 构建镜像
docker-compose build

# 3. 启动服务
docker-compose up -d

# 4. 查看服务状态
docker-compose ps
```

## 📦 服务说明

### 服务架构

```
┌─────────────────────────────────────┐
│   WireGuard Manager (Docker)        │
├─────────────────────────────────────┤
│                                     │
│  ┌──────────────┐  ┌─────────────┐ │
│  │  WireGuard   │  │   Web UI    │ │
│  │   Server     │  │  (Flask)    │ │
│  │              │  │             │ │
│  │  Port: 51820 │  │ Port: 8080  │ │
│  └──────────────┘  └─────────────┘ │
│         │                 │         │
│         └─────────┬───────┘         │
│                   │                 │
│         ┌─────────▼────────┐        │
│         │ Shared Config    │        │
│         │ /etc/wireguard   │        │
│         └──────────────────┘        │
└─────────────────────────────────────┘
```

### 容器列表

1. **wireguard-vpn** - WireGuard VPN 服务器
   - 端口: 51820/udp
   - 功能: VPN 连接处理
   - 网络: host 模式

2. **wireguard-web-ui** - Web 管理界面
   - 端口: 8080/tcp
   - 功能: 可视化管理界面
   - 网络: host 模式

## 🔧 配置说明

### 环境变量

可以在 `docker-compose.yml` 中修改：

```yaml
environment:
  - WG_INTERFACE=wg0          # WireGuard 接口名称
  - WG_PORT=51820             # 监听端口
  - SERVER_VPN_IP=10.8.0.1/24 # VPN 内网地址
  - TZ=Asia/Shanghai          # 时区
```

### 数据持久化

配置文件存储在：
```
./config/wireguard/          # WireGuard 配置目录
├── wg0.conf                 # 服务端配置
├── server_private.key       # 服务端私钥
├── server_public.key        # 服务端公钥
└── clients/                 # 客户端配置目录
    ├── client1.conf
    └── client1_*.key
```

## 💻 使用方法

### 启动服务

```bash
# 启动所有服务
docker-compose up -d

# 只启动 WireGuard 服务
docker-compose up -d wireguard

# 只启动 Web 界面
docker-compose up -d wireguard-web
```

### 停止服务

```bash
# 停止所有服务
docker-compose stop

# 停止特定服务
docker-compose stop wireguard
docker-compose stop wireguard-web
```

### 重启服务

```bash
# 重启所有服务
docker-compose restart

# 重启特定服务
docker-compose restart wireguard
```

### 查看日志

```bash
# 查看所有服务日志
docker-compose logs -f

# 查看特定服务日志
docker-compose logs -f wireguard
docker-compose logs -f wireguard-web

# 查看最近 100 行日志
docker-compose logs --tail=100 wireguard
```

### 查看状态

```bash
# 查看容器状态
docker-compose ps

# 查看 WireGuard 状态
docker-compose exec wireguard wg show

# 查看 WireGuard 配置
docker-compose exec wireguard cat /etc/wireguard/wg0.conf
```

### 进入容器

```bash
# 进入 WireGuard 容器
docker-compose exec wireguard bash

# 进入 Web 容器
docker-compose exec wireguard-web bash
```

## 👥 客户端管理

### 方式1：使用 Web 界面

访问 `http://YOUR_SERVER_IP:8080`

1. 点击"添加客户端"
2. 输入客户端名称
3. 自动生成配置和二维码
4. 复制配置或扫描二维码

### 方式2：使用命令行

```bash
# 添加客户端
docker-compose exec wireguard bash /app/scripts/add_wireguard_client.sh

# 查看客户端列表
docker-compose exec wireguard ls -la /etc/wireguard/clients/

# 查看客户端配置
docker-compose exec wireguard cat /etc/wireguard/clients/client1.conf
```

## 🔍 故障排除

### 检查容器状态

```bash
# 查看所有容器
docker ps -a

# 查看容器详细信息
docker inspect wireguard-vpn
```

### 常见问题

#### 1. WireGuard 容器无法启动

```bash
# 检查内核模块
lsmod | grep wireguard

# 加载内核模块
sudo modprobe wireguard

# 检查内核版本
uname -r  # 应该 >= 5.6
```

#### 2. 端口冲突

```bash
# 检查端口占用
sudo ss -ulnp | grep 51820
sudo ss -tlnp | grep 8080

# 修改 docker-compose.yml 中的端口配置
```

#### 3. 权限问题

```bash
# 容器需要特权模式
# 确保 docker-compose.yml 中有:
privileged: true
cap_add:
  - NET_ADMIN
  - SYS_MODULE
```

#### 4. 客户端无法连接

```bash
# 检查防火墙
sudo ufw status
sudo ufw allow 51820/udp

# 检查 IP 转发
cat /proc/sys/net/ipv4/ip_forward  # 应该为 1

# 查看 WireGuard 日志
docker-compose logs wireguard
```

### 重置配置

```bash
# 停止服务
docker-compose down

# 删除配置（注意：会删除所有客户端配置）
sudo rm -rf config/wireguard/*

# 重新启动
docker-compose up -d
```

## 🔒 安全建议

### 1. 限制 Web 界面访问

```bash
# 使用 SSH 隧道（推荐）
ssh -L 8080:localhost:8080 user@your_server
# 然后访问 http://localhost:8080

# 或使用防火墙限制访问
sudo ufw allow from YOUR_IP to any port 8080
```

### 2. 使用 Docker 网络隔离

修改 `docker-compose.yml`，使用自定义网络而非 host 模式（需要调整配置）。

### 3. 定期备份

```bash
# 备份配置
tar -czf wireguard-backup-$(date +%Y%m%d).tar.gz config/

# 恢复配置
tar -xzf wireguard-backup-YYYYMMDD.tar.gz
```

### 4. 更新镜像

```bash
# 重新构建镜像
docker-compose build --no-cache

# 重启服务
docker-compose up -d --force-recreate
```

## 📊 监控和维护

### 资源使用情况

```bash
# 查看容器资源使用
docker stats

# 查看磁盘使用
docker system df
```

### 清理无用数据

```bash
# 清理未使用的镜像
docker image prune -a

# 清理未使用的容器
docker container prune

# 清理系统
docker system prune -a
```

## 🔄 更新升级

```bash
# 1. 备份配置
tar -czf config-backup.tar.gz config/

# 2. 拉取最新代码
git pull

# 3. 重新构建镜像
docker-compose build --no-cache

# 4. 重启服务
docker-compose up -d --force-recreate

# 5. 验证服务
docker-compose ps
docker-compose logs -f
```

## 🆘 获取帮助

如果遇到问题：

1. 查看日志: `docker-compose logs -f`
2. 检查状态: `docker-compose ps`
3. 查看文档: [WireGuard 官方文档](https://www.wireguard.com/)
4. 提交 Issue: [项目 Issues 页面](#)

---

**快速命令参考：**

```bash
# 部署
sudo bash docker-deploy.sh

# 管理
docker-compose up -d          # 启动
docker-compose stop           # 停止
docker-compose restart        # 重启
docker-compose logs -f        # 日志
docker-compose ps             # 状态

# 访问
http://YOUR_SERVER_IP:8080    # Web 界面
```
