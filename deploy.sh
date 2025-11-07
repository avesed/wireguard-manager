#!/bin/bash
# WireGuard Manager - 统一部署脚本

set -e

# 默认配置
DEFAULT_INSTALL_DIR="/etc/wireguard-manager"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
WEB_PORT="${WEB_PORT:-8080}"
WG_PORT="${WG_PORT:-51820}"
SERVER_VPN_IP="${SERVER_VPN_IP:-10.8.0.1/24}"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 工具函数
log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# 生成符合安全要求的密码
generate_secure_password() {
    local upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local lower="abcdefghijklmnopqrstuvwxyz"
    local digits="0123456789"
    local special='!@#$%^&*()_+-='

    # 确保每种类型至少有2个字符
    local pass=""
    pass+=$(echo "$upper" | fold -w1 | shuf | head -c2)
    pass+=$(echo "$lower" | fold -w1 | shuf | head -c2)
    pass+=$(echo "$digits" | fold -w1 | shuf | head -c2)
    pass+=$(echo "$special" | fold -w1 | shuf | head -c2)

    # 填充剩余8个字符（总共16位）
    local all="${upper}${lower}${digits}${special}"
    pass+=$(echo "$all" | fold -w1 | shuf | head -c8)

    # 打乱顺序
    echo "$pass" | fold -w1 | shuf | tr -d '\n'
    echo ""
}

# 验证密码复杂度
validate_password() {
    local password="$1"

    if [ ${#password} -lt 8 ]; then
        echo "密码长度至少为8个字符"
        return 1
    fi

    if ! echo "$password" | grep -q '[A-Z]'; then
        echo "密码必须包含至少一个大写字母"
        return 1
    fi

    if ! echo "$password" | grep -q '[a-z]'; then
        echo "密码必须包含至少一个小写字母"
        return 1
    fi

    if ! echo "$password" | grep -q '[0-9]'; then
        echo "密码必须包含至少一个数字"
        return 1
    fi

    if ! echo "$password" | grep -q '[!@#$%^&*()_+\-=\[\]{};:'"'"',.<>?/\\|`~]'; then
        echo "密码必须包含至少一个特殊字符 (!@#$%^&* 等)"
        return 1
    fi

    return 0
}

# 检查 Docker
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker 未安装"
        echo "安装命令: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi
    log_info "Docker 环境检查通过"
}

# 检测服务器 IP
detect_server_ip() {
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "")
    if [ -z "$SERVER_IP" ]; then
        echo -n "无法自动检测服务器公网 IP，请输入: "
        read SERVER_IP
    fi
    log_info "服务器 IP: $SERVER_IP"
}

# 启用 IP 转发
enable_ip_forward() {
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf >/dev/null 2>&1 || true
        log_info "IP 转发已启用"
    else
        log_info "IP 转发已启用"
    fi
}

# 创建配置目录
create_config_dir() {
    local config_dir="$1"

    mkdir -p "$config_dir/wireguard/clients"
    chmod 755 "$config_dir"
    chmod 755 "$config_dir/wireguard"
    chmod 755 "$config_dir/wireguard/clients"

    local current_uid=$(id -u)
    local current_gid=$(id -g)
    chown -R $current_uid:$current_gid "$config_dir/wireguard" 2>/dev/null || true

    log_info "配置目录创建完成: $config_dir"
}

# 检查数据目录
check_existing_data() {
    local config_dir="$1"

    if [ -d "$config_dir/wireguard" ] && [ -n "$(ls -A $config_dir/wireguard 2>/dev/null)" ]; then
        echo ""
        log_warn "检测到现有配置数据: $config_dir/wireguard"
        echo -n "是否保留现有数据? (y/n) [y]: "
        read preserve_data
        preserve_data=${preserve_data:-y}

        if [ "$preserve_data" != "y" ] && [ "$preserve_data" != "Y" ]; then
            echo ""
            log_warn "即将删除所有现有数据！"
            echo -n "请输入 'DELETE' 确认删除: "
            read confirm_delete

            if [ "$confirm_delete" = "DELETE" ]; then
                rm -rf "$config_dir/wireguard"
                log_info "现有数据已删除"
                return 1
            else
                log_info "取消删除，保留现有数据"
                return 0
            fi
        else
            log_info "保留现有数据"
            return 0
        fi
    fi
    return 1
}

