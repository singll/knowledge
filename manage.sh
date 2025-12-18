#!/bin/bash
set -e

BASE_DIR="/home/knowledge/knowledge"
cd "$BASE_DIR"

# 颜色输出
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echoe -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 获取本机IP
get_ip() { hostname -I | awk '{print $1}'; }

# 检测 yq 版本类型
detect_yq_version() {
    if ! command -v yq >/dev/null 2>&1; then
        echo "not_installed"
        return
    fi

    local version_output=$(yq --version 2>&1)
    local version_num=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    # 处理异常版本 0.0.0
    if [[ "$version_num" == "0.0.0" ]]; then
        echo "corrupted"
        return
    fi

    # 检查是否是 mikefarah/go 版本
    if [[ "$version_output" =~ mikefarah ]] || [[ "$version_output" =~ "https://github.com/mikefarah" ]]; then
        echo "go"
    elif [[ "$version_output" =~ "kislyuk" ]] || [[ "$version_output" =~ "https://github.com/kislyuk" ]]; then
        echo "python"
    else
        # 尝试执行测试命令来判断
        if yq eval '.' /dev/null >/dev/null 2>&1; then
            echo "go"
        elif yq -y '.' /dev/null >/dev/null 2>&1; then
            echo "python"
        else
            echo "unknown"
        fi
    fi
}

# 强制安装/替换为 Go 版本 yq
install_yq() {
    log "检测 yq 工具..."

    local yq_type=$(detect_yq_version)

    # 处理 Python 版本、异常版本或未知版本
    if [[ "$yq_type" == "python" ]] || [[ "$yq_type" == "corrupted" ]] || [[ "$yq_type" == "unknown" ]]; then
        if [[ "$yq_type" == "corrupted" ]]; then
            warn "检测到异常版本 (0.0.0)，将强制替换..."
        else
            warn "检测到不兼容版本，将替换为 Go 版本..."
        fi

        # 尝试卸载 Python 版本
        log "清理旧版本..."
        pip uninstall -y yq >/dev/null 2>&1 || true
        pip3 uninstall -y yq >/dev/null 2>&1 || true

        # 删除可能的二进制文件
        sudo rm -f /usr/bin/yq /usr/local/bin/yq /usr/local/sbin/yq ~/.local/bin/yq
    fi

    # 如果 Go 版本已存在，直接返回
    if [[ "$yq_type" == "go" ]]; then
        local version=$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$version" && "$version" != "0.0.0" ]]; then
            log "✅ Go 版本 yq 已安装 (版本: $version)"
            return 0
        fi
    fi

    # 下载并安装 Go 版本
    log "下载 mikefarah/yq (Go 版本)..."

    # 检测系统架构
    local arch=$(uname -m)
    local yq_arch=""
    case "$arch" in
        x86_64) yq_arch="amd64" ;;
        aarch64|arm64) yq_arch="arm64" ;;
        armv7l) yq_arch="arm" ;;
        *)
            error "❌ 不支持的架构: $arch，无法自动安装 yq"
            return 1
            ;;
    esac

    # 检测操作系统
    local os_type="linux"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="darwin"
    fi

    # 安装目录
    local install_dir="/usr/local/bin"
    local need_sudo=1

    if [[ $EUID -ne 0 ]]; then
        install_dir="$HOME/.local/bin"
        mkdir -p "$install_dir"
        need_sudo=0

        # 确保目录在 PATH 中
        if [[ ":$PATH:" != *":$install_dir:"* ]]; then
            export PATH="$install_dir:$PATH"
            echo "export PATH=\"$install_dir:\$PATH\"" >> "$HOME/.bashrc"
        fi
    fi

    # 下载并安装
    if command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1; then
        local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_${os_type}_${yq_arch}"
        local yq_temp="/tmp/yq_$$"

        log "正在从 GitHub 下载 yq..."

        if command -v wget >/dev/null 2>&1; then
            wget -q --show-progress -O "$yq_temp" "$yq_url"
        else
            curl -L -o "$yq_temp" "$yq_url"
        fi

        if [[ $? -eq 0 && -f "$yq_temp" ]]; then
            # 移除旧版本
            if [[ -f "${install_dir}/yq" ]]; then
                if [[ $need_sudo -eq 1 ]]; then
                    sudo rm -f "${install_dir}/yq"
                else
                    rm -f "${install_dir}/yq"
                fi
            fi

            # 安装新版本
            if [[ $need_sudo -eq 1 ]]; then
                sudo mv "$yq_temp" "${install_dir}/yq"
                sudo chmod +x "${install_dir}/yq"
            else
                mv "$yq_temp" "${install_dir}/yq"
                chmod +x "${install_dir}/yq"
            fi

            # 验证安装
            if command -v yq >/dev/null 2>&1 && [[ $(detect_yq_version) == "go" ]]; then
                local installed_version=$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                log "✅ yq 安装成功！版本: $installed_version"
                rm -f "$yq_temp"
                return 0
            else
                error "❌ yq 安装失败或版本不正确"
                rm -f "$yq_temp"
                return 1
            fi
        else
            error "❌ yq 下载失败"
            rm -f "$yq_temp"
        fi
    else
        error "❌ 未找到 wget 或 curl，无法下载 yq"
    fi

    error "❌ 无法自动安装 yq，请手动安装: https://github.com/mikefarah/yq"
    return 1
}

