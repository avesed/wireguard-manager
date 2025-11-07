#!/bin/bash
# WireGuard Manager - 一键安装脚本

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        OS=$(uname -s)
    fi

    log_info "检测到操作系统: $OS"
}

# 检查并安装 Docker
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_info "Docker 已安装: $(docker --version)"
        return 0
    fi

    log_warn "Docker 未安装，开始安装..."

    case "$OS" in
        ubuntu|debian)
            log_step "使用官方脚本安装 Docker..."
            curl -fsSL https://get.docker.com | sh

            # 将当前用户添加到 docker 组
            if [ -n "$SUDO_USER" ]; then
                usermod -aG docker "$SUDO_USER"
                log_info "用户 $SUDO_USER 已添加到 docker 组"
            fi
            ;;
        centos|rhel|fedora)
            log_step "使用官方脚本安装 Docker..."
            curl -fsSL https://get.docker.com | sh

            systemctl start docker
            systemctl enable docker

            if [ -n "$SUDO_USER" ]; then
                usermod -aG docker "$SUDO_USER"
                log_info "用户 $SUDO_USER 已添加到 docker 组"
            fi
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            echo "请手动安装 Docker: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac

    # 启动 Docker 服务
    if command -v systemctl >/dev/null 2>&1; then
        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true
    fi

    log_info "Docker 安装完成"
}

# 检查并安装 Git
install_git() {
    if command -v git >/dev/null 2>&1; then
        log_info "Git 已安装: $(git --version)"
        return 0
    fi

    log_warn "Git 未安装，开始安装..."

    case "$OS" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y git
            ;;
        centos|rhel|fedora)
            yum install -y git
            ;;
        *)
            log_error "无法自动安装 Git，请手动安装"
            exit 1
            ;;
    esac

    log_info "Git 安装完成"
}

# 检查并安装其他依赖
install_dependencies() {
    log_step "检查系统依赖..."

    # 检查 curl
    if ! command -v curl >/dev/null 2>&1; then
        log_warn "安装 curl..."
        case "$OS" in
            ubuntu|debian)
                apt-get update -qq
                apt-get install -y curl
                ;;
            centos|rhel|fedora)
                yum install -y curl
                ;;
        esac
    fi

    # 检查 tar
    if ! command -v tar >/dev/null 2>&1; then
        log_warn "安装 tar..."
        case "$OS" in
            ubuntu|debian)
                apt-get install -y tar
                ;;
            centos|rhel|fedora)
                yum install -y tar
                ;;
        esac
    fi

    log_info "系统依赖检查完成"
}

# 检查是否为交互模式
is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

# 增强的交互能力检测
detect_interaction_capability() {
    # 检测标准终端
    if [ -t 0 ] && [ -t 1 ]; then
        INTERACTION_MODE="terminal"
        return 0
    fi

    # 检测 /dev/tty 可用性
    if [ -r /dev/tty ] && [ -w /dev/tty ] 2>/dev/null; then
        INTERACTION_MODE="tty"
        return 0
    fi

    # 检测环境变量强制交互
    if [ "$FORCE_INTERACTIVE" = "true" ]; then
        INTERACTION_MODE="forced"
        return 0
    fi

    # 检测是否禁用交互
    if [ "$NO_INTERACTIVE" = "true" ] || [ "$AUTO_INSTALL" = "true" ]; then
        INTERACTION_MODE="disabled"
        return 1
    fi

    # 默认无交互能力
    INTERACTION_MODE="none"
    return 1
}

# 智能交互输入函数
interactive_read() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local timeout="${4:-30}"

    case "$INTERACTION_MODE" in
        "terminal")
            if [ -n "$timeout" ] && [ "$timeout" != "0" ]; then
                read -t "$timeout" -p "$prompt" $varname || eval "$varname=\"$default\""
            else
                read -p "$prompt" $varname
            fi
            ;;
        "tty")
            if [ -n "$timeout" ] && [ "$timeout" != "0" ]; then
                read -t "$timeout" -p "$prompt" $varname </dev/tty || eval "$varname=\"$default\""
            else
                read -p "$prompt" $varname </dev/tty
            fi
            ;;
        "forced")
            # 尝试从 /dev/tty 读取，失败则使用默认值
            read -p "$prompt" $varname </dev/tty 2>/dev/null || eval "$varname=\"$default\""
            ;;
        "disabled"|"none")
            log_info "非交互模式，使用默认值: $default"
            eval "$varname=\"$default\""
            ;;
    esac

    # 如果变量为空，使用默认值
    local current_value=$(eval "echo \$$varname")
    if [ -z "$current_value" ]; then
        eval "$varname=\"$default\""
    fi
}