# 构建镜像
build_images() {
    local service="$1"

    echo ""
    echo "构建 Docker 镜像..."

    if [ "$service" = "wireguard" ] || [ "$service" = "all" ]; then
        docker build -f Dockerfile.wireguard -t wireguard-manager:latest . >/dev/null
        log_info "WireGuard 镜像构建完成"
    fi

    if [ "$service" = "web" ] || [ "$service" = "all" ]; then
        docker build -f Dockerfile.web -t wireguard-web:latest . >/dev/null
        log_info "Web 镜像构建完成"
    fi
}

# 停止容器
stop_containers() {
    local service="$1"

    if [ "$service" = "wireguard" ] || [ "$service" = "all" ]; then
        docker stop wireguard-vpn 2>/dev/null || true
        log_info "WireGuard 容器已停止"
    fi

    if [ "$service" = "web" ] || [ "$service" = "all" ]; then
        docker stop wireguard-web-ui 2>/dev/null || true
        log_info "Web 容器已停止"
    fi
}

# 删除容器
remove_containers() {
    local service="$1"

    if [ "$service" = "wireguard" ] || [ "$service" = "all" ]; then
        docker rm wireguard-vpn 2>/dev/null || true
    fi

    if [ "$service" = "web" ] || [ "$service" = "all" ]; then
        docker rm wireguard-web-ui 2>/dev/null || true
    fi
}

# 启动 WireGuard 容器
start_wireguard() {
    local config_dir="$1"

    echo ""
    echo "启动 WireGuard 容器..."

    # 清理现有容器
    docker stop wireguard-vpn 2>/dev/null || true
    docker rm wireguard-vpn 2>/dev/null || true

    # 清理现有的 WireGuard 接口
    if ip link show wg0 >/dev/null 2>&1; then
        log_info "清理现有 WireGuard 接口..."
        sudo wg-quick down wg0 2>/dev/null || true
        sleep 2
    fi

    docker run -d \
        --name wireguard-vpn \
        --restart unless-stopped \
        --network host \
        --privileged \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        -e WG_INTERFACE=wg0 \
        -e WG_PORT=$WG_PORT \
        -e SERVER_VPN_IP=$SERVER_VPN_IP \
        -e TZ=Asia/Shanghai \
        -v "$config_dir/wireguard:/etc/wireguard" \
        -v /lib/modules:/lib/modules:ro \
        wireguard-manager:latest

    log_info "WireGuard 容器已启动"

    # 等待 WireGuard 容器初始化
    echo "等待 WireGuard 初始化..."
    sleep 10

    # 检查 WireGuard 状态
    local retry_count=0
    local max_retries=12
    while [ $retry_count -lt $max_retries ]; do
        if docker exec wireguard-vpn wg show wg0 >/dev/null 2>&1; then
            log_info "WireGuard 初始化完成"
            return 0
        fi
        echo "等待 WireGuard 启动... ($((retry_count + 1))/$max_retries)"
        sleep 5
        retry_count=$((retry_count + 1))
    done

    log_warn "WireGuard 启动超时，但继续部署..."
    return 1
}

