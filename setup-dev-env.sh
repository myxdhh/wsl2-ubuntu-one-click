#!/usr/bin/env bash
# =============================================================================
# setup-dev-env.sh — Linux 开发环境一键安装/卸载脚本
# 适用于 Ubuntu / Debian 系统（含 WSL2）
#
# 用法:
#   bash setup-dev-env.sh --install                一键安装所有组件（无交互，默认 p10k 主题）
#   bash setup-dev-env.sh --install --theme pure   一键安装（使用 pure 主题）
#   bash setup-dev-env.sh --uninstall              一键卸载所有组件（无交互）
#   bash setup-dev-env.sh                          进入交互界面
# =============================================================================

set -uo pipefail
# 注意: 去掉 set -e，改用显式错误处理，避免在某些安装失败时整个脚本退出

# ─── 颜色与样式 ───────────────────────────────────────────────────────────────
# 仅当输出到终端时使用颜色
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  {
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
    echo ""
}

# ─── 日志文件 ─────────────────────────────────────────────────────────────────
LOG_FILE="${HOME}/.setup-dev-env.log"

log_start() {
    echo "========================================" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始 $1" >> "$LOG_FILE"
}

log_end() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 完成 $1 (状态: $2)" >> "$LOG_FILE"
}

# ─── 安装错误记录 ─────────────────────────────────────────────────────────────
FAILED_COMPONENTS=()

record_failure() {
    FAILED_COMPONENTS+=("$1")
    error "$1 安装失败！详情请查看日志: $LOG_FILE"
}

