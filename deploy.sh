#!/usr/bin/env bash
# ============================================================================
# Cosmo Mail 一键部署脚本
# Copyright (C) 2026 magiccode (魔法代码)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# Project: https://github.com/qwernot/Cosmomail
# License: AGPL-3.0 (https://github.com/qwernot/Cosmomail/blob/main/LICENSE)
#
# 用法: ./deploy.sh [命令] [选项]
#
# 命令:
#   install     安装并启动服务（默认）
#   start       启动服务
#   stop        停止服务
#   restart     重启服务
#   status      查看运行状态
#   update      更新到最新版本
#   uninstall   卸载（保留数据，可选删除）
#   logs        查看日志
#   version     显示版本信息
#   doctor      环境自检
#   help        显示帮助信息
#
# 选项:
#   --yes, -y   跳过确认提示（非交互模式）
#   --version V  指定安装版本（默认 latest）
#   --port P     指定监听端口（默认 8080）
#
# 安装后可通过 cosmomail 命令管理:
#   cosmomail status / start / stop / restart / update / uninstall / logs / version / doctor
# ============================================================================
set -euo pipefail

# ─── 颜色定义 ──────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── 配置 ──────────────────────────────────────────
REPO="qwernot/Cosmomail"
REPO_URL="https://github.com/${REPO}"
API_URL="https://api.github.com/repos/${REPO}"
RELEASE_URL="${API_URL}/releases/latest"

INSTALL_DIR="/opt/cosmomail"
BIN_NAME="cosmomail"
DATA_DIR="/var/lib/cosmomail"
LOG_FILE="/var/log/cosmomail.log"
CONFIG_DIR="${INSTALL_DIR}/config"
SERVICE_NAME="cosmomail"
CLI_BIN="/usr/local/bin/${BIN_NAME}"
DEFAULT_PORT=8080

# 全局变量
TARGET_OS=""
TARGET_ARCH=""
TARGET_VERSION=""
TARGET_PORT="${DEFAULT_PORT}"
INTERACTIVE=true
IN_RESTRICTED_ENV=false

# ─── 工具函数 ──────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

print_banner() {
    local ver="$(get_installed_version 2>/dev/null || echo '?.?.?')"
    echo ""
    # ─── 主 Logo（青色粗体，figlet slant 字体）───────
    printf '\033[1;36m'
    cat << 'BANNER'
    __  ___            _                      _ __
   /  |/  /___ _____ _(_)________ ___  ____ _(_) /
  / /|_/ / __ `/ __ `/ / ___/ __ `__ \/ __ `/ / / 
 / /  / / /_/ / /_/ / / /__/ / / / / / /_/ / / /  
/_/  /_/\__,_/\__, /_/\___/_/ /_/ /_/\__,_/_/_/   
             /____/                              
BANNER
    printf '\033[0m'

    # ─── 版本号 + 副标题框─────────────────────────────
    # 中文字符为双宽度(×2)，内容区=8空格+6中文(12列)+8空格=28列
    printf "\033[0;36m                              v%s\n" "${ver}"
    printf '\033[1;37m'
    printf '          ┌────────────────────────────┐\n'
    printf '          │        一键部署工具        │\n'
    printf '          └────────────────────────────┘\n'
    printf '\033[0m\n'
}

# ═══════════════════════════════════════════════════════
# 第一部分：平台检测模块
# ═══════════════════════════════════════════════════════

# 检测操作系统类型 (linux/darwin/windows)
detect_os() {
    local os_name="$(uname -s)"
    case "${os_name,,}" in
        linux*)   echo "linux" ;;
        darwin*)  echo "darwin" ;;
        msys*|mingw*|cygwin*) echo "windows" ;;
        *)       die "不支持的操作系统: ${os_name}" ;;
    esac
}

# 检测 CPU 架构 (amd64/arm64)
detect_arch() {
    local arch_name="$(uname -m)"
    case "${arch_name,,}" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf)  die "不支持 ARMv7，请使用 ARM64 (aarch64) 设备" ;;
        i386|i686)     die "不支持 32 位系统，请使用 64 位系统" ;;
        *)             die "不支持的 CPU 架构: ${arch_name}" ;;
    esac
}

# 检测当前 Linux 环境是否缺少系统服务管理器
is_restricted_env() {
    is_linux && ! command -v systemctl >/dev/null 2>&1
}

# 检测 Linux 发行版名称
detect_distro() {
    if [[ "$(uname -s)" != "Linux"* ]]; then
        echo "macOS"
        return
    fi

    # 优先使用 /etc/os-release (最可靠)
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "${ID,,}" in
            debian|ubuntu|linuxmint|pop|elementary)
                echo "debian" ;;
            centos|rhel|rocky|alma|fedora|ol)
                echo "rhel" ;;
            alpine)
                echo "alpine" ;;
            arch|manjaro|endeavouros)
                echo "arch" ;;
            opensuse*|suse|sles)
                echo "opensuse" ;;
            *)
                echo "${ID:-unknown}" ;;
        esac
        return
    fi

    # 兜底探测
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        echo "opensuse"
    else
        echo "unknown-linux"
    fi
}

# 获取可用的包管理器名称
get_package_manager() {
    local distro
    distro="$(detect_distro)"
    case "${distro}" in
        debian)
            if command -v apt-get &>/dev/null; then echo "apt"; return; fi
            ;;
        rhel)
            if command -v dnf &>/dev/null; then echo "dnf"; return; fi
            if command -v yum &>/dev/null; then echo "yum"; return; fi
            ;;
        alpine)
            if command -v apk &>/dev/null; then echo "apk"; return; fi
            ;;
        arch)
            if command -v pacman &>/dev/null; then echo "pacman"; return; fi
            ;;
        opensuse)
            if command -v zypper &>/dev/null; then echo "zypper"; return; fi
            ;;
        macOS)
            if command -v brew &>/dev/null; then echo "brew"; return; fi
            ;;
    esac

    # 全局兜底扫描
    for pm in apt dnf yum apk pacman zypper brew; do
        if command -v "${pm}" &>/dev/null; then
            echo "${pm}"
            return
        fi
    done

    echo "unknown"
}

is_linux() { [[ "$(uname -s)" == Linux* ]]; }
is_macos() { [[ "$(uname -s)" == Darwin* ]]; }

# ═══════════════════════════════════════════════════════
# 第一点五：GitHub 镜像代理（国内加速）
# ═══════════════════════════════════════════════════════

# 镜像代理列表（按优先级排序，依次尝试）
# 格式: "前缀" - 将 GitHub URL 前面加上此前缀即可使用镜像
MIRROR_PREFIXES=(
    ""                                          # 原始地址（优先直连）
    "https://gh-proxy.com/"                    # gh-proxy 镜像
    "https://ghfast.top/"                      # ghfast 镜像
)

# jsDelivr CDN 专用格式: https://cdn.jsdelivr.net/gh/{user}/{repo}@{branch}/{path}
# 仅适用于 raw.githubusercontent.com 文件下载，不适用于 releases 和 API
JSDELVR_BASE="https://cdn.jsdelivr.net/gh/${REPO}"

# 判断 URL 是否为 raw 文件（可用 jsDelivr 加速）
_is_raw_url() {
    [[ "$1" == *"raw.githubusercontent.com"* ]]
}

# 判断 URL 是否为 GitHub API / Release（只能用通用代理）
_is_github_api_or_release() {
    [[ "$1" == *".github.com/"* ]] && ! _is_raw_url "$1"
}

# 将 raw.githubusercontent.com URL 转为 jsDelivr CDN URL
_to_jsdelivr_url() {
    local url="$1"
    # https://raw.githubusercontent.com/qwernot/Cosmomail/main/deploy.sh
    # → https://cdn.jsdelivr.net/gh/qwernot/Cosmomail@main/deploy.sh
    echo "${url}" | sed -E 's|https?://raw\.githubusercontent\.com/[^/]+/[^/]+/|'"${JSDELVR_BASE}"'@|'
}

