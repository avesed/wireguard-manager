# Web 管理界面快速部署指南

## 📋 部署步骤

### 1. 准备服务器环境
```bash
# 确保已安装 WireGuard
cd wireguard-manager
sudo bash scripts/install_wireguard.sh
```

### 2. 上传 Web 应用文件

将以下文件上传到服务器：

```bash
# 方式1: 使用 scp 上传
scp web/app.py root@YOUR_SERVER:/tmp/
scp web/templates/index.html root@YOUR_SERVER:/tmp/

# 方式2: 直接在服务器创建
# 在服务器上创建目录并手动复制文件内容
```

### 3. 运行部署脚本

```bash
# 在服务器上运行
cd wireguard-manager
sudo bash deploy_wireguard_web.sh
```

脚本会提示你移动文件：
- 将 `/tmp/app.py` 移动到 `/opt/wireguard-web/app.py`
- 将 `/tmp/index.html` 移动到 `/opt/wireguard-web/templates/index.html`

### 4. 完成部署

部署成功后访问：
```
http://YOUR_SERVER_IP:8080
```

## 🔧 手动部署（详细步骤）

如果自动部署失败，可以手动执行：

```bash
# 1. 安装依赖
sudo apt-get update
sudo apt-get install -y python3 python3-pip python3-venv qrencode

# 2. 创建应用目录
sudo mkdir -p /opt/wireguard-web/templates

# 3. 上传文件
sudo cp web/app.py /opt/wireguard-web/
sudo cp web/templates/index.html /opt/wireguard-web/templates/

# 4. 创建虚拟环境
cd /opt/wireguard-web
sudo python3 -m venv venv
sudo venv/bin/pip install flask qrcode[pil] pillow

# 5. 设置权限
sudo chown -R www-data:www-data /opt/wireguard-web

# 6. 配置 sudo 权限
sudo bash web/install_wireguard_web.sh

# 7. 启动服务
sudo systemctl daemon-reload
sudo systemctl start wireguard-web
sudo systemctl enable wireguard-web
```

## ✅ 验证部署

```bash
# 检查服务状态
sudo systemctl status wireguard-web

# 查看日志
sudo journalctl -u wireguard-web -f

# 测试访问
curl http://localhost:8080
```

## 🐛 常见问题

### 服务无法启动
```bash
# 检查错误日志
sudo journalctl -u wireguard-web -n 50 --no-pager

# 检查文件权限
ls -la /opt/wireguard-web/
```

### 端口被占用
```bash
# 检查端口占用
sudo ss -tlnp | grep 8080

# 修改端口（在 app.py 最后一行）
# app.run(host='0.0.0.0', port=8080, debug=False)
```

### 权限错误
```bash
# 重新配置 sudo 权限
sudo visudo -f /etc/sudoers.d/wireguard-web
```