# 启动 Web 容器
start_web() {
    local config_dir="$1"
    local admin_username="${2:-admin}"
    local admin_password="$3"
    local generated_password=false

    echo ""
    echo "启动 Web 管理界面..."

    # 清理现有容器
    docker stop wireguard-web-ui 2>/dev/null || true
    docker rm wireguard-web-ui 2>/dev/null || true

    # 如果未设置密码，生成安全的随机密码
    if [ -z "$admin_password" ]; then
        admin_password=$(generate_secure_password)
        generated_password=true
    fi

    # 生成 SECRET_KEY
    local secret_key=${SECRET_KEY:-$(openssl rand -hex 32)}

    docker run -d \
        --name wireguard-web-ui \
        --restart unless-stopped \
        --network host \
        --cap-add NET_ADMIN \
        --user root \
        -e "WEB_PORT=$WEB_PORT" \
        -e "TZ=Asia/Shanghai" \
        -e "ADMIN_USERNAME=$admin_username" \
        -e "ADMIN_PASSWORD=$admin_password" \
        -e "SECRET_KEY=$secret_key" \
        -v "$config_dir/wireguard:/etc/wireguard" \
        -v "$config_dir/wireguard/clients:/etc/wireguard/clients" \
        wireguard-web:latest

    log_info "Web 管理界面已启动"

    # 等待 Web 服务启动
    echo "等待 Web 服务启动..."
    sleep 5

    # 检查 Web 服务状态
    local retry_count=0
    local max_retries=6
    while [ $retry_count -lt $max_retries ]; do
        if curl -f http://localhost:$WEB_PORT/ >/dev/null 2>&1; then
            log_info "Web 服务启动完成"
            break
        fi
        echo "等待 Web 服务启动... ($((retry_count + 1))/$max_retries)"
        sleep 5
        retry_count=$((retry_count + 1))
    done

    if [ $retry_count -eq $max_retries ]; then
        log_warn "Web 服务启动检查超时，请手动检查"
    fi

    # 显示凭据
    if [ "$generated_password" = true ]; then
        echo ""
        echo "=========================================="
        echo "🔒 登录凭据:"
        echo "  用户名: $admin_username"
        echo "  密码: $admin_password"
        echo ""
        log_warn "这是自动生成的密码，请妥善保存！"
        echo "  提示：建议首次登录后修改密码（使用选项 9）"

        # 保存凭据到文件
        cat > "$config_dir/web-credentials.txt" <<EOF
WireGuard Web 管理面板登录凭据
================================
访问地址: http://$SERVER_IP:$WEB_PORT
用户名: $admin_username
密码: $admin_password
生成时间: $(date)
================================
⚠️ 请妥善保管此文件，并在首次登录后删除
EOF
        chmod 600 "$config_dir/web-credentials.txt"
        echo ""
        log_info "凭据已保存到: $config_dir/web-credentials.txt"
        echo "=========================================="
    fi
}