# 获取所有可尝试的 URL 列表（原始 + jsDelivr(仅raw) + 各镜像代理）
_get_mirror_urls() {
    local url="$1"

    # 1. 始终先尝试直连（短超时快速判断）
    printf '%s\n' "${url}"

    # 2. raw 文件额外提供 jsDelivr CDN 加速
    if _is_raw_url "${url}"; then
        printf '%s\n' "$(_to_jsdelivr_url "${url}")"
    fi

    # 3. 通用镜像代理链（适用于 API/Release/raw 全类型）
    local prefix
    for prefix in "${MIRROR_PREFIXES[@]}"; do
        [ -z "${prefix}" ] && continue  # 跳过空元素（已用原始 URL）
        printf '%s\n' "${prefix}${url}"
    done
}

# 单次下载尝试（内部用），成功返回 0，失败返回 1
_download_attempt() {
    local url="$1"
    local dest="$2"
    local timeout="${3:-30}"  # 默认超时 30 秒

    if command -v curl &>/dev/null; then
        curl -fSL --connect-timeout "${timeout}" --max-time 300 \
            --speed-limit 1024 --speed-time 15 \
            --progress-bar -o "${dest}" "${url}" 2>/dev/null && return 0
    elif command -v wget &>/dev/null; then
        wget --timeout="${timeout}" --progress=bar:force:noscroll \
            -O "${dest}" "${url}" 2>/dev/null && return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════
# 第二部分：依赖检查与安装模块
# ═══════════════════════════════════════════════════════

# 通过包管理器安装包列表
install_packages() {
    local packages=("$@")
    if [ ${#packages[@]} -eq 0 ]; then return; fi

    local pm
    pm="$(get_package_manager)"

    case "${pm}" in
        apt)
            apt-get update -qq && apt-get install -y -qq "${packages[@]}" ;;
        dnf)
            dnf install -y -q "${packages[@]}" ;;
        yum)
            yum install -y -q "${packages[@]}" ;;
        pacman)
            pacman -S --noconfirm "${packages[@]}" ;;
        apk)
            apk add "${packages[@]}" ;;
        zypper)
            zypper --non-interactive install "${packages[@]}" ;;
        brew)
            brew install "${packages[@]}" ;;
        *)
            die "无法自动安装依赖 (${packages[*]})。未知的包管理器，请手动安装后再试" ;;
    esac
}

# 确保下载工具可用 (curl/wget)
ensure_download_tool() {
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        info "安装下载工具 (curl)..."
        install_packages curl || die "无法自动安装 curl/wget，请手动安装后再试"
        success "curl 已安装"
    fi
}

# 确保必要工具存在
ensure_required_tools() {
    local missing=()

    for tool in tar gzip; do
        if ! command -v "${tool}" &>/dev/null; then
            missing+=("${tool}")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        info "安装缺失的工具: ${missing[*]}"
        install_packages "${missing[@]}"
        success "工具已安装: ${missing[*]}"
    fi
}

# 系统资源预检 (磁盘空间 >= 200MB, 内存 >= 256MB)
check_system_resources() {
    info "检查系统资源..."

    # 磁盘空间检查 (目标安装路径所在分区)
    local check_dir="${INSTALL_DIR}"
    if [ ! -d "${check_dir}" ]; then
        check_dir="/"
    fi

    local disk_free_kb
    disk_free_kb=$(df -k "${check_dir}" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    local disk_free_mb=$((disk_free_kb / 1024))

    if [ "${disk_free_mb}" -lt 200 ]; then
        warn "磁盘剩余空间不足: ${disk_free_mb}MB < 200MB (建议至少 500MB)"
        warn "安装可能失败或影响程序正常运行"
    else
        success "磁盘空间充足: ${disk_free_mb}MB 可用"
    fi

    # 内存检查
    if is_linux && [ -r /proc/meminfo ]; then
        local mem_total_kb
        mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
        local mem_total_mb=$((mem_total_kb / 1024))

        if [ "${mem_total_mb}" -lt 256 ]; then
            warn "内存较小: ${mem_total_mb}MB < 256MB，可能影响性能"
        else
            success "内存充足: ${mem_total_mb}MB 总计"
        fi
    fi

    # 受限运行环境提示
    if is_restricted_env; then
        IN_RESTRICTED_ENV=true
        warn "检测到 受限运行环境环境 — systemd 服务不可用，将使用前台/后台模式运行"
    fi
}

# 端口冲突检测
check_port_conflict() {
    local port="${1:-${TARGET_PORT}}"

    info "检查端口 ${port} 占用情况..."

    local occupied=false
    local occupier=""

    if command -v ss &>/dev/null; then
        occupier=$(ss -tlnp 2>/dev/null | grep ":${port}" || true)
    elif command -v netstat &>/dev/null; then
        occupier=$(netstat -tlnp 2>/dev/null | grep ":${port}" || true)
    elif command -v lsof &>/dev/null; then
        occupier=$(lsof -i ":${port}" 2>/dev/null || true)
    fi

    if [ -n "${occupier}" ]; then
        occupied=true
        warn "端口 ${port} 已被占用:"
        echo "  ${occupier}" | head -3 | sed 's/^/    /'
        warn "如果端口冲突，Cosmo Mail 可能无法正常启动。可通过 --port 参数指定其他端口"
    else
        success "端口 ${port} 可用"
    fi
}

# 防火墙状态检测与提示
check_firewall() {
    local port="${1:-${TARGET_PORT}}"

    if is_linux; then
        if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
            warn "UFW 防火墙已启用，如需外部访问请执行:"
            echo -e "  ${DIM}sudo ufw allow ${port}/tcp${NC}"
        fi

        if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
            warn "firewalld 防火墙已启用，如需外部访问请执行:"
            echo -e "  ${DIM}sudo firewall-cmd --add-port=${port}/tcp --permanent && sudo firewall-cmd --reload${NC}"
        fi

        if command -v iptables &>/dev/null && iptables -L INPUT -n 2>/dev/null | grep -q "DROP\|REJECT"; then
            warn "iptables 规则可能限制端口访问，请确认 ${port} 端口已放行"
        fi
    fi
}

# ═══════════════════════════════════════════════════════
# 第三部分：下载与二进制安装模块
# ═══════════════════════════════════════════════════════

# 获取下载文件名后缀
get_binary_suffix() {
    local os="$1"
    local arch="$2"
    case "${os}-${arch}" in
        linux-amd64)      echo "" ;;
        linux-arm64)      echo "-arm64" ;;
        darwin-amd64)     echo "-macos-x86_64" ;;
        darwin-arm64)     echo "-macos-arm64" ;;
        windows-amd64)    echo ".exe" ;;
        *)                die "无法确定二进制文件名: ${os}/${arch}" ;;
    esac
}

# 获取最新版本号（支持镜像自动切换）
get_latest_version() {
    # 优先使用本地 git tag（源码部署场景）
    if command -v git &>/dev/null && [ -d ".git" ] 2>/dev/null; then
        local tag
        tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
        if [ -n "${tag}" ]; then
            echo "${tag}"
            return
        fi
    fi

    # 从 GitHub API 获取，带镜像自动切换
    local api_urls
    api_urls="$(_get_mirror_urls "${RELEASE_URL}")"

    local version=""
    local http_code=""
    local api_url
    while IFS= read -r api_url; do
        [ -z "${api_url}" ] && continue

        if command -v curl &>/dev/null; then
            # 同时提取 HTTP 状态码和响应体（用于区分网络问题 vs 无 Release）
            http_code="$(curl -fsSL -o /tmp/cosmomail_api_resp.json \
                -w '%{http_code}' --connect-timeout 10 --max-time 30 \
                "${api_url}" 2>/dev/null || true)"

            version="$(grep '"tag_name"' /tmp/cosmomail_api_resp.json 2>/dev/null | head -1 \
                | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/' || true)"

            # 404 = 该仓库暂未发布 Release，无需继续尝试镜像
            if [ "${http_code}" = "404" ]; then
                rm -f /tmp/cosmomail_api_resp.json
                die "该仓库暂未发布任何 Release（HTTP 404）。
  请先在 GitHub 上创建一个 Release: ${REPO_URL}/releases/new
  或使用 --version V.x.y.z 手动指定版本"
            fi
        elif command -v wget &>/dev/null; then
            wget --timeout=30 -qO- "${api_url}" > /tmp/cosmomail_api_resp.json 2>/dev/null || true
            version="$(grep '"tag_name"' /tmp/cosmomail_api_resp.json 2>/dev/null | head -1 \
                | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/' || true)"
        fi

        if [ -n "${version}" ]; then
            rm -f /tmp/cosmomail_api_resp.json
            echo "${version}"
            return
        fi
    done <<< "${api_urls}"

    rm -f /tmp/cosmomail_api_resp.json
    die "无法获取最新版本号，请检查网络连接或手动指定版本 (--version V.x.y.z)
  提示: 国内用户如遇 GitHub 访问问题，脚本会自动切换代理；如全部失败请检查服务器是否能访问外网
  Release 页面: ${REPO_URL}/releases"
}