# 根据 yq 类型执行命令（兼容层）
yq_run() {
    local cmd="$1"
    local file="$2"
    local in_place="${3:-false}"

    local yq_type=$(detect_yq_version)

    case "$yq_type" in
        "go")
            if [[ "$in_place" == "true" ]]; then
                yq eval "$cmd" -i "$file"
            else
                yq eval "$cmd" "$file"
            fi
            ;;
        "python")
            if [[ "$in_place" == "true" ]]; then
                # Python 版本不支持 -i，需要重定向
                yq -y "$cmd" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            else
                yq -y "$cmd" "$file"
            fi
            ;;
        *)
            error "❌ 未知的 yq 类型或 yq 未安装"
            return 1
            ;;
    esac
}

# 修复网络配置（简化版，兼容双版本）
fix_network_config() {
    local compose_file="$1"
    local target_service="$2"
    local backup_file="${compose_file}.backup.$(date +%Y%m%d_%H%M%S)"

    # 备份
    if [[ ! -f "$backup_file" ]]; then
        cp "$compose_file" "$backup_file"
        log "已备份: $(basename "$backup_file")"
    fi

    log "处理: $(basename "$compose_file") -> 服务: $target_service"

    # 添加顶级 networks
    if ! yq_run '.networks' "$compose_file" 2>/dev/null | grep -q "knowledge-net"; then
        log "添加顶级 networks..."
        yq_run '.networks.knowledge-net = {"external": true}' "$compose_file" "true"
        log "✅ 已添加顶级 networks"
    else
        log "✅ 顶级 networks 已存在"
    fi

    # 为服务添加网络
    if ! yq_run ".services.${target_service}.networks" "$compose_file" 2>/dev/null | grep -q "knowledge-net"; then
        log "为服务 $target_service 添加 knowledge-net..."
        yq_run "with(.services.${target_service}; .networks = (.networks // []) + [\"knowledge-net\"])" "$compose_file"
"true"
        log "✅ 已为服务 $target_service 添加 knowledge-net"
    else
        log "✅ 服务 $target_service 已包含 knowledge-net"
    fi
}

# 创建共享网络
create_network() {
    log "创建 Docker 网络 knowledge-net..."
    docker network create knowledge-net 2>/dev/null || true
}