# 更改管理员密码
change_admin_password() {
    local config_dir="$1"

    echo ""
    echo "=== 更改管理员密码 ==="
    echo ""

    # 检查 Web 容器是否运行
    if ! docker ps --format '{{.Names}}' | grep -q '^wireguard-web-ui$'; then
        log_error "Web 容器未运行，无法更改密码"
        echo "请先启动 Web 服务（选项 1 或 3）"
        return 1
    fi

    echo "密码要求："
    echo "  - 至少 8 个字符"
    echo "  - 包含大写字母"
    echo "  - 包含小写字母"
    echo "  - 包含数字"
    echo "  - 包含特殊字符 (!@#$%^&* 等)"
    echo ""

    local new_password=""
    local confirm_password=""
    local attempts=0
    local max_attempts=3

    while [ $attempts -lt $max_attempts ]; do
        echo -n "请输入新密码: "
        read -s new_password
        echo ""

        echo -n "请再次输入新密码: "
        read -s confirm_password
        echo ""

        if [ "$new_password" != "$confirm_password" ]; then
            log_error "两次输入的密码不一致"
            attempts=$((attempts + 1))
            continue
        fi

        # 验证密码复杂度
        if validate_password "$new_password"; then
            break
        else
            log_error "$(validate_password "$new_password" 2>&1)"
            attempts=$((attempts + 1))
        fi
    done

    if [ $attempts -eq $max_attempts ]; then
        log_error "密码设置失败，已达到最大尝试次数"
        return 1
    fi

    # 更新容器环境变量并重启
    echo ""
    echo "正在更新密码..."

    # 获取当前的其他环境变量
    local admin_username=$(docker inspect wireguard-web-ui --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^ADMIN_USERNAME=' | cut -d= -f2)
    local secret_key=$(docker inspect wireguard-web-ui --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^SECRET_KEY=' | cut -d= -f2)

    admin_username=${admin_username:-admin}
    secret_key=${secret_key:-$(openssl rand -hex 32)}

    # 停止并删除旧容器
    docker stop wireguard-web-ui >/dev/null 2>&1
    docker rm wireguard-web-ui >/dev/null 2>&1

    # 使用新密码启动容器
    docker run -d \
        --name wireguard-web-ui \
        --restart unless-stopped \
        --network host \
        --cap-add NET_ADMIN \
        --user root \
        -e "WEB_PORT=$WEB_PORT" \
        -e "TZ=Asia/Shanghai" \
        -e "ADMIN_USERNAME=$admin_username" \
        -e "ADMIN_PASSWORD=$new_password" \
        -e "SECRET_KEY=$secret_key" \
        -v "$config_dir/wireguard:/etc/wireguard" \
        -v "$config_dir/wireguard/clients:/etc/wireguard/clients" \
        wireguard-web:latest >/dev/null

    # 等待服务重启
    sleep 5

    if docker ps --format '{{.Names}}' | grep -q '^wireguard-web-ui$'; then
        log_info "密码更改成功！"
        echo ""
        echo "新的登录凭据："
        echo "  用户名: $admin_username"
        echo "  密码: $new_password"
        echo ""
        log_warn "请妥善保存新密码"

        # 更新凭据文件
        cat > "$config_dir/web-credentials.txt" <<EOF
WireGuard Web 管理面板登录凭据
================================
访问地址: http://$SERVER_IP:$WEB_PORT
用户名: $admin_username
密码: $new_password
更新时间: $(date)
================================
⚠️ 请妥善保管此文件
EOF
        chmod 600 "$config_dir/web-credentials.txt"
    else
        log_error "密码更改后服务启动失败，请检查日志"
        return 1
    fi
}

# 备份数据
backup_data() {
    local config_dir="$1"
    local backup_file="wireguard-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    echo ""
    echo "=== 备份数据 ==="
    echo ""

    if [ ! -d "$config_dir/wireguard" ]; then
        log_error "配置目录不存在: $config_dir/wireguard"
        return 1
    fi

    tar -czf "$backup_file" -C "$config_dir" wireguard
    log_info "数据已备份到: $backup_file"
    echo "备份大小: $(du -h "$backup_file" | cut -f1)"
}

# 恢复数据
restore_data() {
    local config_dir="$1"

    echo ""
    echo "=== 恢复数据 ==="
    echo ""

    echo -n "请输入备份文件路径: "
    read backup_file

    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi

    echo ""
    log_warn "恢复数据将覆盖现有配置"
    echo -n "是否继续? (y/n) [n]: "
    read confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "取消恢复"
        return 0
    fi

    # 停止容器
    stop_containers "all"

    # 备份当前数据
    if [ -d "$config_dir/wireguard" ]; then
        local old_backup="wireguard-old-$(date +%Y%m%d-%H%M%S).tar.gz"
        tar -czf "$old_backup" -C "$config_dir" wireguard 2>/dev/null || true
        log_info "当前数据已备份到: $old_backup"
    fi

    # 删除现有数据
    rm -rf "$config_dir/wireguard"

    # 恢复数据
    tar -xzf "$backup_file" -C "$config_dir"
    log_info "数据恢复完成"

    echo ""
    log_info "请重启服务以应用恢复的配置（选项 3）"
}

# 清除所有数据
clear_all_data() {
    local config_dir="$1"

    echo ""
    echo "=== 清除所有数据 ==="
    echo ""

    log_warn "此操作将永久删除所有 WireGuard 配置和客户端数据！"
    echo ""
    echo -n "请输入 'DELETE ALL' 确认删除: "
    read confirm_delete

    if [ "$confirm_delete" != "DELETE ALL" ]; then
        log_info "取消删除"
        return 0
    fi

    # 停止容器
    stop_containers "all"

    # 删除数据
    rm -rf "$config_dir/wireguard"
    log_info "所有数据已删除"
}

# 查看日志
view_logs() {
    echo ""
    echo "=== 查看日志 ==="
    echo ""
    echo "1) WireGuard 日志"
    echo "2) Web 日志"
    echo "3) 两者都查看"
    echo ""
    echo -n "选择 [1-3]: "
    read log_choice

    case $log_choice in
        1)
            if docker ps --format '{{.Names}}' | grep -q '^wireguard-vpn$'; then
                docker logs --tail 50 -f wireguard-vpn
            else
                log_error "WireGuard 容器未运行"
            fi
            ;;
        2)
            if docker ps --format '{{.Names}}' | grep -q '^wireguard-web-ui$'; then
                docker logs --tail 50 -f wireguard-web-ui
            else
                log_error "Web 容器未运行"
            fi
            ;;
        3)
            echo "WireGuard 日志:"
            docker logs --tail 20 wireguard-vpn 2>/dev/null || log_error "WireGuard 容器未运行"
            echo ""
            echo "Web 日志:"
            docker logs --tail 20 wireguard-web-ui 2>/dev/null || log_error "Web 容器未运行"
            ;;
        *)
            log_error "无效选项"
            ;;
    esac
}