# 通用文件下载（自动切换镜像）
download_file() {
    local url="$1"
    local dest="$2"

    info "正在下载: $(echo "${url}" | sed -E 's|https?://[^/]+/||')"

    # 尝试原始 URL（短超时，快速判断直连是否可用）
    info "正在使用直连下载..."
    if _download_attempt "${url}" "${dest}" 10; then
        success "下载成功 (直连)"
        return
    fi

    warn "直连失败，自动切换镜像加速..."

    local mirror_urls
    mirror_urls="$(_get_mirror_urls "${url}")"

    local mirror_url
    while IFS= read -r mirror_url; do
        # 跳过空行和原始 URL（已试过）
        [ -z "${mirror_url}" ] && continue
        [ "${mirror_url}" = "${url}" ] && continue

        # 提取镜像名称用于日志显示
        local mirror_name="${mirror_url%%://*}"
        case "${mirror_name}" in
            *gh-proxy.com*)         mirror_name="gh-proxy 镜像" ;;
            *ghfast.top*)           mirror_name="ghfast 镜像" ;;
            *.jsdelivr.net*)        mirror_name="jsDelivr CDN" ;;
            *)                      mirror_name="未知源" ;;
        esac

        info "正在使用 ${mirror_name} 下载..."
        if _download_attempt "${mirror_url}" "${dest}" 30; then
            success "下载成功 (${mirror_name})"
            return
        fi
    done <<< "${mirror_urls}"

    die "所有镜像均下载失败，请检查网络或手动下载后放置到 ${dest}"
}

# 下载并安装二进制文件
install_binary() {
    local target_os="$1"
    local target_arch="$2"
    local version="$3"

    local suffix
    suffix="$(get_binary_suffix "${target_os}" "${target_arch}")"
    local binary_url="${REPO_URL}/releases/download/${version}/${BIN_NAME}${suffix}"

    local binary_path="${INSTALL_DIR}/${BIN_NAME}${suffix}"
    local staged_path="${binary_path}.download.$$"
    local final_bin="${INSTALL_DIR}/${BIN_NAME}"
    local backup_path="${final_bin}.bak.$(date +%Y%m%d%H%M%S)"

    info "正在下载 Cosmo Mail ${version} (${target_os}/${target_arch})..."
    info "下载地址: ${binary_url}"

    # 始终下载到同目录临时文件。中断或下载失败时不会截断正在运行的程序，
    # 完成后通过同一文件系统内的 mv 原子替换。
    if ! download_file "${binary_url}" "${staged_path}"; then
        rm -f "${staged_path}"
        return 1
    fi
    if [ ! -s "${staged_path}" ]; then
        rm -f "${staged_path}"
        die "下载文件为空，已保留当前版本"
    fi
    chmod +x "${staged_path}"

    # 备份旧版本后再原子替换，确保随时可回滚。
    if [ -f "${final_bin}" ] && [ ! -L "${final_bin}" ]; then
        cp -p "${final_bin}" "${backup_path}"
        info "旧版本已备份: ${backup_path}"
    fi
    mv -f "${staged_path}" "${binary_path}"

    # 非默认平台通过统一入口软链接到带后缀的文件。
    if [ -n "${suffix}" ]; then
        ln -sf "$(basename "${binary_path}")" "${final_bin}"
    fi

    success "二进制已安装: ${final_bin}"
    echo "${final_bin}"
}

# 获取已安装的版本号 (从二进制或记录文件)
get_installed_version() {
    local bin="${INSTALL_DIR}/${BIN_NAME}"
    if [ -x "${bin}" ]; then
        # 尝试从文件名/元数据获取（Go 二进制无 --version 时用备用方案）
        local ver_file="${INSTALL_DIR}/.version"
        if [ -f "${ver_file}" ]; then
            cat "${ver_file}"
        else
            echo "installed"
        fi
    else
        echo ""
    fi
}

# ═══════════════════════════════════════════════════════
# 第四部分：目录与权限初始化
# ═══════════════════════════════════════════════════════

init_directories() {
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${DATA_DIR}/data"
    mkdir -p "$(dirname "${LOG_FILE}")"

    # 复制部署脚本到安装目录（供 CLI wrapper 使用）
    cp -f "$0" "${INSTALL_DIR}/deploy.sh" 2>/dev/null || true
    chmod +x "${INSTALL_DIR}/deploy.sh" 2>/dev/null || true

    success "目录已创建: ${INSTALL_DIR}, ${DATA_DIR}"
}

# ─── 权限检查 ─────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此操作需要 root 权限，请使用 sudo 运行:"
        echo -e "  ${DIM}sudo $0 $*${NC}"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════
# 第五部分：服务管理模块
# ═══════════════════════════════════════════════════════

# 创建 Linux systemd 服务文件
create_systemd_service() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    cat > "${service_file}" << SERVICEEOF
[Unit]
Description=Cosmo Mail Mail Management Service
Documentation=https://github.com/qwernot/Cosmomail
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${BIN_NAME}
WorkingDirectory=${DATA_DIR}
Restart=on-failure
RestartSec=5

# 环境变量配置
Environment=COSMOMAIL_ENV=production
Environment=COSMOMAIL_PORT=${TARGET_PORT}
Environment=COSMOMAIL_HOST=0.0.0.0
Environment=COSMOMAIL_DSN=${DATA_DIR}/data/cosmomail.db

# 日志输出
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

# 安全加固
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${DATA_DIR}
PrivateTmp=true
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SERVICEEOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    success "systemd 服务已创建: ${service_file}"
}

# 创建 macOS LaunchDaemon 服务
create_launchd_service() {
    local plist_file="/Library/LaunchDaemons/com.cosmomail.service.plist"

    cat > "${plist_file}" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cosmomail.service</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/${BIN_NAME}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${DATA_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_FILE}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>COSMOMAIL_ENV</key>
        <string>production</string>
        <key>COSMOMAIL_PORT</key>
        <string>${TARGET_PORT}</string>
        <key>COSMOMAIL_HOST</key>
        <string>0.0.0.0</string>
        <key>COSMOMAIL_DSN</key>
        <string>${DATA_DIR}/data/cosmomail.db</string>
    </dict>
</dict>
</plist>
PLISTEOF

    launchctl load "${plist_file}" 2>/dev/null || true
    success "LaunchDaemon 服务已创建: ${plist_file}"
}

# 启动服务
svc_start() {
    check_root start

    if is_restricted_env; then
        # 无系统服务管理器时直接后台运行
        if pgrep -f "${INSTALL_DIR}/${BIN_NAME}" &>/dev/null; then
            warn "进程已在运行中"
        else
            cd "${DATA_DIR}" && COSMOMAIL_ENV=production COSMOMAIL_PORT="${TARGET_PORT}" \
                nohup "${INSTALL_DIR}/${BIN_NAME}" >> "${LOG_FILE}" 2>&1 &
            sleep 1
            success "已在 受限环境中启动 (PID: $!)"
        fi
        svc_status
        return
    fi

    if is_linux; then
        systemctl start "${SERVICE_NAME}" || die "启动失败"
        sleep 1
    else
        launchctl start "com.cosmomail.service" 2>/dev/null \
            || (cd "${DATA_DIR}" && "${INSTALL_DIR}/${BIN_NAME}" &)
        sleep 1
    fi
    svc_status
    success "服务已启动"
}