print_summary() {
    echo ""
    if [[ ${#FAILED_COMPONENTS[@]} -gt 0 ]]; then
        warn "以下组件安装失败："
        for comp in "${FAILED_COMPONENTS[@]}"; do
            echo -e "  ${RED}✗${NC} $comp"
        done
        echo ""
        info "日志文件: $LOG_FILE"
    fi
}

# ─── 主题与组件选择 ──────────────────────────────────────────────────────────────────
# 可选值: p10k, pure
if [[ -f "$HOME/.zshrc" ]] && grep -q "prompt pure" "$HOME/.zshrc" 2>/dev/null; then
    SELECTED_THEME="pure"
elif [[ -d "$HOME/.zsh/pure" ]] && { [[ ! -d "$HOME/powerlevel10k" ]] && ! grep -q "powerlevel10k.zsh-theme" "$HOME/.zshrc" 2>/dev/null; }; then
    SELECTED_THEME="pure"
else
    SELECTED_THEME="p10k"
fi
# 可选为空（全选），或逗号分隔的组件标识符 (如 "rustup,volta,uv")
SELECTED_COMPONENTS=""
# 是否自动清理原脚本文件
AUTO_CLEANUP=0

# ─── 组件列表 ─────────────────────────────────────────────────────────────────
COMPONENTS=(
    "apt-deps:基础依赖包"
    "zsh:Zsh Shell"
    "ohmyzsh:Oh My Zsh"
    "rustup:Rust 工具链 (rustup)"
    "eza:eza (现代 ls 替代)"
    "yazi:yazi (终端文件管理器)"
    "theme:终端主题 (p10k/pure)"
    "zsh-autosuggestions:zsh-autosuggestions 插件"
    "zsh-syntax-highlighting:zsh-syntax-highlighting 插件"
    "volta:Volta (Node/npm/pnpm 版本管理)"
    "uv:uv (Python 版本管理)"
    "proto:proto (多语言版本管理)"
)

# ─── 工具函数 ─────────────────────────────────────────────────────────────────
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

command_exists() { command -v "$1" &>/dev/null; }

check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
            warn "当前系统 ($ID) 非 Ubuntu/Debian，部分 apt 命令可能不兼容"
            read -rp "是否继续？(y/N): " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                info "已退出"
                exit 0
            fi
        else
            info "检测到系统: $PRETTY_NAME"
        fi
    else
        warn "无法检测操作系统类型"
    fi
}

check_network() {
    info "检测网络连接..."
    if curl -sS --connect-timeout 5 https://github.com > /dev/null 2>&1; then
        success "网络连接正常"
    elif curl -sS --connect-timeout 5 https://gitee.com > /dev/null 2>&1; then
        warn "GitHub 连接失败，但国内网络可用。部分安装可能较慢"
    else
        error "网络连接失败，请检查网络后重试"
        exit 1
    fi
}

ensure_sudoers() {
    local user
    user="$(whoami)"
    if [[ "$user" == "root" ]]; then
        success "当前为 root 用户"
        return 0
    fi
    if sudo -n true 2>/dev/null; then
        success "sudoers 免密已配置"
    else
        warn "当前用户 ($user) 未配置 sudoers 免密"
        echo -e "  请以 root 身份执行以下命令后重试："
        echo -e "  ${BOLD}echo '$user ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$user${NC}"
        echo -e "  ${BOLD}sudo chmod 0440 /etc/sudoers.d/$user${NC}"
        exit 1
    fi
}

source_cargo_env() {
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
}

source_volta_env() {
    export VOLTA_HOME="$HOME/.volta"
    [[ -d "$VOLTA_HOME/bin" ]] && export PATH="$VOLTA_HOME/bin:$PATH"
}

source_uv_env() {
    [[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
}

source_proto_env() {
    export PROTO_HOME="$HOME/.proto"
    export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"
}

# ─── 安装函数 ─────────────────────────────────────────────────────────────────

install_apt_deps() {
    header "安装基础依赖包"
    log_start "apt-deps"

    # 分开 update 和 upgrade，避免 upgrade 失败导致整体失败
    info "更新软件源..."
    if ! sudo apt-get update 2>&1 | tee -a "$LOG_FILE"; then
        warn "apt-get update 部分完成（可能有源不可用），继续安装..."
    fi

    info "升级已安装的包..."
    sudo apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE" || warn "apt-get upgrade 部分失败，继续..."

    info "安装基础依赖..."
    # 使用 --no-install-recommends 减少不必要的包
    local packages=(
        curl wget git build-essential unzip gzip xz-utils
        ffmpeg p7zip-full jq poppler-utils fd-find ripgrep fzf zoxide imagemagick
        make gcc
    )

    local missing_pkgs=()
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
        success "所有基础依赖已安装"
    else
        info "需要安装: ${missing_pkgs[*]}"
        if sudo apt-get install -y "${missing_pkgs[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            success "基础依赖安装完成"
        else
            # 逐个尝试安装，避免某个包不存在导致全部失败
            warn "批量安装失败，尝试逐个安装..."
            for pkg in "${missing_pkgs[@]}"; do
                sudo apt-get install -y "$pkg" 2>&1 | tee -a "$LOG_FILE" || warn "包 $pkg 安装失败，跳过"
            done
        fi
    fi

    log_end "apt-deps" $?
}

install_zsh() {
    header "安装 Zsh"
    log_start "zsh"

    if command_exists zsh; then
        success "Zsh 已安装: $(zsh --version)"
    else
        if ! sudo apt-get install -y zsh 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "zsh"
            return 1
        fi
        success "Zsh 安装完成: $(zsh --version)"
    fi

    # 设置 zsh 为默认 shell
    if [[ "$SHELL" != *"zsh"* ]]; then
        if sudo chsh -s "$(which zsh)" "$USER" 2>&1 | tee -a "$LOG_FILE"; then
            info "已将 Zsh 设为默认 shell（下次登录生效）"
        else
            warn "chsh 失败，可手动运行: chsh -s \$(which zsh)"
        fi
    else
        info "Zsh 已是默认 shell"
    fi

    log_end "zsh" $?
}

install_ohmyzsh() {
    header "安装 Oh My Zsh"
    log_start "ohmyzsh"

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        success "Oh My Zsh 已安装"
    else
        if ! sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "ohmyzsh"
            return 1
        fi
        success "Oh My Zsh 安装完成"
    fi

    # 确保 ZSH_CUSTOM_DIR 更新（oh-my-zsh 安装后可能设置了 ZSH_CUSTOM）
    ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    log_end "ohmyzsh" $?
}

install_rustup() {
    header "安装 Rust 工具链 (rustup)"
    log_start "rustup"

    if command_exists rustc; then
        success "Rust 已安装: $(rustc --version)"
    else
        if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "rustup"
            return 1
        fi
        source_cargo_env
        success "Rust 安装完成: $(rustc --version)"
    fi

    log_end "rustup" $?
}

install_eza() {
    header "安装 eza"
    log_start "eza"
    source_cargo_env

    if ! command_exists cargo; then
        error "cargo 未找到，请先安装 Rust"
        record_failure "eza"
        return 1
    fi

    if command_exists eza; then
        success "eza 已安装: $(eza --version | head -1)"
    else
        info "正在通过 cargo 编译安装 eza（可能需要几分钟）..."
        if ! cargo install eza 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "eza"
            return 1
        fi
        success "eza 安装完成"
    fi

    log_end "eza" $?
}

install_yazi() {
    header "安装 yazi"
    log_start "yazi"
    source_cargo_env

    if ! command_exists cargo; then
        error "cargo 未找到，请先安装 Rust"
        record_failure "yazi"
        return 1
    fi

    if command_exists yazi; then
        success "yazi 已安装"
    else
        info "正在通过 cargo 编译安装 yazi（可能需要较长时间）..."
        if ! cargo install --force yazi-build 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "yazi"
            return 1
        fi
        success "yazi 安装完成"
    fi

    log_end "yazi" $?
}

install_p10k() {
    header "安装 Powerlevel10k 主题"
    log_start "p10k"

    if [[ -d "$HOME/powerlevel10k" ]]; then
        success "Powerlevel10k 已安装"
    else
        if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "p10k"
            return 1
        fi
        success "Powerlevel10k 安装完成"
    fi

    log_end "p10k" $?
}

install_pure() {
    header "安装 Pure 主题"
    log_start "pure"

    local pure_dir="$HOME/.zsh/pure"
    if [[ -d "$pure_dir" ]]; then
        success "Pure 主题已安装"
    else
        mkdir -p "$HOME/.zsh"
        if ! git clone https://github.com/sindresorhus/pure.git "$pure_dir" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "pure"
            return 1
        fi
        success "Pure 主题安装完成"
    fi

    log_end "pure" $?
}

# 根据 SELECTED_THEME 安装对应主题
install_theme() {
    if [[ "$SELECTED_THEME" == "pure" ]]; then
        install_pure
    else
        install_p10k
    fi
}

install_zsh_autosuggestions() {
    header "安装 zsh-autosuggestions"
    log_start "zsh-autosuggestions"

    local target_dir="${ZSH_CUSTOM_DIR}/plugins/zsh-autosuggestions"
    if [[ -d "$target_dir" ]]; then
        success "zsh-autosuggestions 已安装"
    else
        mkdir -p "${ZSH_CUSTOM_DIR}/plugins"
        if ! git clone https://github.com/zsh-users/zsh-autosuggestions "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "zsh-autosuggestions"
            return 1
        fi
        success "zsh-autosuggestions 安装完成"
    fi

    log_end "zsh-autosuggestions" $?
}

install_zsh_syntax_highlighting() {
    header "安装 zsh-syntax-highlighting"
    log_start "zsh-syntax-highlighting"

    local target_dir="${ZSH_CUSTOM_DIR}/plugins/zsh-syntax-highlighting"
    if [[ -d "$target_dir" ]]; then
        success "zsh-syntax-highlighting 已安装"
    else
        mkdir -p "${ZSH_CUSTOM_DIR}/plugins"
        if ! git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "zsh-syntax-highlighting"
            return 1
        fi
        success "zsh-syntax-highlighting 安装完成"
    fi

    log_end "zsh-syntax-highlighting" $?
}

install_volta() {
    header "安装 Volta (Node/npm/pnpm)"
    log_start "volta"

    if command_exists volta; then
        success "Volta 已安装: $(volta --version)"
    else
        if ! curl https://get.volta.sh | bash -s -- --skip-setup 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "volta"
            return 1
        fi
        source_volta_env
        success "Volta 安装完成"
    fi

    # 安装 node / npm / pnpm
    source_volta_env
    export VOLTA_FEATURE_PNPM=1

    info "安装 Node.js (latest LTS)..."
    if ! volta install node 2>&1 | tee -a "$LOG_FILE"; then
        warn "Node.js 安装失败"
    fi

    info "安装 npm (latest)..."
    if ! volta install npm 2>&1 | tee -a "$LOG_FILE"; then
        warn "npm 安装失败"
    fi

    info "安装 pnpm (latest)..."
    if ! volta install pnpm 2>&1 | tee -a "$LOG_FILE"; then
        warn "pnpm 安装失败"
    fi

    # 验证安装
    if command_exists node && command_exists npm && command_exists pnpm; then
        success "Node=$(node -v), npm=$(npm -v), pnpm=$(pnpm -v)"
    else
        warn "部分工具未正确安装，请手动检查"
    fi

    log_end "volta" $?
}

install_uv() {
    header "安装 uv (Python 版本管理)"
    log_start "uv"

    if command_exists uv; then
        success "uv 已安装: $(uv --version)"
    else
        if ! curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "uv"
            return 1
        fi
        source_uv_env
        success "uv 安装完成"
    fi

    source_uv_env

    info "安装 Python 3.14 并设为默认..."
    if ! uv python install 3.14 --default 2>&1 | tee -a "$LOG_FILE"; then
        warn "Python 3.14 安装失败，可能版本尚不可用"
        info "尝试安装 Python 3.13..."
        if uv python install 3.13 --default 2>&1 | tee -a "$LOG_FILE"; then
            success "已回退安装 Python 3.13"
        else
            warn "Python 安装失败，请稍后手动安装"
        fi
    else
        success "Python 3.14 已安装并设为默认"
    fi

    log_end "uv" $?
}

install_proto() {
    header "安装 proto (多语言版本管理)"
    log_start "proto"

    if command_exists proto; then
        success "proto 已安装: $(proto --version)"
    else
        if ! bash <(curl -fsSL https://moonrepo.dev/install/proto.sh) --yes 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "proto"
            return 1
        fi
        source_proto_env
        success "proto 安装完成"
    fi

    log_end "proto" $?
}

# ─── .zshrc 配置 ──────────────────────────────────────────────────────────────

configure_zshrc() {
    header "配置 .zshrc"

    local zshrc="$HOME/.zshrc"

    # 备份现有 .zshrc（仅保留最近 3 个备份避免堆积）
    if [[ -f "$zshrc" ]]; then
        cp "$zshrc" "${zshrc}.bak.$(date +%Y%m%d%H%M%S)"
        info "已备份 .zshrc"
        # 清理旧备份，仅保留最近 3 个
        ls -t "${zshrc}".bak.* 2>/dev/null | tail -n +4 | xargs -r rm -f
    fi

    # 生成管理块标记
    local MARKER_START="# >>> one-click-dev-env >>>"
    local MARKER_END="# <<< one-click-dev-env <<<"

    # 移除旧的管理块（使用固定字符串匹配避免 sed 正则问题）
    if [[ -f "$zshrc" ]]; then
        # 使用 awk 更安全地处理标记块删除
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip
        ' "$zshrc" > "${zshrc}.tmp" && mv "${zshrc}.tmp" "$zshrc"
    fi

    # 确保基础 oh-my-zsh 配置存在
    if [[ -f "$zshrc" ]] && grep -q "^ZSH_THEME=" "$zshrc"; then
        # 替换主题为空（我们使用外部主题 p10k/pure）
        sed -i 's/^ZSH_THEME=.*/ZSH_THEME=""/' "$zshrc"
    fi

    # 更新 plugins 列表
    local plugins_line='plugins=(git eza zsh-autosuggestions zsh-syntax-highlighting)'
    if [[ -f "$zshrc" ]] && grep -q "^plugins=" "$zshrc"; then
        sed -i "s/^plugins=.*/${plugins_line}/" "$zshrc"
    fi

    # eza zstyle 配置必须在 source $ZSH/oh-my-zsh.sh 之前才能生效
    # 先移除旧的 eza zstyle 行（如果有）
    if [[ -f "$zshrc" ]]; then
        sed -i "/^zstyle ':omz:plugins:eza'/d" "$zshrc"
    fi
    # 在 source $ZSH/oh-my-zsh.sh 之前插入 eza zstyle 配置
    local eza_config="# ── eza 插件配置（需在 source oh-my-zsh.sh 之前）──\nzstyle ':omz:plugins:eza' 'dirs-first' yes\nzstyle ':omz:plugins:eza' 'icons' yes\nzstyle ':omz:plugins:eza' 'hyperlink' yes"
    if [[ -f "$zshrc" ]] && grep -q "^source.*oh-my-zsh.sh" "$zshrc"; then
        sed -i "/^source.*oh-my-zsh.sh/i\\${eza_config}" "$zshrc"
    fi

    # 追加配置块（根据主题不同生成不同的配置）
    {
        echo ""
        echo "# >>> one-click-dev-env >>>"
        echo ""

        if [[ "$SELECTED_THEME" == "pure" ]]; then
            cat << 'PURE_BLOCK'
# ── Pure Theme ──
# pure 必须在 source oh-my-zsh.sh 之后加载
fpath+=("$HOME/.zsh/pure")
autoload -U promptinit; promptinit
zstyle :prompt:pure:git:stash show yes
prompt pure
PURE_BLOCK
        else
            cat << 'P10K_BLOCK'
# ── Powerlevel10k Instant Prompt ──
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ── Powerlevel10k Theme ──
[[ -f ~/powerlevel10k/powerlevel10k.zsh-theme ]] && source ~/powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
P10K_BLOCK
        fi

        cat << 'ENV_BLOCK'

# ── Volta ──
export VOLTA_HOME="$HOME/.volta"
export VOLTA_FEATURE_PNPM=1
[[ -d "$VOLTA_HOME/bin" ]] && export PATH="$VOLTA_HOME/bin:$PATH"

# ── Cargo / Rust ──
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ── uv ──
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# ── proto ──
export PROTO_HOME="$HOME/.proto"
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"

# <<< one-click-dev-env <<<
ENV_BLOCK
    } >> "$zshrc"

    success ".zshrc 配置完成 (主题: $SELECTED_THEME)"
}

# ─── 卸载函数 ─────────────────────────────────────────────────────────────────

uninstall_proto() {
    header "卸载 proto"
    if [[ -d "$HOME/.proto" ]]; then
        rm -rf "$HOME/.proto"
        success "proto 已卸载"
    else
        info "proto 未安装，跳过"
    fi
}

uninstall_uv() {
    header "卸载 uv"
    source_uv_env
    if command_exists uv; then
        uv self uninstall --yes 2>/dev/null || true
        rm -rf "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx" "$HOME/.local/share/uv"
        success "uv 已卸载"
    else
        info "uv 未安装，跳过"
    fi
}

uninstall_volta() {
    header "卸载 Volta"
    if [[ -d "$HOME/.volta" ]]; then
        rm -rf "$HOME/.volta"
        success "Volta 已卸载"
    else
        info "Volta 未安装，跳过"
    fi
}

uninstall_p10k() {
    header "卸载 Powerlevel10k"
    if [[ -d "$HOME/powerlevel10k" ]] || [[ -f "$HOME/.p10k.zsh" ]]; then
        rm -rf "$HOME/powerlevel10k" "$HOME/.p10k.zsh"
        rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}"/p10k-instant-prompt-*.zsh
        success "Powerlevel10k 已卸载"
    else
        info "Powerlevel10k 未安装，跳过"
    fi
}

uninstall_pure() {
    header "卸载 Pure 主题"
    if [[ -d "$HOME/.zsh/pure" ]]; then
        rm -rf "$HOME/.zsh/pure"
        success "Pure 主题已卸载"
    else
        info "Pure 主题未安装，跳过"
    fi
}

uninstall_theme() {
    uninstall_p10k
    uninstall_pure
}

uninstall_zsh_autosuggestions() {
    header "卸载 zsh-autosuggestions"
    local target_dir="${ZSH_CUSTOM_DIR}/plugins/zsh-autosuggestions"
    if [[ -d "$target_dir" ]]; then
        rm -rf "$target_dir"
        success "zsh-autosuggestions 已卸载"
    else
        info "zsh-autosuggestions 未安装，跳过"
    fi
}

uninstall_zsh_syntax_highlighting() {
    header "卸载 zsh-syntax-highlighting"
    local target_dir="${ZSH_CUSTOM_DIR}/plugins/zsh-syntax-highlighting"
    if [[ -d "$target_dir" ]]; then
        rm -rf "$target_dir"
        success "zsh-syntax-highlighting 已卸载"
    else
        info "zsh-syntax-highlighting 未安装，跳过"
    fi
}

uninstall_yazi() {
    header "卸载 yazi"
    source_cargo_env
    if command_exists yazi; then
        cargo uninstall yazi-fm yazi-cli yazi-build 2>/dev/null || true
        success "yazi 已卸载"
    else
        info "yazi 未安装，跳过"
    fi
}

uninstall_eza() {
    header "卸载 eza"
    source_cargo_env
    if command_exists eza; then
        cargo uninstall eza 2>/dev/null || true
        success "eza 已卸载"
    else
        info "eza 未安装，跳过"
    fi
}

uninstall_rustup() {
    header "卸载 Rust (rustup)"
    source_cargo_env
    if command_exists rustup; then
        rustup self uninstall -y
        success "Rust 已卸载"
    else
        info "Rust 未安装，跳过"
    fi
}

uninstall_ohmyzsh() {
    header "卸载 Oh My Zsh"
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        rm -rf "$HOME/.oh-my-zsh"
        success "Oh My Zsh 已卸载"
    else
        info "Oh My Zsh 未安装，跳过"
    fi
}

uninstall_zsh() {
    header "卸载 Zsh"
    if command_exists zsh; then
        # 先切回 bash
        if [[ "$SHELL" == *"zsh"* ]]; then
            chsh -s "$(which bash)" 2>/dev/null || true
        fi
        sudo apt-get remove -y zsh 2>/dev/null || true
        success "Zsh 已卸载"
    else
        info "Zsh 未安装，跳过"
    fi
}

uninstall_apt_deps() {
    header "卸载基础依赖包"
    info "跳过基础依赖卸载（避免影响系统其他程序）"
}

remove_zshrc_config() {
    header "清理 .zshrc 配置"
    local zshrc="$HOME/.zshrc"
    local MARKER_START="# >>> one-click-dev-env >>>"
    local MARKER_END="# <<< one-click-dev-env <<<"
    if [[ -f "$zshrc" ]]; then
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip
        ' "$zshrc" > "${zshrc}.tmp" && mv "${zshrc}.tmp" "$zshrc"
        # 清理 eza zstyle 和 pure 相关行
        sed -i "/^zstyle ':omz:plugins:eza'/d" "$zshrc"
        sed -i "/^# ── eza 插件配置/d" "$zshrc"
        success ".zshrc 中的 one-click-dev-env 配置已移除"
    fi
}

# ─── 耗时估算 ─────────────────────────────────────────────────────────────────

estimate_time() {
    echo -e "${BOLD}预估安装时间：${NC}"
    echo "  • 基础依赖 + zsh + oh-my-zsh:  ~2 分钟"
    echo "  • Rust + eza + yazi (cargo 编译): ~10-20 分钟"
    echo "  • Volta + Node/npm/pnpm:  ~2 分钟"
    echo "  • uv + Python:  ~2 分钟"
    echo "  • 其他:  ~1 分钟"
    echo -e "  ${BOLD}总计约 20-30 分钟${NC}（取决于网络和机器性能）"
    echo ""
}

# ─── 一键安装 ─────────────────────────────────────────────────────────────────

select_theme() {
    echo ""
    echo -e "${BOLD}${CYAN}请选择终端主题：${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}) ${BOLD}Powerlevel10k${NC}$( [[ "$SELECTED_THEME" == "p10k" ]] && echo -e " ${YELLOW}★当前默认${NC}" )"
    echo -e "     ${GREEN}优势：${NC}高度可定制、丰富图标、Git 状态即时显示、Instant Prompt 极速启动"
    echo -e "     ${YELLOW}注意：${NC}需要在宿主机安装 Nerd Font 字体"
    echo ""
    echo -e "  ${CYAN}2${NC}) ${BOLD}Pure${NC}$( [[ "$SELECTED_THEME" == "pure" ]] && echo -e " ${YELLOW}★当前默认${NC}" )"
    echo -e "     ${GREEN}优势：${NC}极简美观、零配置、不依赖特殊字体、异步 Git 检测不阻塞输入"
    echo -e "     ${YELLOW}注意：${NC}宿主机${BOLD}无需${NC}${YELLOW}安装任何特殊字体${NC}"
    echo ""
    
    local default_choice="1"
    [[ "$SELECTED_THEME" == "pure" ]] && default_choice="2"
    
    read -rp "请选择 (1/2) [默认保持: ${SELECTED_THEME}]: " theme_choice
    case "${theme_choice:-$default_choice}" in
        2) SELECTED_THEME="pure" ;;
        1) SELECTED_THEME="p10k" ;;
        *) SELECTED_THEME="$SELECTED_THEME" ;;
    esac
    success "已选择主题: $SELECTED_THEME"
}

run_install_all() {
    header "🚀 开始一键安装所有开发环境组件"

    check_os
    check_network
    ensure_sudoers

    # 如果未通过 --theme 指定主题，则交互选择
    if [[ "$SELECTED_THEME" == "p10k" ]] && [[ "${THEME_SET_BY_FLAG:-}" != "1" ]]; then
        select_theme
    fi

    estimate_time

    local start_time
    start_time=$(date +%s)

    # 自动处理依赖关系：如果选择了 eza 或 yazi，则必须安装 rustup
    if [[ -n "$SELECTED_COMPONENTS" ]]; then
        local comps=",${SELECTED_COMPONENTS},"
        if [[ "$comps" == *",eza,"* || "$comps" == *",yazi,"* ]]; then
            if [[ "$comps" != *",rustup,"* ]]; then
                SELECTED_COMPONENTS="${SELECTED_COMPONENTS},rustup"
                info "因选择了 eza 或 yazi，自动添加 rustup 依赖"
            fi
        fi
    fi

    local comps=",${SELECTED_COMPONENTS},"
    should_install() {
        [[ -z "$SELECTED_COMPONENTS" ]] && return 0
        [[ "$comps" == *",$1,"* ]] && return 0
        return 1
    }

    # 基础环境始终安装
    install_apt_deps
    install_zsh
    install_ohmyzsh
    install_theme

    # 可选组件
    should_install "rustup" && install_rustup
    should_install "eza" && install_eza
    should_install "yazi" && install_yazi
    should_install "zsh-autosuggestions" && install_zsh_autosuggestions
    should_install "zsh-syntax-highlighting" && install_zsh_syntax_highlighting
    should_install "volta" && install_volta
    should_install "uv" && install_uv
    should_install "proto" && install_proto
    
    # 配置
    configure_zshrc

    local end_time elapsed_min
    end_time=$(date +%s)
    elapsed_min=$(( (end_time - start_time) / 60 ))

    echo ""
    header "✅ 安装流程完成！(耗时 ${elapsed_min} 分钟)"
    echo -e "${BOLD}基础组件：${NC}"
    echo "  • Zsh + Oh My Zsh"
    if [[ "$SELECTED_THEME" == "pure" ]]; then
        echo "  • Pure 主题"
    else
        echo "  • Powerlevel10k 主题"
    fi

    echo -e "\n${BOLD}可选组件配置结果：${NC}"
    should_install "zsh-autosuggestions" && echo "  • zsh-autosuggestions"
    should_install "zsh-syntax-highlighting" && echo "  • zsh-syntax-highlighting"
    should_install "rustup" && echo "  • Rust (rustup + cargo)"
    should_install "eza" && echo "  • eza"
    should_install "yazi" && echo "  • yazi"
    should_install "volta" && echo "  • Volta (Node.js + npm + pnpm)"
    should_install "uv" && echo "  • uv (Python)"
    should_install "proto" && echo "  • proto"

    print_summary

    echo ""
    if [[ "$SELECTED_THEME" == "pure" ]]; then
        info "Pure 主题已配置，无需额外步骤"
    else
        warn "请手动运行 ${BOLD}p10k configure${NC}${YELLOW} 配置 Powerlevel10k 主题偏好${NC}"
    fi

    echo ""
    info "如果终端中的 ${BOLD}图标显示为乱码或问号${NC}，说明缺少 Nerd Font 字体。"
    echo -e "  请在日常使用的终端软件（如 Windows Terminal, iTerm2, Alacritty 等）中配置字体为 ${BOLD}MesloLGS NF${NC}。"
    echo -e "  ${YELLOW}字体安装命令提示：${NC}"
    echo -e "    • ${BOLD}Windows (WSL)${NC}: 在宿主机 PowerShell 中运行 ${CYAN}iex (iwr -useb https://raw.githubusercontent.com/romkatv/powerlevel10k-media/master/fonts.ps1)${NC}"
    echo -e "    • ${BOLD}macOS${NC}: ${CYAN}brew tap homebrew/cask-fonts && brew install --cask font-meslo-lg-nerd-font${NC}"
    echo -e "    • ${BOLD}Linux${NC}: 下载并移动字体文件至 ${CYAN}~/.local/share/fonts${NC}，然后运行 ${CYAN}fc-cache -f -v${NC}"
    echo ""

    info "运行 ${BOLD}exec zsh${NC} 或重新登录以启用新配置"

    # 如果配置了自动清理，则移除自身脚本
    if [[ "$AUTO_CLEANUP" == "1" ]]; then
        local script_path
        script_path=$(readlink -f "$0")
        if [[ -f "$script_path" ]]; then
            info "清理安装脚本: $script_path"
            rm -f "$script_path"
        fi
    fi
}

# ─── 一键卸载 ─────────────────────────────────────────────────────────────────

run_uninstall_all() {
    header "🗑️  开始一键卸载所有开发环境组件"

    warn "即将卸载所有开发环境组件，此操作不可逆！"
    echo ""

    remove_zshrc_config
    uninstall_proto
    uninstall_uv
    uninstall_volta
    uninstall_yazi
    uninstall_eza
    uninstall_zsh_syntax_highlighting
    uninstall_zsh_autosuggestions
    uninstall_theme
    uninstall_rustup
    uninstall_ohmyzsh
    uninstall_zsh
    uninstall_apt_deps

    header "✅ 卸载完成"
}

# ─── 交互模式 ─────────────────────────────────────────────────────────────────

show_status_indicator() {
    local comp_id="$1"
    case "$comp_id" in
        apt-deps)     dpkg -s curl &>/dev/null && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        zsh)          command_exists zsh && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        ohmyzsh)      [[ -d "$HOME/.oh-my-zsh" ]] && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        rustup)       command_exists rustc && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        eza)          command_exists eza && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        yazi)         command_exists yazi && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        theme)
            if [[ -d "$HOME/powerlevel10k" ]]; then
                echo -e "${GREEN}● p10k${NC}"
            elif [[ -d "$HOME/.zsh/pure" ]]; then
                echo -e "${GREEN}● pure${NC}"
            else
                echo -e "${RED}○${NC}"
            fi
            ;;
        zsh-autosuggestions)     [[ -d "${ZSH_CUSTOM_DIR}/plugins/zsh-autosuggestions" ]] && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        zsh-syntax-highlighting) [[ -d "${ZSH_CUSTOM_DIR}/plugins/zsh-syntax-highlighting" ]] && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        volta)        command_exists volta && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        uv)           command_exists uv && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        proto)        command_exists proto && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        *)            echo -e "${RED}○${NC}" ;;
    esac
}