# 主逻辑分支
case "$1" in
    "start")
        log "🚀 启动知识库系统..."

        # 确保 yq 工具可用（强制安装 Go 版本）
        install_yq

        create_network

        # 修复所有服务的网络配置
        fix_network_config "$BASE_DIR/ragflow/docker/docker-compose.yml" "ragflow-cpu"
        fix_network_config "$BASE_DIR/firecrawl/docker-compose.yaml" "api"
        fix_network_config "$BASE_DIR/knowledge-management/docker-compose.yml" "backend"

        # 验证配置文件语法
        log "验证 docker-compose 文件语法..."
        cd firecrawl && docker compose config -q >/dev/null 2>&1 || { error "Firecrawl 语法验证失败"; cd "$BASE_DIR"; exit 1; }
        cd "$BASE_DIR"
        cd ragflow/docker && docker compose -f docker-compose.yml config -q >/dev/null 2>&1 || { error "RAGFlow 语法验证失败"; cd "$BASE_DIR"; exit 1; }
        cd "$BASE_DIR"
        cd knowledge-management && docker compose config -q >/dev/null 2>&1 || { error "Knowledge Management 语法验证失败"; cd "$BASE_DIR"; exit 1; }
        cd "$BASE_DIR"

        # 启动服务...
        log "1/4 启动 Firecrawl..."
        cd firecrawl && docker compose up -d && cd "$BASE_DIR"

        log "2/4 启动 n8n..."
        docker start n8n >/dev/null 2>&1 || \
        docker run -d --name n8n \
          --user root \
          --restart unless-stopped \
          --network knowledge-net \
          -p 5678:5678 \
          -v n8n_data:/home/node/.n8n \
          -e TZ="Asia/Shanghai" \
          -e GENERIC_TIMEZONE="Asia/Shanghai" \
          -e N8N_HOST=0.0.0.0 \
          -e N8N_PROTOCOL=http \
          -e N8N_SECURE_COOKIE=false \
          -e N8N_BASIC_AUTH_ACTIVE=true \
          -e N8N_BASIC_AUTH_USER=admin \
          -e N8N_BASIC_AUTH_PASSWORD='llDHgate123.' \
          -e N8N_LOG_LEVEL=info \
          -e NODE_OPTIONS="--max-old-space-size=2048" \
          -e "HOST_DOCKER_INTERNAL=host.docker.internal" \
          --add-host=host.docker.internal:host-gateway \
          docker.n8n.io/n8nio/n8n

        log "3/4 启动 RAGFlow..."
        cd "$BASE_DIR/ragflow/docker" && docker compose -f docker-compose.yml up -d && cd "$BASE_DIR"

        log "等待 RAGFlow 初始化 (约 30 秒)..."
        sleep 30

        log "4/4 启动 Knowledge Management 服务..."
        cd "$BASE_DIR/knowledge-management" && docker compose up -d --build && cd "$BASE_DIR"

        # 验证连通性
        sleep 10
        log "验证服务间网络连通性..."
        docker exec knowledge-backend bash -c "\
            curl -sf http://ragflow-cpu:9380/api/v1/health && echo 'RAGFlow ✅' || echo 'RAGFlow ❌'; \
            curl -sf http://api:3002 && echo 'Firecrawl ✅' || echo 'Firecrawl ❌' \
        " 2>/dev/null || warn "连通性测试失败，请手动检查"

        IP=$(get_ip)
        log "✅ 系统启动完成！"
        echo "📊 Firecrawl: http://${IP}:3002"
        echo "🔄 n8n: http://${IP}:5678 (admin/llDHgate123.)"
        echo "📚 RAGFlow: http://${IP}:80"
        echo "☁️  Knowledge Backend: http://${IP}:5000 (健康检查: /health)"
        echo "🖥️  Knowledge Frontend: http://${IP}:8080"
        ;;

    "stop")
        log "⏹️ 停止知识库系统..."
        cd firecrawl && docker compose down && cd "$BASE_DIR"
        docker stop n8n 2>/dev/null || true
        cd ragflow/docker && docker compose -f docker-compose.yml down && cd "$BASE_DIR"
        cd knowledge-management && docker compose down && cd "$BASE_DIR"
        log "✅ 系统已停止"
        ;;

    "status")
        log "📋 查看知识库系统状态..."
        IP=$(get_ip)
        echo ""
        echo "=== Docker 容器状态 ==="
        echo ""

        # Firecrawl
        echo -n "📊 Firecrawl (api): "
        if docker ps --format '{{.Names}}' | grep -q "firecrawl-api"; then
            echo -e "${GREEN}运行中${NC} - http://${IP}:3002"
        else
            echo -e "${RED}已停止${NC}"
        fi

        # n8n
        echo -n "🔄 n8n: "
        if docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
            echo -e "${GREEN}运行中${NC} - http://${IP}:5678"
        else
            echo -e "${RED}已停止${NC}"
        fi

        # RAGFlow
        echo -n "📚 RAGFlow (ragflow-cpu): "
        if docker ps --format '{{.Names}}' | grep -q "ragflow"; then
            echo -e "${GREEN}运行中${NC} - http://${IP}:80"
        else
            echo -e "${RED}已停止${NC}"
        fi

        # Knowledge Backend
        echo -n "☁️  Knowledge Backend: "
        if docker ps --format '{{.Names}}' | grep -q "^knowledge-backend$"; then
            echo -e "${GREEN}运行中${NC} - http://${IP}:5000"
        else
            echo -e "${RED}已停止${NC}"
        fi

        # Knowledge Frontend
        echo -n "🖥️  Knowledge Frontend: "
        if docker ps --format '{{.Names}}' | grep -q "^knowledge-frontend$"; then
            echo -e "${GREEN}运行中${NC} - http://${IP}:8080"
        else
            echo -e "${RED}已停止${NC}"
        fi

        echo ""
        echo "=== 详细容器信息 ==="
        docker ps --filter "name=api" --filter "name=n8n" --filter "name=ragflow" --filter "name=knowledge" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
        ;;

    "install-yq")
        install_yq
        ;;

    *)
        echo "用法: $0 {start|stop|status|install-yq}"
        exit 1
        ;;
esac