# 停止服务
svc_stop() {
    check_root stop

    if is_restricted_env; then
        pkill -f "${INSTALL_DIR}/${BIN_NAME}" 2>/dev/null || true
        success "后台进程已停止"
        return
    fi

    if is_linux; then
        systemctl stop "${SERVICE_NAME}" 2>/dev/null || warn "服务可能未在运行"
    else
        launchctl stop "com.cosmomail.service" 2>/dev/null \
            || pkill -f "${INSTALL_DIR}/${BIN_NAME}" 2>/dev/null || true
    fi
    success "服务已停止"
}

# 重启服务
svc_restart() {
    check_root restart

    if is_restricted_env; then
        svc_stop
        sleep 1
        svc_start
        return
    fi

    if is_linux; then
        systemctl restart "${SERVICE_NAME}" || die "重启失败"
    else
        svc_stop
        sleep 1
        svc_start
    fi
    success "服务已重启"
}

# 服务状态查看
svc_status() {
    local running=false

    if is_linux && ! is_restricted_env; then
        if systemctl is-active "${SERVICE_NAME}" &>/dev/null; then
            running=true
            echo -e "${GREEN}● 服务状态: 运行中${NC}"
            systemctl status "${SERVICE_NAME}" --no-pager -l 2>/dev/null | head -12
        else
            echo -e "${RED}○ 服务状态: 未运行${NC}"
            # 显示失败原因
            systemctl status "${SERVICE_NAME}" --no-pager -l 2>/dev/null | grep -E "Active:|Main PID:" | head -3 | sed 's/^/  /'
        fi
    elif is_restricted_env; then
        if pgrep -f "${INSTALL_DIR}/${BIN_NAME}" &>/dev/null; then
            running=true
            echo -e "${GREEN}● 服务状态: 运行中 (受限环境模式)${NC}"
            ps aux | grep "[${BIN_NAME:0:1}]${BIN_NAME:1}" | head -3 | sed 's/^/  /'
        else
            echo -e "${RED}○ 服务状态: 未运行${NC}"
        fi
    else
        if pgrep -f "${INSTALL_DIR}/${BIN_NAME}" &>/dev/null; then
            running=true
            echo -e "${GREEN}● 服务状态: 运行中${NC}"
            ps aux | grep "[${BIN_NAME:0:1}]${BIN_NAME:1}" | head -5 | sed 's/^/  /'
        else
            echo -e "${RED}○ 服务状态: 未运行${NC}"
        fi
    fi

    echo ""

    # 端口监听信息
    local listen_port="${TARGET_PORT}"
    local port_info=""

    if command -v ss &>/dev/null; then
        port_info="$(ss -tlnp 2>/dev/null | grep ":${listen_port}" || true)"
    elif command -v netstat &>/dev/null; then
        port_info="$(netstat -tlnp 2>/dev/null | grep ":${listen_port}" || true)"
    elif command -v lsof &>/dev/null; then
        if lsof -i ":${listen_port}" &>/dev/null; then
            port_info="(listening)"
        fi
    fi

    if [ -n "${port_info}" ] || ${running}; then
        info "端口监听: ${listen_port}"
    else
        warn "端口 ${listen_port}: 未监听"
    fi

    # 关键路径信息
    echo ""
    info "访问地址: http://localhost:${listen_port}"
    info "数据目录: ${DATA_DIR}"
    info "日志文件: ${LOG_FILE}"
    info "配置目录: ${CONFIG_DIR}"

    # 版本信息
    local installed_ver
    installed_ver="$(get_installed_version 2>/dev/null || echo '?')"
    if [ -n "${installed_ver}" ]; then
        info "已装版本: ${installed_ver}"
    fi
}

# 查看日志
svc_logs() {
    local lines="${1:-100}"

    if [ -f "${LOG_FILE}" ]; then
        tail -"${lines}" "${LOG_FILE}" 2>/dev/null || warn "无法读取日志"
    elif is_linux && ! is_restricted_env; then
        journalctl -u "${SERVICE_NAME}" --no-pager -n "${lines}" 2>/dev/null \
            || warn "无日志可读 (journalctl)"
    else
        warn "日志文件不存在: ${LOG_FILE}"
    fi
}

# ═══════════════════════════════════════════════════════
# 第六部分：CLI Wrapper 生成模块
# ═══════════════════════════════════════════════════════

# 创建 /usr/local/bin/cosmomail CLI 命令（自包含，不依赖 deploy.sh）
create_cli_wrapper() {
    local wrapper="${CLI_BIN}"

    cat > "${wrapper}" << 'WRAPPEREOF'
#!/usr/bin/env bash
# ============================================================================
# Cosmo Mail CLI - 自包含命令行工具
# 用法: cosmomail [命令] [选项]
# 注意: 此文件由 install 自动生成，基础操作不依赖 deploy.sh
# ============================================================================
set -euo pipefail

# ─── 配置 ──────────────────────────────────────────
COSMOMAIL_INSTALL_DIR="/opt/cosmomail"
COSMOMAIL_DATA_DIR="/var/lib/cosmomail"
COSMOMAIL_LOG_FILE="/var/log/cosmomail.log"
COSMOMAIL_SERVICE="cosmomail"
DEPLOY_SCRIPT="${COSMOMAIL_INSTALL_DIR}/deploy.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── 工具函数 ──────────────────────────────────────
_detect_os() {
    case "$(uname -s)" in
        Linux)  echo "linux" ;;
        Darwin) echo "macos" ;;
        *)      echo "other" ;;
    esac
}

_is_restricted_env() {
    [ "$(uname -s 2>/dev/null)" = "Linux" ] && ! command -v systemctl >/dev/null 2>&1
}

_is_linux()  { [ "$(_detect_os)" = "linux" ]; }
_is_macos()  { [ "$(_detect_os)" = "macos" ]; }

_ensure_root() {
    if [ $EUID -ne 0 ]; then
        exec sudo "$0" "$@"
    fi
}

# 检查 deploy.sh 是否可用，不可用时给出友好提示
_check_deploy_script() {
    if [ ! -x "${DEPLOY_SCRIPT}" ] && [ ! -f "${DEPLOY_SCRIPT}" ]; then
        error "部署脚本不存在: ${DEPLOY_SCRIPT}"
        echo ""
        warn "此功能需要部署脚本支持，请重新下载:"
        echo "  curl -fsSL https://raw.githubusercontent.com/qwernot/Cosmomail/main/deploy.sh -o ${DEPLOY_SCRIPT}"
        echo "  chmod +x ${DEPLOY_SCRIPT}"
        echo ""
        echo "或者直接执行:"
        echo "  curl -fsSL https://raw.githubusercontent.com/qwernot/Cosmomail/main/deploy.sh | sudo bash -s -- $*"
        exit 1
    fi
}

show_help() {
    echo ""
    echo -e "${CYAN}${BOLD}Cosmo Mail - 命令行工具${NC}"
    echo ""
    echo "用法: cosmomail <命令> [选项]"
    echo ""
    echo "命令:"
    echo "  status       查看服务运行状态"
    echo "  start        启动服务"
    echo "  stop         停止服务"
    echo "  restart      重启服务"
    echo "  update       更新到最新版本 (需要部署脚本)"
    echo "  logs [N]     查看最近 N 行日志 (默认100)"
    echo "  version      显示版本信息"
    echo "  doctor       环境健康自检 (需要部署脚本)"
    echo "  uninstall    卸载程序 (需要部署脚本)"
    echo "  update-script 更新部署脚本到最新版"
    echo "  help, -h     显示此帮助"
    echo ""
    echo "选项:"
    echo "  -y, --yes    跳过确认提示"
    echo ""
    echo "示例:"
    echo "  cosmomail status          # 查看状态"
    echo "  cosmomail logs 50         # 查看50行日志"
    echo "  cosmomail update -y       # 无交互更新"
    echo ""
}