interactive_menu() {
    local action="$1"  # install 或 uninstall
    local action_label
    if [[ "$action" == "install" ]]; then
        action_label="安装"
    else
        action_label="卸载"
    fi

    echo -e "\n${BOLD}请选择要${action_label}的组件（输入编号，逗号分隔，或 ${CYAN}all${NC}${BOLD} 全选）：${NC}"
    echo -e "  ${GREEN}●${NC} = 已安装    ${RED}○${NC} = 未安装\n"

    for i in "${!COMPONENTS[@]}"; do
        local comp="${COMPONENTS[$i]}"
        local name="${comp%%:*}"
        local desc="${comp##*:}"
        local status
        status=$(show_status_indicator "$name")
        printf "  %b ${CYAN}%2d${NC}) %-40s ${BOLD}[%s]${NC}\n" "$status" "$((i+1))" "$desc" "$name"
    done

    echo ""
    read -rp "请输入选择 (例: 1,3,5 或 all): " choices

    if [[ -z "$choices" ]]; then
        warn "未输入任何选择"
        return
    fi

    local selected=()
    if [[ "$choices" == "all" ]]; then
        for comp in "${COMPONENTS[@]}"; do
            selected+=("${comp%%:*}")
        done
    else
        IFS=',' read -ra nums <<< "$choices"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | tr -d '[:space:]')
            if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#COMPONENTS[@]} )); then
                local comp="${COMPONENTS[$((num-1))]}"
                selected+=("${comp%%:*}")
            else
                warn "无效选择: $num，已跳过"
            fi
        done
    fi

    if [[ ${#selected[@]} -eq 0 ]]; then
        warn "未选择任何组件"
        return
    fi

    echo -e "\n${BOLD}将${action_label}以下组件：${NC}"
    for s in "${selected[@]}"; do
        echo -e "  • $s"
    done
    echo ""
    read -rp "确认？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        info "已取消"
        return
    fi

    if [[ "$action" == "install" ]]; then
        ensure_sudoers
        # 如果选择了主题组件，先询问主题类型
        for s in "${selected[@]}"; do
            if [[ "$s" == "theme" ]]; then
                select_theme
                break
            fi
        done
        for s in "${selected[@]}"; do
            local func_name="install_${s//-/_}"
            if declare -F "$func_name" > /dev/null; then
                "$func_name" || warn "安装 $s 时出现问题"
            else
                warn "未知组件: $s"
            fi
        done
        # 如果安装了 zsh 相关组件，重新配置 .zshrc
        configure_zshrc
    else
        for s in "${selected[@]}"; do
            local func_name="uninstall_${s//-/_}"
            if declare -F "$func_name" > /dev/null; then
                "$func_name" || warn "卸载 $s 时出现问题"
            else
                warn "未知组件: $s"
            fi
        done
        remove_zshrc_config
    fi

    header "✅ ${action_label}操作完成"
    print_summary
}

run_interactive() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  Linux 开发环境管理工具${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════${NC}\n"
    echo -e "  ${CYAN}1${NC}) 选择安装组件"
    echo -e "  ${CYAN}2${NC}) 选择卸载组件"
    echo -e "  ${CYAN}3${NC}) 查看所有组件状态"
    echo -e "  ${CYAN}0${NC}) 退出"
    echo ""
    read -rp "请选择操作: " op

    case "$op" in
        1) interactive_menu "install" ;;
        2) interactive_menu "uninstall" ;;
        3)
            echo -e "\n${BOLD}组件状态：${NC}\n"
            for comp in "${COMPONENTS[@]}"; do
                local name="${comp%%:*}"
                local desc="${comp##*:}"
                local status
                status=$(show_status_indicator "$name")
                printf "  %b %s\n" "$status" "$desc"
            done
            echo ""
            ;;
        0) info "已退出"; exit 0 ;;
        *) error "无效选择"; exit 1 ;;
    esac
}