# 查看容器状态
show_status() {
    echo ""
    echo "=== 容器状态 ==="
    echo ""

    local wg_running=false
    local web_running=false

    if docker ps --format '{{.Names}}' | grep -q '^wireguard-vpn$'; then
        wg_running=true
        log_info "WireGuard 容器: 运行中"
        echo "  容器 ID: $(docker ps --filter name=wireguard-vpn --format '{{.ID}}')"
        echo "  启动时间: $(docker ps --filter name=wireguard-vpn --format '{{.Status}}')"
    else
        log_error "WireGuard 容器: 未运行"
    fi

    echo ""

    if docker ps --format '{{.Names}}' | grep -q '^wireguard-web-ui$'; then
        web_running=true
        log_info "Web 容器: 运行中"
        echo "  容器 ID: $(docker ps --filter name=wireguard-web-ui --format '{{.ID}}')"
        echo "  启动时间: $(docker ps --filter name=wireguard-web-ui --format '{{.Status}}')"
        echo "  访问地址: http://$SERVER_IP:$WEB_PORT"
    else
        log_error "Web 容器: 未运行"
    fi

    echo ""

    if [ "$wg_running" = true ]; then
        echo "WireGuard 接口状态:"
        docker exec wireguard-vpn wg show 2>/dev/null || log_warn "无法获取 WireGuard 状态"
    fi
}

# 完整安装
full_install() {
    local config_dir="$1"

    echo ""
    echo "=========================================="
    echo "    WireGuard Manager 完整安装"
    echo "=========================================="
    echo ""
    echo "安装目录: $config_dir"
    echo ""

    check_docker
    detect_server_ip

    # 检查现有数据
    check_existing_data "$config_dir"

    # 创建配置目录
    create_config_dir "$config_dir"

    # 启用 IP 转发
    enable_ip_forward

    # 构建镜像
    build_images "all"

    # 启动服务
    start_wireguard "$config_dir"
    start_web "$config_dir" "${ADMIN_USERNAME:-admin}" "$ADMIN_PASSWORD"

    echo ""
    echo "=========================================="
    log_info "部署完成！"
    echo "=========================================="
    echo ""
    echo "WireGuard VPN:"
    echo "  服务器: $SERVER_IP:$WG_PORT"
    echo "  配置: $config_dir/wireguard/"
    echo ""
    echo "Web 管理界面:"
    echo "  地址: http://$SERVER_IP:$WEB_PORT"
    echo ""
    echo "常用命令:"
    echo "  查看状态: $0 status"
    echo "  查看日志: $0 logs"
    echo "  更改密码: $0 password"
    echo "  重启服务: $0 restart"
    echo "=========================================="
}

# 升级/重新安装
upgrade_install() {
    local config_dir="$1"

    echo ""
    echo "=== 升级/重新安装 ==="
    echo ""

    log_info "停止现有容器..."
    stop_containers "all"
    remove_containers "all"

    log_info "重新构建镜像..."
    build_images "all"

    log_info "重新启动服务..."
    start_wireguard "$config_dir"
    start_web "$config_dir" "${ADMIN_USERNAME:-admin}" "$ADMIN_PASSWORD"

    echo ""
    log_info "升级完成！"
}