# ─── 状态查询（自包含）──────────────────────────────
_cmd_status() {
    local bin="${COSMOMAIL_INSTALL_DIR}/cosmomail"
    local running="否"

    if _is_restricted_env; then
        pgrep -f "${bin}" &>/dev/null && running="是 (后台模式)"
    elif _is_linux; then
        if systemctl is-active --quiet "${COSMOMAIL_SERVICE}" 2>/dev/null; then
            running="是 (systemd active)"
        else
            pgrep -f "${bin}" &>/dev/null && running="是 (进程运行中)"
        fi
    elif _is_macos; then
        launchctl print "com.cosmomail.service" &>/dev/null 2>&1 && running="是 (launchd)"
    fi

    echo ""
    echo -e "${CYAN}${BOLD}Cosmo Mail 服务状态${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  运行状态:   ${running}"
    echo "  二进制:     ${bin}$([ -x "${bin}" ] || echo ' (缺失)')"
    echo "  数据目录:   ${COSMOMAIL_DATA_DIR}"

    if [ -f "${COSMOMAIL_INSTALL_DIR}/.version" ]; then
        echo "  已装版本:   $(cat "${COSMOMAIL_INSTALL_DIR}/.version")"
    fi

    local port="${COSMOMAIL_PORT:-8080}"
    echo "  监听端口:   ${port}"

    if _is_linux; then
        echo ""
        systemctl status "${COSMOMAIL_SERVICE}" 2>/dev/null | head -15 || true
    fi
}

# ─── 日志查看（自包含）──────────────────────────────
_cmd_logs() {
    local lines="${1:-100}"

    if [ -f "${COSMOMAIL_LOG_FILE}" ]; then
        echo ""
        echo -e "${CYAN}${BOLD}最近 ${lines} 行日志${NC} (${COSMOMAIL_LOG_FILE})"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        tail -n "${lines}" "${COSMOMAIL_LOG_FILE}" 2>/dev/null || error "无法读取日志"
        return
    fi

    if _is_linux && command -v journalctl >/dev/null 2>&1; then
        journalctl -u "${COSMOMAIL_SERVICE}" -n "${lines}" --no-pager
        return
    fi

    error "没有可用的 Cosmo Mail 日志"
    exit 1
}

# ─── 版本信息（自包含）──────────────────────────────
_cmd_version() {
    local bin="${COSMOMAIL_INSTALL_DIR}/cosmomail"

    if [ ! -x "${bin}" ]; then
        error "Cosmo Mail 未安装或二进制文件缺失"
        exit 1
    fi

    echo ""
    echo -e "${CYAN}${BOLD}Cosmo Mail${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  安装路径:  ${bin}"
    echo "  数据目录:  ${COSMOMAIL_DATA_DIR}"
    echo "  日志文件:  ${COSMOMAIL_LOG_FILE}"

    if [ -f "${COSMOMAIL_INSTALL_DIR}/.version" ]; then
        echo "  版本信息:  $(cat "${COSMOMAIL_INSTALL_DIR}/.version")"
    fi

    echo "  服务名称:  ${COSMOMAIL_SERVICE}"

    local fsize fmod
    fsize=$(stat -c%s "${bin}" 2>/dev/null || stat -f%z "${bin}" 2>/dev/null || echo "?")
    fmod=$(stat -c%y "${bin}" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "${bin}" 2>/dev/null || echo "?")
    echo "  文件大小:  $(( fsize / 1024 )) KB"
    echo "  修改时间:  ${fmod}"
}

# ─── 更新部署脚本（自包含）───────────────────────────
_cmd_update_script() {
    local script_url="https://raw.githubusercontent.com/qwernot/Cosmomail/main/deploy.sh"
    local backup="${DEPLOY_SCRIPT}.bak.$(date +%Y%m%d%H%M%S)"
    local tmpfile="${COSMOMAIL_INSTALL_DIR}/.deploy.sh.tmp"

    info "正在从 GitHub 获取最新部署脚本..."
    echo "  来源: ${script_url}"

    # 检查下载工具
    if command -v curl &>/dev/null; then
        curl -fsSL --connect-timeout 10 --max-time 60 -o "${tmpfile}" "${script_url}" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -q --timeout=60 -O "${tmpfile}" "${script_url}" 2>/dev/null
    else
        error "找不到 curl 或 wget，无法下载"
        exit 1
    fi

    if [ ! -s "${tmpfile}" ]; then
        error "下载失败或文件为空，请检查网络连接"
        rm -f "${tmpfile}"
        exit 1
    fi

    # 验证是合法的 bash 脚本（简单检查）
    if ! head -1 "${tmpfile}" | grep -qE '^#!/usr/bin/env bash|^#!/bin/bash'; then
        error "下载的文件不是有效的 Bash 脚本"
        rm -f "${tmpfile}"
        exit 1
    fi

    # 备份旧版本
    if [ -f "${DEPLOY_SCRIPT}" ]; then
        cp -f "${DEPLOY_SCRIPT}" "${backup}" 2>/dev/null || true
        info "旧版本已备份: ${backup}"
    fi

    # 替换为新版
    mv -f "${tmpfile}" "${DEPLOY_SCRIPT}"
    chmod +x "${DEPLOY_SCRIPT}"

    ok "部署脚本已更新: ${DEPLOY_SCRIPT}"
}

# ════════════════════════════════════════════════════
# 主路由
# ════════════════════════════════════════════════════
cmd="${1:-help}"
shift 2>/dev/null || true

case "${cmd}" in
    status)
        _cmd_status
        ;;
    start)
        _ensure_root start "$@" || true
        info "正在启动 Cosmo Mail 服务..."
        if _is_restricted_env; then
            cd "${COSMOMAIL_DATA_DIR}" && nohup "${COSMOMAIL_INSTALL_DIR}/cosmomail" >> "${COSMOMAIL_LOG_FILE}" 2>&1 &
            sleep 2
        elif _is_linux; then
            systemctl start "${COSMOMAIL_SERVICE}"
        elif _is_macos; then
            launchctl start "com.cosmomail.service" 2>/dev/null || true
        fi
        ok "服务启动完成"
        ;;
    stop)
        _ensure_root stop "$@" || true
        info "正在停止 Cosmo Mail 服务..."
        if _is_restricted_env; then
            pkill -f "${COSMOMAIL_INSTALL_DIR}/cosmomail" 2>/dev/null || true
        elif _is_linux; then
            systemctl stop "${COSMOMAIL_SERVICE}"
        elif _is_macos; then
            launchctl stop "com.cosmomail.service" 2>/dev/null || true
        fi
        ok "服务已停止"
        ;;
    restart)
        _ensure_root restart "$@" || true
        info "正在重启 Cosmo Mail 服务..."
        if _is_restricted_env; then
            pkill -f "${COSMOMAIL_INSTALL_DIR}/cosmomail" 2>/dev/null || true
            sleep 1
            cd "${COSMOMAIL_DATA_DIR}" && nohup "${COSMOMAIL_INSTALL_DIR}/cosmomail" >> "${COSMOMAIL_LOG_FILE}" 2>&1 &
            sleep 2
        elif _is_linux; then
            systemctl restart "${COSMOMAIL_SERVICE}"
        elif _is_macos; then
            launchctl stop "com.cosmomail.service" 2>/dev/null || true
            sleep 1
            launchctl start "com.cosmomail.service" 2>/dev/null || true
        fi
        ok "服务重启完成"
        ;;
    logs)
        _cmd_logs "${1:-100}"
        ;;
    version|--version|-V)
        _cmd_version
        ;;
    update|uninstall|doctor)
        # 这些命令依赖部署脚本，检测其是否存在
        _check_deploy_script
        exec "${DEPLOY_SCRIPT}" "${cmd}" "$@"
        ;;
    update-script)
        # 自包含：直接从 GitHub 下载最新部署脚本替换本地副本
        _ensure_root update-script "$@" || true
        _cmd_update_script
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        error "未知命令: ${cmd}"
        echo "使用 'cosmomail help' 查看帮助"
        exit 1
        ;;
esac
WRAPPEREOF

    chmod +x "${wrapper}"
    success "CLI 命令已注册: ${wrapper}"
}

# 移除 CLI wrapper
remove_cli_wrapper() {
    if [ -L "${CLI_BIN}" ] || [ -f "${CLI_BIN}" ]; then
        # 如果是本脚本生成的 wrapper 则移除
        if head -5 "${CLI_BIN}" 2>/dev/null | grep -qE "(由 deploy.sh install 自动生成|自包含命令行工具)"; then
            rm -f "${CLI_BIN}"
            info "CLI 命令已移除: ${CLI_BIN}"
        else
            warn "${CLI_BIN} 不是由 deploy.sh 创建，跳过删除"
        fi
    fi
}