# ─── 主入口 ───────────────────────────────────────────────────────────────────

main() {
    # 解析参数
    local action=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install)   action="install"; shift ;;
            --uninstall) action="uninstall"; shift ;;
            --theme)
                shift
                case "${1:-}" in
                    pure)  SELECTED_THEME="pure"; THEME_SET_BY_FLAG=1 ;;
                    p10k)  SELECTED_THEME="p10k"; THEME_SET_BY_FLAG=1 ;;
                    *)     error "无效主题: ${1:-}（可选: p10k, pure）"; exit 1 ;;
                esac
                shift
                ;;
            --components)
                shift
                SELECTED_COMPONENTS="${1:-}"
                shift
                ;;
            --auto-cleanup)
                AUTO_CLEANUP=1
                shift
                ;;
            --help|-h)
                echo "Linux 开发环境管理工具"
                echo ""
                echo "用法: $0 [--install | --uninstall] [--theme p10k|pure] [--components \"comp1,comp2\"] [--help]"
                echo ""
                echo "选项:"
                echo "  --install              一键安装所有组件"
                echo "  --uninstall            一键卸载所有组件"
                echo "  --theme p10k|pure      指定终端主题（默认: p10k）"
                echo "    p10k   Powerlevel10k  高度可定制、丰富图标（需 Nerd Font）"
                echo "    pure   Pure           极简美观、无需特殊字体"
                echo "  --components \"...\"   指定要安装的可选组件标识符，逗号分隔 (例: rustup,eza,volta)，留空或不传则安装全部"
                echo "  --help, -h             显示帮助信息"
                echo "  （无参数）              进入交互界面"
                echo ""
                echo "日志文件: $LOG_FILE"
                exit 0
                ;;
            *)
                error "未知选项: $1"
                echo "用法: $0 [--install | --uninstall] [--theme p10k|pure] [--help]"
                exit 1
                ;;
        esac
    done

    case "$action" in
        install)   run_install_all ;;
        uninstall) run_uninstall_all ;;
        "")        run_interactive ;;
    esac
}

main "$@"