# 重启服务
restart_services() {
    local config_dir="$1"

    echo ""
    echo "=== 重启服务 ==="
    echo ""
    echo "1) 重启 Web"
    echo "2) 重启 WireGuard"
    echo "3) 重启全部"
    echo ""
    echo -n "选择 [1-3]: "
    read restart_choice

    case $restart_choice in
        1)
            if docker ps --format '{{.Names}}' | grep -q '^wireguard-web-ui$'; then
                docker restart wireguard-web-ui
                log_info "Web 服务已重启"
            else
                log_warn "Web 容器未运行，启动新容器..."
                start_web "$config_dir" "${ADMIN_USERNAME:-admin}" "$ADMIN_PASSWORD"
            fi
            ;;
        2)
            if docker ps --format '{{.Names}}' | grep -q '^wireguard-vpn$'; then
                docker restart wireguard-vpn
                log_info "WireGuard 服务已重启"
            else
                log_warn "WireGuard 容器未运行，启动新容器..."
                start_wireguard "$config_dir"
            fi
            ;;
        3)
            docker restart wireguard-vpn wireguard-web-ui 2>/dev/null || true
            log_info "所有服务已重启"
            ;;
        *)
            log_error "无效选项"
            ;;
    esac
}

# 卸载
uninstall() {
    local config_dir="$1"

    echo ""
    echo "=== 卸载 WireGuard Manager ==="
    echo ""

    log_warn "此操作将停止并删除所有容器"
    echo -n "是否继续? (y/n) [n]: "
    read confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "取消卸载"
        return 0
    fi

    # 停止并删除容器
    stop_containers "all"
    remove_containers "all"

    # 清理 WireGuard 接口
    if ip link show wg0 >/dev/null 2>&1; then
        sudo wg-quick down wg0 2>/dev/null || true
    fi

    log_info "容器已删除"

    echo ""
    echo -n "是否删除配置数据? (y/n) [n]: "
    read delete_data

    if [ "$delete_data" = "y" ] || [ "$delete_data" = "Y" ]; then
        echo ""
        log_warn "即将删除所有配置数据！"
        echo -n "请输入 'DELETE' 确认: "
        read confirm_delete

        if [ "$confirm_delete" = "DELETE" ]; then
            rm -rf "$config_dir"
            log_info "配置数据已删除"
        else
            log_info "保留配置数据"
        fi
    else
        log_info "保留配置数据: $config_dir"
    fi

    log_info "卸载完成"
}

# 数据管理菜单
data_management() {
    local config_dir="$1"

    echo ""
    echo "=== 数据管理 ==="
    echo ""
    echo "1) 备份数据"
    echo "2) 恢复数据"
    echo "3) 清除所有数据"
    echo "0) 返回主菜单"
    echo ""
    echo -n "选择 [0-3]: "
    read data_choice

    case $data_choice in
        1)
            backup_data "$config_dir"
            ;;
        2)
            restore_data "$config_dir"
            ;;
        3)
            clear_all_data "$config_dir"
            ;;
        0)
            return 0
            ;;
        *)
            log_error "无效选项"
            ;;
    esac
}

# 交互式菜单
interactive_menu() {
    local config_dir="${1:-$INSTALL_DIR}"

    while true; do
        echo ""
        echo "=========================================="
        echo "    WireGuard Manager 部署脚本"
        echo "=========================================="
        echo ""
        echo "1) 完整安装 (WireGuard + Web)"
        echo "2) 升级/重新安装"
        echo "3) 重启服务"
        echo "4) 停止服务"
        echo "5) 卸载"
        echo "6) 数据管理"
        echo "7) 查看日志"
        echo "8) 查看状态"
        echo "9) 更改管理员密码"
        echo "0) 退出"
        echo ""
        echo "安装目录: $config_dir"
        echo ""
        echo -n "请选择 [0-9]: "
        read choice

        case $choice in
            1)
                full_install "$config_dir"
                ;;
            2)
                upgrade_install "$config_dir"
                ;;
            3)
                restart_services "$config_dir"
                ;;
            4)
                stop_containers "all"
                log_info "所有服务已停止"
                ;;
            5)
                uninstall "$config_dir"
                ;;
            6)
                data_management "$config_dir"
                ;;
            7)
                view_logs
                ;;
            8)
                detect_server_ip
                show_status
                ;;
            9)
                detect_server_ip
                change_admin_password "$config_dir"
                ;;
            0)
                echo ""
                log_info "退出"
                exit 0
                ;;
            *)
                log_error "无效选项，请重新选择"
                ;;
        esac

        # 暂停，等待用户查看结果
        if [ "$choice" != "0" ]; then
            echo ""
            echo -n "按 Enter 键继续..."
            read
        fi
    done
}