# ═══════════════════════════════════════════════════════
# 第七部分：主流程命令
# ═══════════════════════════════════════════════════════

# ─── 安装 ───────────────────────────────────────────
cmd_install() {
    check_root install
    print_banner

    # 0. 检测是否已安装
    local installed_ver=""
    installed_ver="$(get_installed_version 2>/dev/null || echo '')"
    if [ -n "${installed_ver}" ]; then
        info "检测到已安装版本: ${installed_ver}"

        # 获取最新版本
        local latest_ver="${TARGET_VERSION}"
        if [ -z "${latest_ver}" ]; then
            latest_ver="$(get_latest_version 2>/dev/null || echo '')"
        fi

        # 无法获取远程版本时，直接提示已安装并退出
        if [ -z "${latest_ver}" ]; then
            warn "无法获取远程版本信息，跳过重复安装"
            echo ""
            echo -e "  ${YELLOW}Cosmo Mail 已安装 (v${installed_ver})${NC}"
            echo "  如需重新安装，请先执行: $0 uninstall"
            echo "  或执行更新:           $0 update"
            exit 0
        fi

        info "最新可用版本: ${latest_ver}"

        # 比较版本，无更新则退出
        if [ "${installed_ver}" = "${latest_ver}" ]; then
            success "当前已是最新版本 (${installed_ver})"
            echo ""
            echo -e "  ${GREEN}无需更新${NC}，如需重装请先: $0 uninstall"
            exit 0
        fi

        # 有新版本，询问用户
        echo ""
        echo -e "  ${YELLOW}发现新版本: ${CYAN}${installed_ver}${YELLOW} → ${BOLD}${latest_ver}${NC}"
        if ${INTERACTIVE}; then
            read -rp "  是否立即更新? [Y/n] " confirm
            if [[ "${confirm:-Y}" =~ ^[Nn]$ ]]; then
                info "已取消，保持当前版本 v${installed_ver}"
                exit 0
            fi
        else
            info "非交互模式，自动执行更新..."
        fi

        # 用户确认后走更新流程（停止服务→下载新版→重启）
        cmd_update
        return
    fi

    # 1. 环境检测
    TARGET_OS="$(detect_os)"
    TARGET_ARCH="$(detect_arch)"

    if [ "${TARGET_OS}" == "windows" ]; then
        die "Windows 不支持此脚本，请直接从 GitHub Release 下载 exe 文件运行"
    fi

    local distro
    distro="$(detect_distro)"
    info "操作系统: $(uname -s) (${distro})"
    info "CPU 架构: $(uname -m) → ${TARGET_ARCH}"
    info "目标端口:  ${TARGET_PORT}"

    # 2. 系统资源预检
    check_system_resources

    # 3. 端口占用检查
    check_port_conflict "${TARGET_PORT}"

    # 4. 防火墙提示
    check_firewall "${TARGET_PORT}"

    # 5. 安装依赖工具
    ensure_download_tool
    ensure_required_tools

    # 6. 初始化目录
    init_directories

    # 7. 获取版本并下载
    local version="${TARGET_VERSION}"
    if [ -z "${version}" ]; then
        version="$(get_latest_version)"
    fi
    info "目标版本: ${version}"

    local final_bin
    final_bin="$(install_binary "${TARGET_OS}" "${TARGET_ARCH}" "${version}")"

    # 记录版本号
    echo "${version}" > "${INSTALL_DIR}/.version"

    # 8. 验证二进制
    info "验证二进制文件..."
    if [ -x "${final_bin}" ]; then
        # Go 编译的二进制无 --version 参数时通过 file 命令验证
        local file_type
        file_type="$(file "${final_bin}" 2>/dev/null | head -1 || echo '')"
        if echo "${file_type}" | grep -qiE "executable|ELF|Mach-O"; then
            success "二进制验证通过: ${file_type}"
        else
            warn "二进制文件异常: ${file_type}"
        fi
    fi

    # 9. 创建服务管理
    if is_restricted_env; then
        info "受限运行环境 — 跳过系统服务创建"
    elif is_linux; then
        create_systemd_service
    else
        create_launchd_service
    fi

    # 10. 注册全局命令
    create_cli_wrapper

    # 11. 启动服务
    echo ""
    info "正在启动服务..."
    if is_restricted_env; then
        cd "${DATA_DIR}" && COSMOMAIL_ENV=production COSMOMAIL_PORT="${TARGET_PORT}" \
            nohup "${final_bin}" >> "${LOG_FILE}" 2>&1 &
        sleep 2
    elif is_linux; then
        systemctl start "${SERVICE_NAME}"
        sleep 2
    else
        launchctl start "com.cosmomail.service" 2>/dev/null || true
        sleep 2
    fi

    # 12. 输出汇总信息
    print_summary "install" "${version}"
}

# ─── 更新 ───────────────────────────────────────────
cmd_update() {
    check_root update
    print_banner
    info "检查更新..."

    local new_version
    if [ -n "${TARGET_VERSION}" ]; then
        new_version="${TARGET_VERSION}"
    else
        new_version="$(get_latest_version)"
    fi

    local current_version
    current_version="$(get_installed_version || echo "unknown")"

    info "当前版本: ${current_version}"
    info "最新版本: ${new_version}"

    if [ "${current_version}" = "${new_version}" ]; then
        success "当前已是最新版本 (${new_version})"
        print_summary "update" "${new_version}"
        return
    fi

    # 确认操作
    if ${INTERACTIVE}; then
        warn "即将从 ${current_version} 更新至 ${new_version}"
        read -rp "确认继续? [Y/n] " confirm
        if [[ "${confirm:-Y}" =~ ^[Nn]$ ]]; then
            info "已取消更新"
            return
        fi
    fi

    # 执行更新
    svc_stop 2>/dev/null || true
    sleep 1

    install_binary "${TARGET_OS:-$(detect_os)}" "${TARGET_ARCH:-$(detect_arch)}" "${new_version}"
    echo "${new_version}" > "${INSTALL_DIR}/.version"

    svc_start 2>/dev/null || true

    print_summary "update" "${new_version}"
}

# ─── 卸载 ───────────────────────────────────────────
cmd_uninstall() {
    check_root uninstall
    print_banner

    warn "即将卸载 Cosmo Mail 服务"
    echo ""
    echo "  程序目录: ${INSTALL_DIR}"
    echo "  数据目录: ${DATA_DIR} （包含数据库和附件）"
    echo "  CLI 命令: ${CLI_BIN}"
    echo ""

    local delete_data="n"
    local confirm="n"

    if ${INTERACTIVE}; then
        read -rp "是否同时删除数据(数据库/附件)? [y/N] " delete_data
        read -rp "确认卸载 Cosmo Mail? [y/N] " confirm

        if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
            info "已取消卸载"
            return
        fi
    else
        info "非交互模式：仅卸载程序，保留数据"
    fi

    # 1. 停止服务
    svc_stop 2>/dev/null || true
    sleep 1

    # 2. 移除系统服务
    if is_linux && ! is_restricted_env && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
        ok "systemd 服务已移除"
    fi

    if [ -f "/Library/LaunchDaemons/com.cosmomail.service.plist" ]; then
        launchctl unload "/Library/LaunchDaemons/com.cosmomail.service.plist" 2>/dev/null || true
        rm -f "/Library/LaunchDaemons/com.cosmomail.service.plist"
        ok "LaunchDaemon 已移除"
    fi

    # 3. 移除 CLI 命令
    remove_cli_wrapper

    # 4. 删除程序文件
    rm -rf "${INSTALL_DIR}"
    ok "程序文件已删除"

    # 5. 可选删除数据
    if [[ "${delete_data}" =~ ^[Yy]$ ]]; then
        rm -rf "${DATA_DIR}"
        rm -f "${LOG_FILE}"
        ok "数据和日志已删除"
    else
        info "数据已保留: ${DATA_DIR}"
        info "如需彻底清理请执行: sudo rm -rf ${DATA_DIR}"
    fi

    print_summary "uninstall" ""
}

