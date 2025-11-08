# WireGuard Manager

基于 Docker 的 WireGuard VPN 管理工具，支持真正一键部署和完整的Web管理界面。

## 快速开始

### 一键安装
```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/avesed/wireguard-manager/main/install.sh)
```
部署完成后，登录凭据会显示在终端并保存到 `/etc/wireguard-manager/web-credentials.txt`

## 访问Web界面

部署完成后访问：`http://YOUR_SERVER_IP:8080`

**默认凭据**：
- 用户名：`admin`
- 密码：部署时自动生成（查看终端或 `/etc/wireguard-manager/web-credentials.txt`）

**密码要求**（安全要求）：
- 最少 8 个字符
- 包含大写字母
- 包含小写字母
- 包含数字
- 包含特殊字符 (!@#$%^&* 等)

## 管理命令

### 交互式菜单

运行 deploy.sh 进入交互式管理菜单：

```bash
cd wireguard-manager  # 或您的安装目录
sudo bash deploy.sh
```

**菜单选项**：
1. **完整安装** - 安装 WireGuard + Web 界面
2. **升级/重新安装** - 重新构建镜像并重启
3. **重启服务** - 重启 Web/WireGuard/全部
4. **停止服务** - 停止所有容器
5. **卸载** - 删除容器，可选删除数据
6. **数据管理** - 备份/恢复/清除配置数据
7. **查看日志** - 查看容器运行日志
8. **查看状态** - 显示容器和 WireGuard 状态
9. **更改管理员密码** - 安全地更改密码（含验证）

### 命令行快捷方式

```bash
# 查看状态
sudo bash deploy.sh status

# 查看日志
sudo bash deploy.sh logs

# 重启服务
sudo bash deploy.sh restart

# 更改密码
sudo bash deploy.sh password

# 停止服务
sudo bash deploy.sh stop

# 卸载
sudo bash deploy.sh uninstall

# 备份数据
sudo bash deploy.sh backup
```

### Docker 直接管理

```bash
# 查看容器
docker ps

# 查看日志
docker logs -f wireguard-vpn       # WireGuard
docker logs -f wireguard-web-ui    # Web界面

# 重启服务
docker restart wireguard-vpn
docker restart wireguard-web-ui
```

## 配置文件

默认配置目录：`/etc/wireguard-manager`（可在安装时自定义）

- **WireGuard配置**：`/etc/wireguard-manager/wireguard/wg0.conf`
- **客户端配置**：`/etc/wireguard-manager/wireguard/clients/`
- **用户数据**：`/etc/wireguard-manager/wireguard/users.json`
- **登录凭据**：`/etc/wireguard-manager/web-credentials.txt`

### 数据备份与恢复

```bash
# 备份数据
sudo bash deploy.sh backup

# 恢复数据
sudo bash deploy.sh
# 选择菜单选项 6 -> 2
```

## 身份认证

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

## 故障排除

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

使用统一脚本更改密码：
```bash
sudo bash deploy.sh password
```

或手动重置：
```bash
# 删除用户数据
sudo rm /etc/wireguard-manager/wireguard/users.json

# 重启容器（会生成新密码）
docker restart wireguard-web-ui

# 查看新密码
docker logs wireguard-web-ui | grep -A 5 "credentials"
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
## 高级配置

### 自定义安装目录

```bash
sudo bash deploy.sh install --install-dir /opt/wg-data
```


## 详细文档

- **[环境变量配置](.env.example)** - 配置示例文件
- **[部署脚本](deploy.sh)** - 统一部署和管理脚本
- **[安装脚本](install.sh)** - 一键安装脚本