# 克隆或更新仓库
clone_repository() {
    local repo_url="${REPO_URL:-https://github.com/avesed/wireguard-manager.git}"
    local install_path="${INSTALL_PATH:-$HOME/wireguard-manager}"

    log_step "准备安装到: $install_path"

    # 检查目录是否已存在
    if [ -d "$install_path" ]; then
        log_warn "目录已存在: $install_path"

        local update_choice="y"

        # 使用智能交互系统
        if detect_interaction_capability; then
            interactive_read "是否更新现有安装? (y/n) [y]: " "y" "update_choice"
        else
            log_info "非交互模式，自动更新现有安装"
        fi

        if [ "$update_choice" = "y" ] || [ "$update_choice" = "Y" ]; then
            log_step "更新现有仓库..."
            cd "$install_path"
            git pull origin main || git pull origin master
            log_info "仓库更新完成"
        else
            log_info "使用现有安装"
        fi
    else
        log_step "克隆仓库..."
        git clone "$repo_url" "$install_path"
        log_info "仓库克隆完成"
    fi

    cd "$install_path"
    INSTALL_DIR="$install_path"
}

# 下载最新版本（如果不使用 git）
download_latest() {
    local repo_url="${REPO_URL:-https://github.com/avesed/wireguard-manager}"
    local install_path="${INSTALL_PATH:-$HOME/wireguard-manager}"

    log_step "下载最新版本..."

    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # 下载最新的 release 或 main 分支
    curl -fsSL "$repo_url/archive/refs/heads/main.tar.gz" -o wireguard-manager.tar.gz

    # 创建安装目录
    mkdir -p "$install_path"

    # 解压
    tar -xzf wireguard-manager.tar.gz --strip-components=1 -C "$install_path"

    # 清理
    rm -rf "$temp_dir"

    cd "$install_path"
    INSTALL_DIR="$install_path"

    log_info "下载完成"
}

# 运行部署脚本
run_deploy() {
    log_step "运行部署脚本..."

    if [ ! -f "./deploy.sh" ]; then
        log_error "deploy.sh 未找到"
        exit 1
    fi

    chmod +x ./deploy.sh

    # 传递所有参数给 deploy.sh
    if [ -n "$AUTO_INSTALL" ]; then
        # 自动安装模式
        ./deploy.sh install --install-dir "${CONFIG_DIR:-/etc/wireguard-manager}"
    else
        # 交互式模式
        ./deploy.sh "$@"
    fi
}

# 显示欢迎信息
show_welcome() {
    echo ""
    echo "=========================================="
    echo "   WireGuard Manager 一键安装脚本"
    echo "=========================================="
    echo ""
    echo "此脚本将自动安装并配置 WireGuard Manager"
    echo ""
    echo "环境要求:"
    echo "  - 操作系统: Ubuntu/Debian/CentOS/RHEL/Fedora"
    echo "  - 需要 root 或 sudo 权限"
    echo "  - 需要互联网连接"
    echo ""
}

# 显示完成信息
show_completion() {
    echo ""
    echo "=========================================="
    log_info "安装完成！"
    echo "=========================================="
    echo ""
    echo "下一步:"
    echo "  1. 访问 Web 管理界面进行配置"
    echo "  2. 创建客户端配置"
    echo "  3. 下载配置文件或扫描二维码连接"
    echo ""
    echo "管理命令:"
    echo "  cd $INSTALL_DIR"
    echo "  ./deploy.sh          # 打开管理菜单"
    echo "  ./deploy.sh status   # 查看状态"
    echo "  ./deploy.sh logs     # 查看日志"
    echo "  ./deploy.sh password # 更改密码"
    echo ""
    echo "文档: https://github.com/avesed/wireguard-manager"
    echo "=========================================="
    echo ""
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ] && [ -z "$SUDO_USER" ]; then
        log_warn "建议使用 root 或 sudo 运行此脚本"

        # 使用智能交互系统
        if detect_interaction_capability; then
            local continue_choice="n"
            interactive_read "是否继续? (y/n) [n]: " "n" "continue_choice"

            if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
                log_info "退出安装"
                exit 0
            fi
        else
            log_warn "非交互模式，继续安装（可能需要手动处理权限问题）"
        fi
    fi
}