# ─── 自检 ───────────────────────────────────────────
cmd_doctor() {
    print_banner
    echo -e "${BOLD}环境健康自检${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local all_ok=true
    local total_checks=0
    local passed_checks=0

    # 辅助函数
    check_item() {
        local label="$1"
        shift
        total_checks=$((total_checks + 1))

        if "$@"; then
            passed_checks=$((passed_checks + 1))
            printf "  ${GREEN}✔ %-35s %s${NC}\n" "${label}" "正常"
        else
            all_ok=false
            printf "  ${RED}✘ %-35s %s${NC}\n" "${label}" "异常"
        fi
    }

    warn_item() {
        local label="$1"
        local msg="$2"
        total_checks=$((total_checks + 1))
        printf "  ${YELLOW}⚠ %-35s %s${NC}\n" "${label}" "${msg}"
    }

    echo ""
    echo -e "${BOLD}[系统环境]${NC}"

    check_item "操作系统" true
    check_item "内核版本" true
    info "  内核: $(uname -sr), 发行版: $(detect_distro)"
    check_item "CPU 架构" true
    info "  架构: $(uname -m) → $(detect_arch)"

    echo ""
    echo -e "${BOLD}[程序文件]${NC}"

    check_item "二进制文件" [ -x "${INSTALL_DIR}/${BIN_NAME}" ]
    if [ -x "${INSTALL_DIR}/${BIN_NAME}" ]; then
        local fsize
        fsize=$(ls -lh "${INSTALL_DIR}/${BIN_NAME}" 2>/dev/null | awk '{print $5}')
        info "  大小: ${fsize}, 路径: ${INSTALL_DIR}/${BIN_NAME}"
    fi

    check_item "部署脚本" [ -f "${INSTALL_DIR}/deploy.sh" ]
    check_item "版本记录" [ -f "${INSTALL_DIR}/.version" ] && info "  版本: $(cat "${INSTALL_DIR}/.version" 2>/dev/null || echo '?')"

    echo ""
    echo -e "${BOLD}[数据目录]${NC}"

    check_item "数据主目录" [ -d "${DATA_DIR}" ]
    check_item "数据库文件" [ -f "${DATA_DIR}/data/cosmomail.db" ]

    if [ -f "${DATA_DIR}/data/cosmomail.db" ]; then
        local db_size
        db_size=$(ls -lh "${DATA_DIR}/data/cosmomail.db" 2>/dev/null | awk '{print $5}')
        info "  DB 大小: ${db_size}"
    fi

    check_item "日志文件" [ -f "${LOG_FILE}" ]

    echo ""
    echo -e "${BOLD}[服务状态]${NC}"

    local svc_running=false
    if is_restricted_env; then
        if pgrep -f "${INSTALL_DIR}/${BIN_NAME}" &>/dev/null; then
            svc_running=true
            check_item "后台进程" true
        else
            check_item "后台进程" false
        fi
    elif is_linux && [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        check_item "systemd 服务文件" true
        if systemctl is-active "${SERVICE_NAME}" &>/dev/null; then
            svc_running=true
            check_item "systemd 运行状态" true
        else
            check_item "systemd 运行状态" false
            local state
            state=$(systemctl is-failed "${SERVICE_NAME}" 2>/dev/null || echo "unknown")
            info "  状态详情: ${state}"
        fi
    else
        check_item "系统服务" false
        info "  提示: 未找到服务定义，可能未完整安装"
    fi

    echo ""
    echo -e "${BOLD}[网络与端口]${NC}"

    check_item "网络连通性" true
    # 简单的网络测试
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null || ping -c 1 -W 2 223.5.5.5 &>/dev/null; then
        : # pass
    else
        warn_item "外网连接" "无法连接 DNS (可能是离线环境)"
    fi

    local port_info=""
    local target_p="${TARGET_PORT}"
    if command -v ss &>/dev/null; then
        port_info=$(ss -tlnp 2>/dev/null | grep ":${target_p}" || true)
    elif command -v netstat &>/dev/null; then
        port_info=$(netstat -tlnp 2>/dev/null | grep ":${target_p}" || true)
    fi

    if [ -n "${port_info}" ]; then
        check_item "端口 ${target_p} 监听" ${svc_running}
    else
        if ${svc_running}; then
            warn_item "端口 ${target_p} 监听" "服务运行但端口未监听，可能启动失败"
        else
            check_item "端口 ${target_p} 监听" false
        fi
    fi

    echo ""
    echo -e "${BOLD}[CLI 命令]${NC}"

    check_item "cosmomail 命令" [ -x "${CLI_BIN}" ]
    if [ -x "${CLI_BIN}" ]; then
        info "  路径: ${CLI_BIN}"
    fi

    check_item "curl/wget" command -v curl &>/dev/null || command -v wget &>/dev/null

    echo ""
    echo -e "${BOLD}[资源状态]${NC}"

    local df_kb
    df_kb=$(df -k "${DATA_DIR:-/}" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
    local df_mb=$((df_kb / 1024))
    if [ "${df_mb}" -ge 200 ]; then
        check_item "磁盘空间 (>=200MB)" true
        info "  可用: ~${df_mb} MB"
    else
        check_item "磁盘空间 (>=200MB)" false
        info "  仅剩: ~${df_mb} MB"
    fi

    if is_linux && [ -r /proc/meminfo ]; then
        local mem_mb
        mem_mb=$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
        if [ "${mem_mb}" -ge 256 ]; then
            check_item "内存 (>=256MB)" true
            info "  总计: ~${mem_mb} MB"
        else
            check_item "内存 (>=256MB)" false
            info "  仅: ~${mem_mb} MB"
        fi
    fi

    # ─── 汇总 ─────────────────────────────────────
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if ${all_ok}; then
        echo -e "  ${GREEN}全部通过! ${passed_checks}/${total_checks} 项检查正常${NC}"
    else
        local failed=$((total_checks - passed_checks))
        echo -e "  ${YELLOW}部分问题: ${passed_checks}/${total_checks} 通过, ${failed} 项需关注${NC}"
        echo ""
        echo "  建议:"
        printf '  - 如服务未运行: \033[0;36msudo cosmomail start\033[0m\n'
        printf '  - 如缺少文件:   \033[0;36msudo ./deploy.sh install\033[0m\n'
        printf '  - 如端口未监听: 检查日志: \033[0;36msudo cosmomail logs\033[0m\n'
    fi

    echo ""
}

# ─── 版本信息 ───────────────────────────────────────
cmd_version() {
    local installed_ver
    installed_ver="$(get_installed_version || echo '未安装')"
    local latest_ver=""

    echo ""
    echo -e "${CYAN}${BOLD}Cosmo Mail 版本信息${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  已安装版本:  ${installed_ver}"

    # 尝试获取远程最新版（可选，失败不阻塞）
    if command -v curl &>/dev/null || command -v wget &>/dev/null; then
        latest_ver="$(get_latest_version 2>/dev/null || true)"
        if [ -n "${latest_ver}" ]; then
            if [ "${installed_ver}" = "${latest_ver}" ]; then
                echo "  最新版本:    ${latest_ver} ${GREEN}(已是最新)${NC}"
            else
                echo "  最新版本:    ${latest_ver} ${YELLOW}(可升级)${NC}"
            fi
        else
            echo "  最新版本:    (无法获取，请检查网络)"
        fi
    fi

    echo ""
    echo "  安装位置:    ${INSTALL_DIR}/${BIN_NAME}"
    echo "  数据目录:    ${DATA_DIR}"
    echo "  日志文件:    ${LOG_FILE}"
    echo "  CLI 命令:    ${CLI_BIN}"
    echo "  系统服务:    ${SERVICE_NAME}"
    echo "  目标平台:    $(detect_os)/$(detect_arch)"
    echo "  发行版:      $(detect_distro)"
    echo "  包管理器:    $(get_package_manager)"
    echo "  受限运行环境: $(is_restricted_env && echo '是' || echo '否')"
    echo ""
}

# ═══════════════════════════════════════════════════════
# 第八部分：统一汇总输出
# ═══════════════════════════════════════════════════════

# 统一的信息汇总输出
print_summary() {
    local action="$1"
    local version="${2:-$(get_installed_version || echo '?')}"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"

    case "${action}" in
        install)
            echo -e "  ${GREEN}${BOLD}✅ Cosmo Mail 安装成功！${NC}"
            echo ""
            echo -e "  版本信息:  ${CYAN}${version}${NC}"
            echo -e "  访问地址:  ${CYAN}http://localhost:${TARGET_PORT}${NC}"
            echo -e "  数据目录:  ${CYAN}${DATA_DIR}${NC}"
            echo -e "  日志文件:  ${CYAN}${LOG_FILE}${NC}"
            echo -e "  二进制:    ${CYAN}${INSTALL_DIR}/${BIN_NAME}${NC}"
            echo -e "  CLI 命令:  ${CYAN}${CLI_BIN}${NC}"
            echo ""
            echo -e "  ${BOLD}常用命令:${NC}"
            echo -e "  ${DIM}  cosmomail status${NC}     查看服务状态"
            echo -e "  ${DIM}  cosmomail logs${NC}       查看运行日志"
            echo -e "  ${DIM}  cosmomail restart${NC}    重启服务"
            echo -e "  ${DIM}  cosmomail update${NC}     更新到最新版"
            echo -e "  ${DIM}  cosmomail doctor${NC}     环境健康自检"
            echo -e "  ${DIM}  cosmomail uninstall${NC}  卸载程序"
            ;;

        update)
            echo -e "  ${GREEN}${BOLD}🔄 Cosmo Mail 更新完成！${NC}"
            echo ""
            echo -e "  当前版本:  ${CYAN}${version}${NC}"
            echo -e "  访问地址:  ${CYAN}http://localhost:${TARGET_PORT}${NC}"
            echo ""
            echo -e "  使用 ${CYAN}cosmomail status${NC} 确认服务运行正常"
            ;;

        uninstall)
            echo -e "  ${YELLOW}${BOLD}🗑️  Cosmo Mail 已卸载${NC}"
            echo ""
            echo -e "  程序文件已从 ${INSTALL_DIR} 移除"
            echo -e "  CLI 命令已从 ${CLI_BIN} 移除"
            echo ""
            echo -e "  如需重新安装: ${CYAN}./deploy.sh install${NC}"
            ;;

        *)
            echo -e "  操作完成: ${action}"
            ;;
    esac

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo ""

    # 自动打开浏览器（仅 install 且有桌面环境）
    if [ "${action}" = "install" ]; then
        if command -v xdg-open &>/dev/null; then
            (sleep 1 && xdg-open "http://localhost:${TARGET_PORT}" &) 2>/dev/null || true
        elif command -v open &>/dev/null; then
            (sleep 1 && open "http://localhost:${TARGET_PORT}" &) 2>/dev/null || true
        fi
    fi
}