# 主函数
main() {
    # 解析命令行参数
    QUICK_MODE=false
    DEPLOY_MODE=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --mode)
                DEPLOY_MODE="$2"
                shift 2
                ;;
            --quick)
                QUICK_MODE=true
                shift
                ;;
            install)
                full_install "$INSTALL_DIR"
                exit 0
                ;;
            upgrade)
                upgrade_install "$INSTALL_DIR"
                exit 0
                ;;
            restart)
                restart_services "$INSTALL_DIR"
                exit 0
                ;;
            stop)
                stop_containers "all"
                log_info "所有服务已停止"
                exit 0
                ;;
            uninstall)
                uninstall "$INSTALL_DIR"
                exit 0
                ;;
            logs)
                view_logs
                exit 0
                ;;
            status)
                detect_server_ip
                show_status
                exit 0
                ;;
            password)
                detect_server_ip
                change_admin_password "$INSTALL_DIR"
                exit 0
                ;;
            backup)
                backup_data "$INSTALL_DIR"
                exit 0
                ;;
            -h|--help)
                echo "WireGuard Manager 部署脚本"
                echo ""
                echo "用法:"
                echo "  $0 [命令] [选项]"
                echo ""
                echo "命令:"
                echo "  install              完整安装"
                echo "  upgrade              升级/重新安装"
                echo "  restart              重启服务"
                echo "  stop                 停止服务"
                echo "  uninstall            卸载"
                echo "  logs                 查看日志"
                echo "  status               查看状态"
                echo "  password             更改管理员密码"
                echo "  backup               备份数据"
                echo ""
                echo "选项:"
                echo "  --install-dir DIR    指定安装目录 (默认: /etc/wireguard-manager)"
                echo "  --mode MODE          部署模式: all|wireguard|web (快速模式)"
                echo "  --quick              快速模式，跳过交互"
                echo ""
                echo "示例:"
                echo "  $0                                    # 交互式菜单"
                echo "  $0 install                            # 完整安装"
                echo "  $0 install --install-dir /opt/wg     # 自定义安装目录"
                echo "  $0 --mode wireguard --quick          # 快速部署 WireGuard"
                echo "  $0 status                            # 查看状态"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                echo "使用 '$0 --help' 查看帮助"
                exit 1
                ;;
        esac
    done

    # 快速模式
    if [ "$QUICK_MODE" = true ]; then
        check_docker
        detect_server_ip
        create_config_dir "$INSTALL_DIR"
        enable_ip_forward

        case "$DEPLOY_MODE" in
            wireguard)
                build_images "wireguard"
                start_wireguard "$INSTALL_DIR"
                ;;
            web)
                build_images "web"
                start_web "$INSTALL_DIR" "${ADMIN_USERNAME:-admin}" "$ADMIN_PASSWORD"
                ;;
            all|"")
                build_images "all"
                start_wireguard "$INSTALL_DIR"
                start_web "$INSTALL_DIR" "${ADMIN_USERNAME:-admin}" "$ADMIN_PASSWORD"
                ;;
            *)
                log_error "无效的部署模式: $DEPLOY_MODE"
                exit 1
                ;;
        esac

        log_info "快速部署完成"
        exit 0
    fi

    # 默认启动交互式菜单
    interactive_menu "$INSTALL_DIR"
}

# 运行主函数
main "$@"