# 主函数
main() {
    # 初始化智能交互系统
    detect_interaction_capability

    # 显示当前交互模式
    case "$INTERACTION_MODE" in
        "terminal")
            log_info "检测到标准终端，启用完整交互模式"
            ;;
        "tty")
            log_info "检测到管道模式，通过 /dev/tty 启用交互模式"
            ;;
        "forced")
            log_info "强制交互模式已启用"
            ;;
        "disabled")
            log_info "交互模式已禁用，使用自动安装"
            ;;
        "none")
            log_info "检测到非交互环境，启用自动安装模式"
            AUTO_INSTALL=true
            ;;
    esac

    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --auto)
                AUTO_INSTALL=true
                INTERACTION_MODE="disabled"
                shift
                ;;
            --interactive)
                FORCE_INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                NO_INTERACTIVE=true
                INTERACTION_MODE="disabled"
                shift
                ;;
            --repo)
                REPO_URL="$2"
                shift 2
                ;;
            --path)
                INSTALL_PATH="$2"
                shift 2
                ;;
            --config-dir)
                CONFIG_DIR="$2"
                shift 2
                ;;
            --no-git)
                NO_GIT=true
                shift
                ;;
            -h|--help)
                echo "WireGuard Manager 一键安装脚本"
                echo ""
                echo "用法:"
                echo "  curl -fsSL https://raw.githubusercontent.com/avesed/wireguard-manager/main/install.sh | bash"
                echo "  # 注意：现在支持通过 /dev/tty 在管道模式下进行交互！"
                echo ""
                echo "本地运行:"
                echo "  bash install.sh [选项]"
                echo ""
                echo "选项:"
                echo "  --auto              自动安装模式（非交互）"
                echo "  --interactive       强制启用交互模式"
                echo "  --no-interactive    强制禁用交互模式"
                echo "  --repo URL          自定义仓库 URL (默认: github.com/avesed/wireguard-manager)"
                echo "  --path DIR          安装路径 (默认: ~/wireguard-manager)"
                echo "  --config-dir DIR    配置目录 (默认: /etc/wireguard-manager)"
                echo "  --no-git            不使用 git，直接下载压缩包"
                echo ""
                echo "环境变量:"
                echo "  FORCE_INTERACTIVE=true   # 强制启用交互模式"
                echo "  NO_INTERACTIVE=true      # 强制禁用交互模式"
                echo "  AUTO_INSTALL=true        # 自动安装模式"
                echo ""
                echo "示例:"
                echo "  # 通过 curl 一键安装（支持交互！）"
                echo "  curl -fsSL URL | bash"
                echo ""
                echo "  # 进程替换方式（最佳兼容性）"
                echo "  bash <(curl -fsSL URL)"
                echo ""
                echo "  # 强制交互模式"
                echo "  FORCE_INTERACTIVE=true curl -fsSL URL | bash"
                echo ""
                echo "  # 自动模式"
                echo "  curl -fsSL URL | bash -s -- --auto"
                echo ""
                echo "  # 自定义路径"
                echo "  curl -fsSL URL | bash -s -- --path /opt/wireguard-manager"
                exit 0
                ;;
            *)
                # 保存其他参数传递给 deploy.sh
                DEPLOY_ARGS="$DEPLOY_ARGS $1"
                shift
                ;;
        esac
    done

    # 显示欢迎信息
    show_welcome

    # 检查权限
    check_root

    # 检测操作系统
    detect_os

    # 安装依赖
    log_step "步骤 1/5: 检查并安装系统依赖..."
    install_dependencies

    # 安装 Docker
    log_step "步骤 2/5: 检查并安装 Docker..."
    install_docker

    # 安装 Git 或下载
    if [ "$NO_GIT" = true ]; then
        log_step "步骤 3/5: 下载项目文件..."
        download_latest
    else
        log_step "步骤 3/5: 检查并安装 Git..."
        install_git

        log_step "步骤 4/5: 克隆项目仓库..."
        clone_repository
    fi

    # 运行部署
    log_step "步骤 5/5: 运行部署脚本..."
    run_deploy $DEPLOY_ARGS

    # 显示完成信息
    show_completion
}

# 运行主函数
main "$@"