# ═══════════════════════════════════════════════════════
# 第九部分：入口与参数解析
# ═══════════════════════════════════════════════════════

# 交互式操作菜单（无参数运行时触发）
_show_interactive_menu() {
    # 检测是否已安装
    local installed=""
    if [ -f "${INSTALL_DIR}/${BIN_NAME}" ] 2>/dev/null || command -v "${BIN_NAME}" &>/dev/null; then
        installed="(已安装)"
    fi

    echo ""
    echo -e "${CYAN}${BOLD}请选择操作${NC} ${YELLOW}${installed}${NC}"
    echo ""
    echo "  1) 安装 / 重装 install"
    echo "  2) 更新版本     update"
    echo "  3) 卸载程序     uninstall"
    echo "  4) 查看状态     status"
    echo "  5) 环境自检     doctor"
    echo "  6) 查看帮助     help"
    echo "  0) 退出"
    echo ""

    while true; do
        printf "${CYAN}> 请输入选项 [0-6]: ${NC}"
        read -r choice

        case "${choice}" in
            1) SELECTED_CMD="install"; return ;;
            2) SELECTED_CMD="update"; return ;;
            3) SELECTED_CMD="uninstall"; return ;;
            4) SELECTED_CMD="status"; return ;;
            5) SELECTED_CMD="doctor"; return ;;
            6|''|h|H|help)
                show_help
                # 帮助显示后重新提示选择
                echo ""
                printf "${CYAN}> 请输入选项 [0-6]: ${NC}"
                continue
                ;;
            0|q|Q|exit|quit)
                echo -e "${DIM}已退出。${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请输入 0-6${NC}"
                ;;
        esac
    done
}

show_help() {
    echo ""
    echo -e "${CYAN}${BOLD}Cosmo Mail 一键部署工具${NC}"
    echo ""
    echo "用法: $0 [命令] [选项]"
    echo ""
    echo "命令 (不带参数运行时显示交互菜单):"
    echo "  install       安装并启动服务"
    echo "  start         启动服务"
    echo "  stop          停止服务"
    echo "  restart       重启服务"
    echo "  status        查看运行状态"
    echo "  update        更新到最新版本"
    echo "  uninstall     卸载（保留数据，加 --yes 删除数据仍会询问）"
    echo "  logs [N]      查看最近 N 条日志（默认 100）"
    echo "  version       显示版本信息"
    echo "  doctor        环境健康自检"
    echo "  help          显示此帮助信息"
    echo ""
    echo "选项:"
    echo "  --yes, -y     跳过所有确认提示（非交互模式）"
    echo "  --version V   指定安装/更新的版本号"
    echo "  --port P      指定监听端口（默认: ${DEFAULT_PORT}）"
    echo ""
    echo "示例:"
    echo "  $0 install                          # 默认安装"
    echo "  $0 install --port 3000              # 指定端口安装"
    echo "  $0 update -y                        # 无交互更新"
    echo "  $0 install --version v1.2.0         # 安装指定版本"
    echo "  $0 logs 50                          # 查看 50 行日志"
    echo ""
    echo "仓库: ${REPO_URL}"
    echo "文档: https://github.com/qwernot/Cosmomail/wiki"
    echo ""
    echo "安装后使用 cosmomail 命令管理:"
    echo "  cosmomail status | start | stop | restart | update | logs | doctor | version"
    echo ""
}

main() {
    # 解析选项
    local cmd=""
    local cmd_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)
                INTERACTIVE=false
                shift
                ;;
            --version)
                TARGET_VERSION="$2"
                shift 2
                ;;
            --port)
                TARGET_PORT="$2"
                shift 2
                ;;
            install|start|stop|restart|status|update|uninstall|logs|log|doctor|version|help|--help|-h)
                cmd="$1"
                shift
                # 收集后续作为子命令参数
                if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]] && [[ ! "$1" =~ ^(install|start|stop|restart|status|update|uninstall|logs|log|doctor|version|help)$ ]]; then
                    cmd_args=("$@")
                    shift $#
                fi
                ;;
            *)
                # 未知选项，如果是第一个位置参数则当作命令
                if [ -z "${cmd}" ]; then
                    cmd="$1"
                else
                    die "未知选项: $1 (使用 '$0 help' 查看帮助)"
                fi
                shift
                ;;
        esac
    done

    # 无参数时显示交互菜单
    if [ -z "${cmd}" ]; then
        if [ "${INTERACTIVE}" = "true" ] && [ -t 0 ]; then
            _show_interactive_menu
            cmd="${SELECTED_CMD:-help}"
        else
            # 非交互环境（管道/Cron）默认安装
            cmd="install"
        fi
    fi

    # 路由分发
    case "${cmd}" in
        install)
            cmd_install ;;
        start)
            svc_start ;;
        stop)
            svc_stop ;;
        restart)
            svc_restart ;;
        status)
            svc_status ;;
        update)
            cmd_update ;;
        uninstall|remove)
            cmd_uninstall ;;
        log|logs)
            svc_logs "${cmd_args[0]:-100}" ;;
        version|--version|-V)
            cmd_version ;;
        doctor)
            cmd_doctor ;;
        help|--help|-h)
            show_help ;;
        *)
            die "未知命令: ${cmd}。使用 '$0 help' 或 '${BIN_NAME} help' 查看帮助" ;;
    esac

    exit 0
}

main "$@"
