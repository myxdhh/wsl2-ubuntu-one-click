#!/usr/bin/env bash
# =============================================================================
# setup-dev-env.sh — Linux 开发环境一键安装/卸载脚本
# 适用于 Ubuntu / Debian 系统（含 WSL2）
#
# 用法:
#   bash setup-dev-env.sh --install                一键安装所有组件（无交互，默认 starship 主题）
#   bash setup-dev-env.sh --install --theme p10k    一键安装（使用 p10k 主题）
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

# ─── 主题与插件管理器选择 ──────────────────────────────────────────────────────
# 可选值: starship, p10k, pure
if command -v starship &>/dev/null || [[ -f "$HOME/.config/starship.toml" ]]; then
    SELECTED_THEME="starship"
elif [[ -f "$HOME/.zshrc" ]] && grep -q "prompt pure" "$HOME/.zshrc" 2>/dev/null; then
    SELECTED_THEME="pure"
elif [[ -d "$HOME/.zsh/pure" ]] && { [[ ! -d "$HOME/powerlevel10k" ]] && ! grep -q "powerlevel10k.zsh-theme" "$HOME/.zshrc" 2>/dev/null; }; then
    SELECTED_THEME="pure"
elif [[ -d "$HOME/powerlevel10k" ]] || { [[ -f "$HOME/.zshrc" ]] && grep -q "powerlevel10k" "$HOME/.zshrc" 2>/dev/null; }; then
    SELECTED_THEME="p10k"
else
    SELECTED_THEME="starship"
fi
# 插件管理器: sheldon (默认), ohmyzsh
if [[ -d "$HOME/.oh-my-zsh" ]] && ! command -v sheldon &>/dev/null; then
    SELECTED_PLUGIN_MGR="ohmyzsh"
else
    SELECTED_PLUGIN_MGR="sheldon"
fi
# Catppuccin 风味: mocha (默认), macchiato, frappe, latte
# 自动检测：如已有 starship.toml，读取当前 palette
if [[ -f "$HOME/.config/starship.toml" ]] && grep -q 'palette.*catppuccin_' "$HOME/.config/starship.toml" 2>/dev/null; then
    SELECTED_CATPPUCCIN_FLAVOR="$(grep 'palette' "$HOME/.config/starship.toml" | sed 's/.*catppuccin_//' | sed 's/".*//' | head -1)"
else
    SELECTED_CATPPUCCIN_FLAVOR="mocha"
fi
# 可选为空（全选），或逗号分隔的组件标识符 (如 "rustup,volta,uv")
SELECTED_COMPONENTS=""
# 是否自动清理原脚本文件
AUTO_CLEANUP=0

# ─── 组件列表 ─────────────────────────────────────────────────────────────────
COMPONENTS=(
    "apt-deps:基础依赖包"
    "zsh:Zsh Shell"
    "plugin-mgr:插件管理器 (Sheldon/Oh My Zsh)"
    "theme:终端主题 (starship/p10k/pure)"
    "zsh-autosuggestions:zsh-autosuggestions 插件"
    "fast-syntax-highlighting:fast-syntax-highlighting 插件"
    "fzf-tab:fzf-tab (模糊补全)"
    "zsh-completions:zsh-completions (补全定义)"
    "fzf:fzf (模糊搜索)"
    "zoxide:zoxide (智能 cd)"
    "rustup:Rust 工具链 (rustup)"
    "eza:eza (现代 ls 替代)"
    "yazi:yazi (终端文件管理器)"
    "volta:Volta (Node/npm/pnpm 版本管理)"
    "uv:uv (Python 版本管理)"
    "proto:proto (多语言版本管理)"
)

# ─── 工具函数 ─────────────────────────────────────────────────────────────────
# ZSH_CUSTOM_DIR 仅在 Oh My Zsh 模式下使用
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

command_exists() { command -v "$1" &>/dev/null; }

# 生成 CLI 工具的 Zsh 补全文件
generate_completions() {
    local comp_dir
    if [[ "$SELECTED_PLUGIN_MGR" == "ohmyzsh" ]] && [[ -d "$HOME/.oh-my-zsh" ]]; then
        comp_dir="$HOME/.oh-my-zsh/completions"
    else
        comp_dir="$HOME/.zsh/completions"
    fi
    mkdir -p "$comp_dir"

    local generated=()

    # rustup + cargo
    if command_exists rustup; then
        rustup completions zsh > "$comp_dir/_rustup" 2>>"$LOG_FILE" && generated+=(rustup)
        rustup completions zsh cargo > "$comp_dir/_cargo" 2>>"$LOG_FILE" && generated+=(cargo)
    fi
    # volta（使用 -o 参数直接写入文件，比 stdout 重定向更可靠）
    if command_exists volta; then
        volta completions zsh -o "$comp_dir/_volta" 2>>"$LOG_FILE" && generated+=(volta)
    fi
    # uv
    if command_exists uv; then
        uv generate-shell-completion zsh > "$comp_dir/_uv" 2>>"$LOG_FILE" && generated+=(uv)
    fi
    # proto
    if command_exists proto; then
        proto completions --shell zsh > "$comp_dir/_proto" 2>>"$LOG_FILE" && generated+=(proto)
    fi
    # starship
    if command_exists starship; then
        starship completions zsh > "$comp_dir/_starship" 2>>"$LOG_FILE" && generated+=(starship)
    fi
    # eza（cargo install 不含补全文件，从 GitHub 下载与当前版本匹配的补全定义）
    # 注意：必须从对应版本 tag 下载，main 分支可能含未发布的 flag 变更（如 --hyperlink 从布尔变为可传值），
    # 导致 _arguments 解析别名展开后的参数时错位，补全失败。
    # 每次安装时重新下载，避免 eza 升级后旧补全文件与新版本不兼容。
    if command_exists eza; then
        local eza_ver
        eza_ver="$(eza --version | grep -oP 'v[\d.]+')"
        if [[ -n "$eza_ver" ]]; then
            curl -fsSL "https://raw.githubusercontent.com/eza-community/eza/${eza_ver}/completions/zsh/_eza" \
                > "$comp_dir/_eza" 2>>"$LOG_FILE" && generated+=(eza)
            # 若该 tag 不存在则回退到 main
            if [[ ! -s "$comp_dir/_eza" ]]; then
                warn "eza ${eza_ver} 的补全文件不存在，回退到 main 分支"
                curl -fsSL "https://raw.githubusercontent.com/eza-community/eza/main/completions/zsh/_eza" \
                    > "$comp_dir/_eza" 2>>"$LOG_FILE"
            fi
        fi
    fi

    # 验证：删除空文件（可能是命令静默失败）
    local f basename
    for f in "$comp_dir"/_*; do
        [[ -f "$f" ]] || continue
        if [[ ! -s "$f" ]]; then
            basename="$(basename "$f")"
            warn "补全文件为空，已删除: $basename（请检查日志 $LOG_FILE）"
            rm -f "$f"
        fi
    done

    if [[ ${#generated[@]} -gt 0 ]]; then
        info "补全文件已生成到: $comp_dir (${generated[*]})"
    else
        info "未检测到可生成补全的工具"
    fi
}

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

# ─── Catppuccin 风味辅助函数 ─────────────────────────────────────────────────

# 返回指定 Catppuccin 风味的 fzf --color 参数
get_fzf_catppuccin_colors() {
    case "${1:-mocha}" in
        mocha)
            echo "bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc,marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
            ;;
        macchiato)
            echo "bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796,fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6,marker:#b7bdf8,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796"
            ;;
        frappe)
            echo "bg+:#414559,bg:#303446,spinner:#f2d5cf,hl:#e78284,fg:#c6d0f5,header:#e78284,info:#ca9ee6,pointer:#f2d5cf,marker:#babbf1,fg+:#c6d0f5,prompt:#ca9ee6,hl+:#e78284"
            ;;
        latte)
            echo "bg+:#ccd0da,bg:#eff1f5,spinner:#dc8a78,hl:#d20f39,fg:#4c4f69,header:#d20f39,info:#8839ef,pointer:#dc8a78,marker:#7287fd,fg+:#4c4f69,prompt:#8839ef,hl+:#d20f39"
            ;;
    esac
}

# 交互式 Catppuccin 风味选择（fzf 驱动，带 git diff 风格预览）
select_catppuccin_flavor() {
    info "选择 Catppuccin 风味（同时影响 Starship 和 fzf 配色）"
    echo ""

    if ! command_exists fzf; then
        # fzf 不可用时回退到普通菜单
        echo -e "  ${CYAN}1${NC}) Mocha (深色) ★默认"
        echo -e "  ${CYAN}2${NC}) Macchiato (深色偏暖)"
        echo -e "  ${CYAN}3${NC}) Frapp\u00e9 (中间色调)"
        echo -e "  ${CYAN}4${NC}) Latte (浅色)"
        echo ""
        local default_choice="1"
        [[ "$SELECTED_CATPPUCCIN_FLAVOR" == "macchiato" ]] && default_choice="2"
        [[ "$SELECTED_CATPPUCCIN_FLAVOR" == "frappe" ]] && default_choice="3"
        [[ "$SELECTED_CATPPUCCIN_FLAVOR" == "latte" ]] && default_choice="4"
        read -rp "请选择风味 (1-4) [默认: ${SELECTED_CATPPUCCIN_FLAVOR}]: " flavor_choice
        case "$flavor_choice" in
            2) SELECTED_CATPPUCCIN_FLAVOR="macchiato" ;;
            3) SELECTED_CATPPUCCIN_FLAVOR="frappe" ;;
            4) SELECTED_CATPPUCCIN_FLAVOR="latte" ;;
            1) SELECTED_CATPPUCCIN_FLAVOR="mocha" ;;
            *) ;; # 保持当前值
        esac
    else
        # 用 fzf + --preview 实现 git diff 风格的配色预览
        local selected
        selected=$(printf '%s\n' "mocha" "macchiato" "frappe" "latte" | \
            fzf --height=20 --layout=reverse --border=rounded \
                --header="选择 Catppuccin 风味（↑↓ 移动，Enter 确认）" \
                --preview='
                    case {} in
                        mocha)
                            BG="30;30;46" FG="205;214;244" RED="243;139;168"
                            GREEN="166;227;161" BLUE="137;180;250" SUB="166;173;200"
                            ;;
                        macchiato)
                            BG="36;39;58" FG="202;211;245" RED="237;135;150"
                            GREEN="166;218;149" BLUE="138;173;244" SUB="165;173;203"
                            ;;
                        frappe)
                            BG="48;52;70" FG="198;208;245" RED="231;130;132"
                            GREEN="166;209;137" BLUE="140;170;238" SUB="165;173;206"
                            ;;
                        latte)
                            BG="239;241;245" FG="76;79;105" RED="210;15;57"
                            GREEN="64;160;43" BLUE="30;102;245" SUB="108;111;133"
                            ;;
                    esac
                    R="\033[0m"
                    bg="\033[48;2;${BG}m"
                    fg="\033[38;2;${FG}m"
                    red="\033[38;2;${RED}m"
                    green="\033[38;2;${GREEN}m"
                    blue="\033[38;2;${BLUE}m"
                    sub="\033[38;2;${SUB}m"

                    printf "${bg}${blue} diff --git a/starship.toml b/starship.toml${R}\n"
                    printf "${bg}${blue} --- a/starship.toml${R}\n"
                    printf "${bg}${blue} +++ b/starship.toml${R}\n"
                    printf "${bg}${sub} @@ -1,2 +1,2 @@${R}\n"
                    printf "${bg}${red} -palette = \"catppuccin_mocha\"${R}\n"
                    printf "${bg}${green} +palette = \"catppuccin_{}\"${R}\n"
                    printf "${bg}${fg}  ${R}\n"
                    printf "${bg}${blue} diff --git a/.zshrc b/.zshrc${R}\n"
                    printf "${bg}${blue} --- a/.zshrc${R}\n"
                    printf "${bg}${blue} +++ b/.zshrc${R}\n"
                    printf "${bg}${sub} @@ -5,4 +5,4 @@${R}\n"
                    printf "${bg}${fg}  export FZF_DEFAULT_OPTS=\"${R}\n"
                    printf "${bg}${fg}    --height=60%% --layout=reverse${R}\n"
                    printf "${bg}${red} -  --color=bg:#1e1e2e,fg:#cdd6f4,hl:#f38ba8${R}\n"
                    printf "${bg}${green} +  --color=bg:#...,fg:#...,hl:#...  ({})${R}\n"
                    printf "${bg}${fg}    --prompt='\''\u276f '\''${R}\n"
                    printf "${bg}${fg}  \"${R}\n"
                ' \
                --preview-window=right:55%:wrap)

        SELECTED_CATPPUCCIN_FLAVOR="${selected:-$SELECTED_CATPPUCCIN_FLAVOR}"
    fi

    success "已选择 Catppuccin 风味: $SELECTED_CATPPUCCIN_FLAVOR"
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
        ffmpeg p7zip-full jq poppler-utils fd-find ripgrep fzf zoxide imagemagick bat
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

install_sheldon() {
    header "安装 Sheldon 插件管理器"
    log_start "sheldon"

    if command_exists sheldon; then
        success "Sheldon 已安装: $(sheldon --version)"
    else
        # 确保 ~/.local/bin 在 PATH 中
        mkdir -p "$HOME/.local/bin"
        export PATH="$HOME/.local/bin:$PATH"

        info "正在下载 Sheldon 预编译二进制..."
        if ! curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
            | bash -s -- --repo rossmacarthur/sheldon --to "$HOME/.local/bin" 2>&1 \
            | tee -a "$LOG_FILE"; then
            record_failure "sheldon"
            return 1
        fi
        success "Sheldon 安装完成: $(sheldon --version)"
    fi

    # 初始化配置目录
    mkdir -p "$HOME/.config/sheldon"

    log_end "sheldon" $?
}

# 根据 SELECTED_PLUGIN_MGR 安装对应的插件管理器
install_plugin_mgr() {
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        install_sheldon
    else
        install_ohmyzsh
    fi
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

    # Sheldon 模式: 主题由 plugins.toml 管理
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        info "Sheldon 模式: Powerlevel10k 将由 plugins.toml 统一管理"
        log_end "p10k" 0
        return 0
    fi

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

    # Sheldon 模式: 主题由 plugins.toml 管理
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        info "Sheldon 模式: Pure 将由 plugins.toml 统一管理"
        log_end "pure" 0
        return 0
    fi

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

install_starship_theme() {
    header "安装 Starship 主题"
    log_start "starship-theme"

    # 安装 Starship 二进制
    if command_exists starship; then
        success "Starship 已安装: $(starship --version 2>&1 | head -1)"
    else
        info "正在安装 Starship..."
        mkdir -p "$HOME/.local/bin"
        if ! curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "starship-theme"
            return 1
        fi
        export PATH="$HOME/.local/bin:$PATH"
        success "Starship 安装完成"
    fi

    # 配置 catppuccin-powerline 预设
    local starship_config="$HOME/.config/starship.toml"
    if [[ -f "$starship_config" ]]; then
        # 配置已存在，更新 Catppuccin 风味
        if grep -q '^palette' "$starship_config"; then
            sed -i "s/^palette.*/palette = \"catppuccin_${SELECTED_CATPPUCCIN_FLAVOR}\"/" "$starship_config"
            success "Catppuccin 风味已更新为: $SELECTED_CATPPUCCIN_FLAVOR"
        else
            info "Starship 配置已存在但非 Catppuccin 预设，保留现有配置"
        fi
    else
        info "正在生成 catppuccin-powerline 预设..."
        mkdir -p "$HOME/.config"
        if starship preset catppuccin-powerline -o "$starship_config" 2>&1 | tee -a "$LOG_FILE"; then
            # 设置选定的 Catppuccin 风味
            if grep -q '^palette' "$starship_config"; then
                sed -i "s/^palette.*/palette = \"catppuccin_${SELECTED_CATPPUCCIN_FLAVOR}\"/" "$starship_config"
            fi
            # 确保 line_break 不被禁用
            if grep -q '^\[line_break\]' "$starship_config"; then
                sed -i '/^\[line_break\]/,/^\[/{s/disabled = true/disabled = false/}' "$starship_config"
            else
                printf '\n[line_break]\ndisabled = false\n' >> "$starship_config"
            fi
            success "catppuccin-powerline 预设已配置 (风味: $SELECTED_CATPPUCCIN_FLAVOR)"
        else
            warn "预设生成失败，Starship 将使用默认配置"
        fi
    fi

    log_end "starship-theme" $?
}

# 根据 SELECTED_THEME 安装对应主题
install_theme() {
    case "$SELECTED_THEME" in
        starship) install_starship_theme ;;
        pure)     install_pure ;;
        *)        install_p10k ;;
    esac
}

install_zsh_autosuggestions() {
    header "安装 zsh-autosuggestions"
    log_start "zsh-autosuggestions"

    # Sheldon 模式: 插件由 plugins.toml 管理
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        info "Sheldon 模式: zsh-autosuggestions 将由 plugins.toml 统一管理"
        log_end "zsh-autosuggestions" 0
        return 0
    fi

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

install_fast_syntax_highlighting() {
    header "安装 fast-syntax-highlighting"
    log_start "fast-syntax-highlighting"

    # Sheldon 模式: 插件由 plugins.toml 管理
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        info "Sheldon 模式: fast-syntax-highlighting 将由 plugins.toml 统一管理"
        log_end "fast-syntax-highlighting" 0
        return 0
    fi

    local target_dir="${ZSH_CUSTOM_DIR}/plugins/fast-syntax-highlighting"
    if [[ -d "$target_dir" ]]; then
        success "fast-syntax-highlighting 已安装"
    else
        mkdir -p "${ZSH_CUSTOM_DIR}/plugins"
        if ! git clone https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "fast-syntax-highlighting"
            return 1
        fi
        success "fast-syntax-highlighting 安装完成"
    fi

    log_end "fast-syntax-highlighting" $?
}

install_fzf_tab() {
    header "安装 fzf-tab"
    log_start "fzf-tab"

    # Sheldon 模式: 插件由 plugins.toml 管理
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        info "Sheldon 模式: fzf-tab 将由 plugins.toml 统一管理"
        log_end "fzf-tab" 0
        return 0
    fi

    local target_dir="${ZSH_CUSTOM_DIR}/plugins/fzf-tab"
    if [[ -d "$target_dir" ]]; then
        success "fzf-tab 已安装"
    else
        mkdir -p "${ZSH_CUSTOM_DIR}/plugins"
        if ! git clone https://github.com/Aloxaf/fzf-tab "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "fzf-tab"
            return 1
        fi
        success "fzf-tab 安装完成"
    fi

    log_end "fzf-tab" $?
}

install_zsh_completions() {
    header "安装 zsh-completions"
    log_start "zsh-completions"

    # Sheldon 模式: 插件由 plugins.toml 管理
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        info "Sheldon 模式: zsh-completions 将由 plugins.toml 统一管理"
        log_end "zsh-completions" 0
        return 0
    fi

    local target_dir="${ZSH_CUSTOM_DIR}/plugins/zsh-completions"
    if [[ -d "$target_dir" ]]; then
        success "zsh-completions 已安装"
    else
        mkdir -p "${ZSH_CUSTOM_DIR}/plugins"
        if ! git clone https://github.com/zsh-users/zsh-completions "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "zsh-completions"
            return 1
        fi
        success "zsh-completions 安装完成"
    fi

    log_end "zsh-completions" $?
}

install_fzf() {
    header "安装 fzf (模糊搜索)"
    log_start "fzf"

    if command_exists fzf; then
        success "fzf 已安装: $(fzf --version 2>&1 | head -1)"
    else
        if [[ -d "$HOME/.fzf" ]]; then
            info "~/.fzf 目录已存在，尝试重新安装..."
            rm -rf "$HOME/.fzf"
        fi
        if ! git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf" 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "fzf"
            return 1
        fi
        # --key-bindings --completion: 启用快捷键和补全  --no-update-rc: 我们自己管理 .zshrc
        if ! "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "fzf"
            return 1
        fi
        success "fzf 安装完成"
    fi

    log_end "fzf" $?
}

install_zoxide() {
    header "安装 zoxide (智能 cd)"
    log_start "zoxide"

    if command_exists zoxide; then
        success "zoxide 已安装: $(zoxide --version 2>&1)"
    else
        if ! curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "zoxide"
            return 1
        fi
        success "zoxide 安装完成"
    fi

    log_end "zoxide" $?
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

# ─── Sheldon plugins.toml 配置 ────────────────────────────────────────────────

configure_sheldon_plugins() {
    info "生成 Sheldon 插件配置..."
    local plugins_toml="$HOME/.config/sheldon/plugins.toml"
    mkdir -p "$(dirname "$plugins_toml")"

    # 生成 plugins.toml
    cat > "$plugins_toml" << 'TOML_HEADER'
# Sheldon plugin manager configuration
# Generated by setup-dev-env.sh
shell = "zsh"

[plugins.zsh-defer]
github = "romkatv/zsh-defer"

[templates]
defer = """{{ hooks?.pre | nl }}{% for file in files %}zsh-defer source "{{ file }}"\n{% endfor %}{{ hooks?.post | nl }}"""

TOML_HEADER

    # 主题（starship 不通过 sheldon 管理）
    case "$SELECTED_THEME" in
        pure)
            cat >> "$plugins_toml" << 'THEME_PURE'
[plugins.pure]
github = "sindresorhus/pure"
use = ["async.zsh", "pure.zsh"]

THEME_PURE
            ;;
        p10k)
            cat >> "$plugins_toml" << 'THEME_P10K'
[plugins.powerlevel10k]
github = "romkatv/powerlevel10k"

THEME_P10K
            ;;
        starship)
            # Starship 是独立二进制，不通过 Sheldon 管理
            ;;
    esac

    # 补全定义（必须在 compinit 之前）
    cat >> "$plugins_toml" << 'COMPLETIONS_BLOCK'
[plugins.custom-completions]
local = "~/.zsh/completions"
apply = ["fpath"]

[plugins.zsh-completions]
github = "zsh-users/zsh-completions"
dir = "src"
apply = ["fpath"]

COMPLETIONS_BLOCK

    # compinit（初始化补全系统，必须在 fzf-tab 之前）
    # 不使用 compinit -C（跳过扫描），因为 /etc/zsh/zshrc 等可能提前创建了
    # 不含自定义补全的 .zcompdump，导致 -C 永远使用残缺缓存
    cat >> "$plugins_toml" << 'COMPINIT_BLOCK'
[plugins.compinit]
inline = '''
autoload -Uz compinit && compinit
'''

COMPINIT_BLOCK

    # 插件（顺序：fzf-tab → completion-styles → ohmyzsh-git → autosuggestions → syntax-highlighting）
    cat >> "$plugins_toml" << 'PLUGINS_BLOCK'
[plugins.fzf-tab]
github = "Aloxaf/fzf-tab"

[plugins.completion-styles]
inline = '''
# 补全系统美化
zstyle ':completion:*' menu select
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# fzf-tab: 候选项少时保持足够的预览空间
zstyle ':fzf-tab:*' fzf-min-height 15
# Ctrl+/ 切换预览显示/隐藏
zstyle ':fzf-tab:*' fzf-bindings 'ctrl-/:toggle-preview'

# fzf-tab: 通用预览（所有命令生效，默认隐藏，按 Ctrl+/ 显示）
# 目录 → eza 树形，文件 → bat 语法高亮，其他（flags/子命令）→ 补全描述
zstyle ':fzf-tab:complete:*:*' fzf-preview 'if [[ -d $realpath ]]; then eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath; elif [[ -f $realpath ]]; then batcat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -100 $realpath; elif [[ -n $desc ]]; then echo -E $desc; fi'
zstyle ':fzf-tab:complete:*:*' fzf-flags --preview-window=hidden,wrap

# fzf-tab: 白名单命令覆盖（预览默认可见）
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi|ls|eza|exa|ll|la|tree|cat|less|more|head|tail|bat|batcat|vim|nvim|nano|code|view|cp|mv|rm|chmod|chown|source|\.|file|diff|stat):*' fzf-preview '[[ -d $realpath ]] && { eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath; } || { [[ -f $realpath ]] && { batcat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -100 $realpath; }; }'
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi|ls|eza|exa|ll|la|tree|cat|less|more|head|tail|bat|batcat|vim|nvim|nano|code|view|cp|mv|rm|chmod|chown|source|\.|file|diff|stat):*' fzf-flags --preview-window=wrap

# fzf-tab: 特定命令预览覆盖（预览默认可见）
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps -p $word -o pid,user,%cpu,%mem,start,command --no-headers 2>/dev/null'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-flags --preview-window=wrap
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word 2>/dev/null'
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-flags --preview-window=wrap
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-preview 'echo ${(P)word}'
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-flags --preview-window=wrap

# fzf-tab: 自定义命令预览示例（取消注释即可启用，预览默认可见）
# 对于支持 `cmd help subcommand` 的工具（如 rustup、cargo、docker），
# 可以覆盖通用规则，实现更丰富的子命令帮助预览
# zstyle ':fzf-tab:complete:rustup:*' fzf-preview 'if [[ -d $realpath ]]; then eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null; elif [[ -f $realpath ]]; then batcat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null; else rustup help $word 2>/dev/null; fi'
# zstyle ':fzf-tab:complete:rustup:*' fzf-flags --preview-window=wrap
'''

[plugins.ohmyzsh-git]
github = "ohmyzsh/ohmyzsh"
use = ["plugins/git/git.plugin.zsh"]
apply = ["defer"]

[plugins.zsh-autosuggestions]
github = "zsh-users/zsh-autosuggestions"
use = ["{{ name }}.zsh"]

[plugins.fast-syntax-highlighting]
github = "zdharma-continuum/fast-syntax-highlighting"

PLUGINS_BLOCK

    # eza inline aliases
    cat >> "$plugins_toml" << 'EZA_PLUGIN'
[plugins.eza-aliases]
inline = '''
if (( $+commands[eza] )); then
  alias ls='eza --icons --group-directories-first --git'
  alias ll='eza -la --icons --group-directories-first --git'
  alias la='eza -a --icons --group-directories-first'
  alias lt='eza --tree --icons --group-directories-first --level=2'
  alias l='eza -l --icons --group-directories-first --git'
fi
'''

EZA_PLUGIN

    # fzf integration
    cat >> "$plugins_toml" << 'FZF_PLUGIN'
[plugins.fzf]
inline = '''
if [[ -f "$HOME/.fzf.zsh" ]]; then
  source "$HOME/.fzf.zsh"
elif (( $+commands[fzf] )); then
  if [[ -n "$(fzf --zsh 2>/dev/null)" ]]; then
    source <(fzf --zsh)
  else
    # apt 安装的 fzf (< 0.48)，加载发行版提供的快捷键和补全
    [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
    [[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && source /usr/share/doc/fzf/examples/completion.zsh
  fi
fi
'''

FZF_PLUGIN

    # zoxide integration
    cat >> "$plugins_toml" << 'ZOXIDE_PLUGIN'
[plugins.zoxide]
inline = '(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd cd)"'
ZOXIDE_PLUGIN

    success "plugins.toml 已生成: $plugins_toml"

    # 确保 sheldon 可用后下载所有插件
    if command_exists sheldon; then
        info "正在下载 Sheldon 管理的插件（首次可能需要一点时间）..."
        if sheldon lock --update 2>&1 | tee -a "$LOG_FILE"; then
            success "Sheldon 插件下载完成"
        else
            warn "Sheldon 插件下载部分失败，可稍后运行 sheldon lock --update"
        fi
    else
        warn "sheldon 命令未找到，跳过插件下载。请先安装 Sheldon 后运行 sheldon lock"
    fi
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

    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        # ── Sheldon 模式 ──

        # 清理 oh-my-zsh 模板行（避免 ohmyzsh 与 sheldon 双重加载）
        if [[ -f "$zshrc" ]]; then
            sed -i '/^export ZSH=.*\.oh-my-zsh/d' "$zshrc"
            sed -i '/^ZSH_THEME=/d' "$zshrc"
            sed -i '/^plugins=(/d' "$zshrc"
            sed -i '/^source.*oh-my-zsh\.sh/d' "$zshrc"
            sed -i "/^zstyle ':omz:plugins:eza'/d" "$zshrc"
            sed -i '/^# ── eza 插件配置/d' "$zshrc"
        fi

        # 生成 plugins.toml 并下载插件
        configure_sheldon_plugins

        # 如果 .zshrc 不存在则创建空文件
        [[ -f "$zshrc" ]] || touch "$zshrc"

        # 追加配置块
        {
            echo ""
            echo "# >>> one-click-dev-env >>>"
            echo ""

            if [[ "$SELECTED_THEME" == "p10k" ]]; then
                cat << 'P10K_INSTANT'
# ── Powerlevel10k Instant Prompt ──
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

P10K_INSTANT
            fi

            cat << 'ENV_BLOCK'
# ── PATH ──
# zsh 登录 shell 不会 source ~/.profile，需要在此显式设置
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# ── Volta ──
export VOLTA_HOME="$HOME/.volta"
export VOLTA_FEATURE_PNPM=1
[[ -d "$VOLTA_HOME/bin" ]] && export PATH="$VOLTA_HOME/bin:$PATH"

# ── Cargo / Rust ──
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ── proto ──
export PROTO_HOME="$HOME/.proto"
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"

# ── Zsh History ──
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt APPEND_HISTORY
ENV_BLOCK

            # FZF_DEFAULT_OPTS 需要变量展开，不能放在单引号 heredoc 中
            local fzf_colors bat_theme
            fzf_colors="$(get_fzf_catppuccin_colors "$SELECTED_CATPPUCCIN_FLAVOR")"
            if [[ "$SELECTED_CATPPUCCIN_FLAVOR" == "latte" ]]; then
                bat_theme="GitHub"
            else
                bat_theme="Monokai Extended"
            fi
            cat << FZF_OPTS

# ── fzf 配色 (Catppuccin ${SELECTED_CATPPUCCIN_FLAVOR}) ──
export FZF_DEFAULT_OPTS="
  --height=60% --layout=reverse --border=rounded
  --color=${fzf_colors}
  --prompt='❯ ' --pointer='▸' --marker='✓'
"

# ── bat 主题 (Catppuccin ${SELECTED_CATPPUCCIN_FLAVOR}) ──
export BAT_THEME="${bat_theme}"
FZF_OPTS

            cat << 'SHELDON_BLOCK'

# ── Sheldon (Plugin Manager) ──
# 配置文件: ~/.config/sheldon/plugins.toml
eval "$(sheldon source)"
SHELDON_BLOCK

            if [[ "$SELECTED_THEME" == "p10k" ]]; then
                echo ""
                cat << 'P10K_CONFIG'
# ── Powerlevel10k config ──
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
P10K_CONFIG
            elif [[ "$SELECTED_THEME" == "starship" ]]; then
                echo ""
                cat << 'STARSHIP_INIT'
# ── Starship Prompt ──
# 配置文件: ~/.config/starship.toml
eval "$(starship init zsh)"
STARSHIP_INIT
            fi

            echo ""
            echo "# <<< one-click-dev-env <<<"
        } >> "$zshrc"

        success ".zshrc 配置完成 (插件管理器: Sheldon, 主题: $SELECTED_THEME)"
    else
        # ── Oh My Zsh 模式 ──

        # 确保 oh-my-zsh 基础模板存在（从 Sheldon 切换过来时可能缺失）
        if [[ -f "$zshrc" ]] && ! grep -q "^source.*oh-my-zsh\.sh" "$zshrc"; then
            info "检测到 .zshrc 缺少 oh-my-zsh 模板，正在补充..."
            # 在文件开头插入 oh-my-zsh 模板
            local omz_template
            omz_template=$(cat << 'OMZ_TPL'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git eza fzf-tab zsh-completions zsh-autosuggestions fast-syntax-highlighting)

# ── eza 插件配置（需在 source oh-my-zsh.sh 之前）──
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'icons' yes

source $ZSH/oh-my-zsh.sh
OMZ_TPL
)
            # 将模板插入到文件开头
            printf '%s\n\n' "$omz_template" | cat - "$zshrc" > "${zshrc}.tmp" && mv "${zshrc}.tmp" "$zshrc"
        fi
        if [[ -f "$zshrc" ]] && grep -q "^ZSH_THEME=" "$zshrc"; then
            # 替换主题为空（我们使用外部主题 p10k/pure）
            sed -i 's/^ZSH_THEME=.*/ZSH_THEME=""/' "$zshrc"
        fi

        # 更新 plugins 列表
        local plugins_line='plugins=(git eza fzf-tab zsh-completions zsh-autosuggestions fast-syntax-highlighting)'
        if [[ -f "$zshrc" ]] && grep -q "^plugins=" "$zshrc"; then
            sed -i "s/^plugins=.*/${plugins_line}/" "$zshrc"
        fi

        # eza zstyle 配置必须在 source $ZSH/oh-my-zsh.sh 之前才能生效
        # 先移除旧的 eza zstyle 行（如果有）
        if [[ -f "$zshrc" ]]; then
            sed -i "/^zstyle ':omz:plugins:eza'/d" "$zshrc"
        fi
        # 在 source $ZSH/oh-my-zsh.sh 之前插入 eza zstyle 配置
        local eza_config="# ── eza 插件配置（需在 source oh-my-zsh.sh 之前）──\nzstyle ':omz:plugins:eza' 'dirs-first' yes\nzstyle ':omz:plugins:eza' 'icons' yes"
        if [[ -f "$zshrc" ]] && grep -q "^source.*oh-my-zsh.sh" "$zshrc"; then
            sed -i "/^source.*oh-my-zsh.sh/i\\${eza_config}" "$zshrc"
        fi

        # 追加配置块（根据主题不同生成不同的配置）
        {
            echo ""
            echo "# >>> one-click-dev-env >>>"
            echo ""

            cat << 'ENV_BLOCK1'
# ── PATH ──
# zsh 登录 shell 不会 source ~/.profile，需要在此显式设置
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# ── Volta ──
export VOLTA_HOME="$HOME/.volta"
export VOLTA_FEATURE_PNPM=1
[[ -d "$VOLTA_HOME/bin" ]] && export PATH="$VOLTA_HOME/bin:$PATH"

# ── Cargo / Rust ──
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# ── proto ──
export PROTO_HOME="$HOME/.proto"
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"

# ── Zsh History ──
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt APPEND_HISTORY
ENV_BLOCK1

            # FZF_DEFAULT_OPTS 需要变量展开
            local fzf_colors bat_theme
            fzf_colors="$(get_fzf_catppuccin_colors "$SELECTED_CATPPUCCIN_FLAVOR")"
            if [[ "$SELECTED_CATPPUCCIN_FLAVOR" == "latte" ]]; then
                bat_theme="GitHub"
            else
                bat_theme="Monokai Extended"
            fi
            cat << FZF_OPTS

# ── fzf 配色 (Catppuccin ${SELECTED_CATPPUCCIN_FLAVOR}) ──
export FZF_DEFAULT_OPTS="
  --height=60% --layout=reverse --border=rounded
  --color=${fzf_colors}
  --prompt='❯ ' --pointer='▸' --marker='✓'
"

# ── bat 主题 (Catppuccin ${SELECTED_CATPPUCCIN_FLAVOR}) ──
export BAT_THEME="${bat_theme}"
FZF_OPTS

            cat << 'ENV_BLOCK2'

# ── fzf ──
if [[ -f "$HOME/.fzf.zsh" ]]; then
  source "$HOME/.fzf.zsh"
elif (( $+commands[fzf] )); then
  if [[ -n "$(fzf --zsh 2>/dev/null)" ]]; then
    source <(fzf --zsh)
  else
    [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
    [[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && source /usr/share/doc/fzf/examples/completion.zsh
  fi
fi

# ── zoxide ──
(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd cd)"

# ── 补全系统美化 ──
zstyle ':completion:*' menu select
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# ── fzf-tab 配置 ──
# 候选项少时保持足够的预览空间
zstyle ':fzf-tab:*' fzf-min-height 15
# Ctrl+/ 切换预览显示/隐藏
zstyle ':fzf-tab:*' fzf-bindings 'ctrl-/:toggle-preview'

# 通用预览（所有命令生效，默认隐藏，按 Ctrl+/ 显示）
# 目录 → eza 树形，文件 → bat 语法高亮，其他（flags/子命令）→ 补全描述
zstyle ':fzf-tab:complete:*:*' fzf-preview 'if [[ -d $realpath ]]; then eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath; elif [[ -f $realpath ]]; then batcat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -100 $realpath; elif [[ -n $desc ]]; then echo -E $desc; fi'
zstyle ':fzf-tab:complete:*:*' fzf-flags --preview-window=hidden,wrap

# 白名单命令覆盖（预览默认可见）
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi|ls|eza|exa|ll|la|tree|cat|less|more|head|tail|bat|batcat|vim|nvim|nano|code|view|cp|mv|rm|chmod|chown|source|\.|file|diff|stat):*' fzf-preview '[[ -d $realpath ]] && { eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath; } || { [[ -f $realpath ]] && { batcat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -100 $realpath; }; }'
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi|ls|eza|exa|ll|la|tree|cat|less|more|head|tail|bat|batcat|vim|nvim|nano|code|view|cp|mv|rm|chmod|chown|source|\.|file|diff|stat):*' fzf-flags --preview-window=wrap

# 特定命令预览覆盖（预览默认可见）
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps -p $word -o pid,user,%cpu,%mem,start,command --no-headers 2>/dev/null'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-flags --preview-window=wrap
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word 2>/dev/null'
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-flags --preview-window=wrap
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-preview 'echo ${(P)word}'
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-flags --preview-window=wrap

# 自定义命令预览示例（取消注释即可启用，预览默认可见）
# 对于支持 `cmd help subcommand` 的工具（如 rustup、cargo、docker），
# 可以覆盖通用规则，实现更丰富的子命令帮助预览
# zstyle ':fzf-tab:complete:rustup:*' fzf-preview 'if [[ -d $realpath ]]; then eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null; elif [[ -f $realpath ]]; then batcat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null; else rustup help $word 2>/dev/null; fi'
# zstyle ':fzf-tab:complete:rustup:*' fzf-flags --preview-window=wrap

ENV_BLOCK2

            case "$SELECTED_THEME" in
                pure)
                    echo ""
                    cat << 'PURE_BLOCK'
# ── Pure Theme ──
# pure 必须在 source oh-my-zsh.sh 之后加载
fpath+=("$HOME/.zsh/pure")
autoload -U promptinit; promptinit
zstyle :prompt:pure:git:stash show yes
prompt pure
PURE_BLOCK
                    ;;
                starship)
                    echo ""
                    cat << 'STARSHIP_BLOCK'
# ── Starship Prompt ──
# 配置文件: ~/.config/starship.toml
eval "$(starship init zsh)"
STARSHIP_BLOCK
                    ;;
                *)
                    echo ""
                    cat << 'P10K_BLOCK'
# ── Powerlevel10k Instant Prompt ──
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ── Powerlevel10k Theme ──
[[ -f ~/powerlevel10k/powerlevel10k.zsh-theme ]] && source ~/powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
P10K_BLOCK
                    ;;
            esac

            echo ""
            echo "# <<< one-click-dev-env <<<"
        } >> "$zshrc"

        success ".zshrc 配置完成 (插件管理器: Oh My Zsh, 主题: $SELECTED_THEME)"
    fi
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

uninstall_fzf() {
    header "卸载 fzf"
    if [[ -d "$HOME/.fzf" ]]; then
        rm -rf "$HOME/.fzf"
        rm -f "$HOME/.fzf.zsh" "$HOME/.fzf.bash"
        success "fzf 已卸载"
    elif command_exists fzf; then
        rm -f "$(which fzf)" 2>/dev/null || true
        success "fzf 已卸载"
    else
        info "fzf 未安装，跳过"
    fi
}

uninstall_zoxide() {
    header "卸载 zoxide"
    if command_exists zoxide || [[ -f "$HOME/.local/bin/zoxide" ]]; then
        rm -f "$HOME/.local/bin/zoxide"
        rm -rf "$HOME/.local/share/zoxide"
        success "zoxide 已卸载"
    else
        info "zoxide 未安装，跳过"
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
    uninstall_starship_theme
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

uninstall_fast_syntax_highlighting() {
    header "卸载 fast-syntax-highlighting"
    local target_dir="${ZSH_CUSTOM_DIR}/plugins/fast-syntax-highlighting"
    if [[ -d "$target_dir" ]]; then
        rm -rf "$target_dir"
        success "fast-syntax-highlighting 已卸载"
    else
        info "fast-syntax-highlighting 未安装，跳过"
    fi
}

uninstall_fzf_tab() {
    header "卸载 fzf-tab"
    local target_dir="${ZSH_CUSTOM_DIR}/plugins/fzf-tab"
    if [[ -d "$target_dir" ]]; then
        rm -rf "$target_dir"
        success "fzf-tab 已卸载"
    else
        info "fzf-tab 未安装，跳过"
    fi
}

uninstall_zsh_completions() {
    header "卸载 zsh-completions"
    local target_dir="${ZSH_CUSTOM_DIR}/plugins/zsh-completions"
    if [[ -d "$target_dir" ]]; then
        rm -rf "$target_dir"
        success "zsh-completions 已卸载"
    else
        info "zsh-completions 未安装，跳过"
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

uninstall_sheldon() {
    header "卸载 Sheldon"
    if command_exists sheldon || [[ -f "$HOME/.local/bin/sheldon" ]]; then
        rm -f "$HOME/.local/bin/sheldon"
        rm -rf "$HOME/.config/sheldon" "$HOME/.local/share/sheldon"
        success "Sheldon 已卸载"
    else
        info "Sheldon 未安装，跳过"
    fi
}

# 卸载时清理所有插件管理器
uninstall_plugin_mgr() {
    uninstall_sheldon
    uninstall_ohmyzsh
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

uninstall_starship_theme() {
    header "卸载 Starship"
    if command_exists starship || [[ -f "$HOME/.local/bin/starship" ]]; then
        rm -f "$HOME/.local/bin/starship"
        rm -f "$HOME/.config/starship.toml"
        success "Starship 已卸载"
    else
        info "Starship 未安装，跳过"
    fi
}

# ─── 耗时估算 ─────────────────────────────────────────────────────────────────

estimate_time() {
    echo -e "${BOLD}预估安装时间：${NC}"
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        echo "  • 基础依赖 + zsh + Sheldon:  ~2 分钟"
    else
        echo "  • 基础依赖 + zsh + Oh My Zsh:  ~2 分钟"
    fi
    echo "  • Rust + eza + yazi (cargo 编译): ~10-20 分钟"
    echo "  • Volta + Node/npm/pnpm:  ~2 分钟"
    echo "  • uv + Python:  ~2 分钟"
    echo "  • 其他:  ~1 分钟"
    echo -e "  ${BOLD}总计约 20-30 分钟${NC}（取决于网络和机器性能）"
    echo ""
}

# ─── 一键安装 ─────────────────────────────────────────────────────────────────

select_plugin_mgr() {
    echo ""
    echo -e "${BOLD}${CYAN}请选择插件管理器：${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}) ${BOLD}Sheldon${NC}$( [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]] && echo -e " ${YELLOW}★当前默认${NC}" )"
    echo -e "     ${GREEN}优势：${NC}Rust 编写极速加载、TOML 配置清晰、延迟加载支持、插件并行安装"
    echo -e "     ${YELLOW}注意：${NC}不包含 oh-my-zsh 内置插件/主题生态"
    echo ""
    echo -e "  ${CYAN}2${NC}) ${BOLD}Oh My Zsh${NC}$( [[ "$SELECTED_PLUGIN_MGR" == "ohmyzsh" ]] && echo -e " ${YELLOW}★当前默认${NC}" )"
    echo -e "     ${GREEN}优势：${NC}社区生态丰富、内置 300+ 插件/140+ 主题、文档完善"
    echo -e "     ${YELLOW}注意：${NC}启动速度稍慢、插件需手动 git clone"
    echo ""

    local default_choice="1"
    [[ "$SELECTED_PLUGIN_MGR" == "ohmyzsh" ]] && default_choice="2"

    read -rp "请选择 (1/2) [默认保持: ${SELECTED_PLUGIN_MGR}]: " pm_choice
    case "${pm_choice:-$default_choice}" in
        2) SELECTED_PLUGIN_MGR="ohmyzsh" ;;
        1) SELECTED_PLUGIN_MGR="sheldon" ;;
        *) SELECTED_PLUGIN_MGR="$SELECTED_PLUGIN_MGR" ;;
    esac
    success "已选择插件管理器: $SELECTED_PLUGIN_MGR"
}

select_theme() {
    echo ""
    echo -e "${BOLD}${CYAN}请选择终端主题：${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}) ${BOLD}Starship (catppuccin-powerline)${NC}$( [[ "$SELECTED_THEME" == "starship" ]] && echo -e " ${YELLOW}★当前默认${NC}" )"
    echo -e "     ${GREEN}优势：${NC}Rust 编写极速渲染、跨 Shell 统一、高度可定制、内置 git/语言检测"
    echo -e "     ${YELLOW}注意：${NC}推荐安装 Nerd Font 以获得最佳图标体验"
    echo ""
    echo -e "  ${CYAN}2${NC}) ${BOLD}Powerlevel10k${NC}$( [[ "$SELECTED_THEME" == "p10k" ]] && echo -e " ${YELLOW}★当前默认${NC}" )"
    echo -e "     ${GREEN}优势：${NC}高度可定制、丰富图标、Git 状态即时显示、Instant Prompt 极速启动"
    echo -e "     ${YELLOW}注意：${NC}需要在宿主机安装 Nerd Font 字体"
    echo ""
    echo -e "  ${CYAN}3${NC}) ${BOLD}Pure${NC}$( [[ "$SELECTED_THEME" == "pure" ]] && echo -e " ${YELLOW}★当前默认${NC}" )"
    echo -e "     ${GREEN}优势：${NC}极简美观、零配置、不依赖特殊字体、异步 Git 检测不阻塞输入"
    echo -e "     ${YELLOW}注意：${NC}宿主机${BOLD}无需${NC}${YELLOW}安装任何特殊字体${NC}"
    echo ""

    local default_choice="1"
    [[ "$SELECTED_THEME" == "p10k" ]] && default_choice="2"
    [[ "$SELECTED_THEME" == "pure" ]] && default_choice="3"

    read -rp "请选择 (1/2/3) [默认保持: ${SELECTED_THEME}]: " theme_choice
    case "${theme_choice:-$default_choice}" in
        1) SELECTED_THEME="starship" ;;
        2) SELECTED_THEME="p10k" ;;
        3) SELECTED_THEME="pure" ;;
        *) SELECTED_THEME="$SELECTED_THEME" ;;
    esac
    success "已选择主题: $SELECTED_THEME"

    # Starship 主题支持 Catppuccin 风味选择
    if [[ "$SELECTED_THEME" == "starship" ]]; then
        echo ""
        select_catppuccin_flavor
    fi
}

run_install_all() {
    header "🚀 开始一键安装所有开发环境组件"

    check_os
    check_network
    ensure_sudoers

    # 如果未通过 --plugin-mgr 指定插件管理器，则交互选择
    if [[ "${PLUGIN_MGR_SET_BY_FLAG:-}" != "1" ]]; then
        select_plugin_mgr
    fi

    # 如果未通过 --theme 指定主题，则交互选择
    if [[ "${THEME_SET_BY_FLAG:-}" != "1" ]]; then
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
    install_plugin_mgr
    install_theme
    install_zsh_autosuggestions
    install_fast_syntax_highlighting
    install_fzf_tab
    install_zsh_completions

    # 可选组件
    should_install "fzf" && install_fzf
    should_install "zoxide" && install_zoxide
    should_install "rustup" && install_rustup
    should_install "eza" && install_eza
    should_install "yazi" && install_yazi
    should_install "volta" && install_volta
    should_install "uv" && install_uv
    should_install "proto" && install_proto
    
    # 生成 CLI 工具的补全文件（必须在 configure_zshrc 之前）
    generate_completions

    # 清除旧的 zcompdump 缓存，确保新补全文件在下次登录时被加载
    rm -f "$HOME/.zcompdump"* 2>/dev/null

    # 配置
    configure_zshrc

    local end_time elapsed_min
    end_time=$(date +%s)
    elapsed_min=$(( (end_time - start_time) / 60 ))

    echo ""
    header "✅ 安装流程完成！(耗时 ${elapsed_min} 分钟)"
    echo -e "${BOLD}基础组件：${NC}"
    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        echo "  • Zsh + Sheldon"
    else
        echo "  • Zsh + Oh My Zsh"
    fi
    case "$SELECTED_THEME" in
        starship) echo "  • Starship 主题 (catppuccin-powerline)" ;;
        pure)     echo "  • Pure 主题" ;;
        *)        echo "  • Powerlevel10k 主题" ;;
    esac

    echo "  • zsh-autosuggestions"
    echo "  • fast-syntax-highlighting"
    echo "  • fzf-tab"
    echo "  • zsh-completions"

    echo -e "\n${BOLD}可选组件配置结果：${NC}"
    should_install "fzf" && echo "  • fzf (模糊搜索)"
    should_install "zoxide" && echo "  • zoxide (智能 cd)"
    should_install "rustup" && echo "  • Rust (rustup + cargo)"
    should_install "eza" && echo "  • eza"
    should_install "yazi" && echo "  • yazi"
    should_install "volta" && echo "  • Volta (Node.js + npm + pnpm)"
    should_install "uv" && echo "  • uv (Python)"
    should_install "proto" && echo "  • proto"

    print_summary

    echo ""
    case "$SELECTED_THEME" in
        starship)
            info "Starship (catppuccin-powerline) 主题已配置"
            info "配置文件: ${BOLD}~/.config/starship.toml${NC}"
            ;;
        pure)
            info "Pure 主题已配置，无需额外步骤"
            ;;
        *)
            warn "请手动运行 ${BOLD}p10k configure${NC}${YELLOW} 配置 Powerlevel10k 主题偏好${NC}"
            ;;
    esac

    echo ""
    if [[ "$SELECTED_THEME" != "pure" ]]; then
        info "如果终端中的 ${BOLD}图标显示为乱码或问号${NC}，说明缺少 Nerd Font 字体。"
        echo -e "  请在日常使用的终端软件（如 Windows Terminal, iTerm2, Alacritty 等）中配置字体为 ${BOLD}MesloLGS NF${NC}。"
        echo -e "  ${YELLOW}字体安装命令提示：${NC}"
        echo -e "    • ${BOLD}Windows (WSL)${NC}: 在宿主机 PowerShell 中运行 ${CYAN}iex (iwr -useb https://raw.githubusercontent.com/romkatv/powerlevel10k-media/master/fonts.ps1)${NC}"
        echo -e "    • ${BOLD}macOS${NC}: ${CYAN}brew tap homebrew/cask-fonts && brew install --cask font-meslo-lg-nerd-font${NC}"
        echo -e "    • ${BOLD}Linux${NC}: 下载并移动字体文件至 ${CYAN}~/.local/share/fonts${NC}，然后运行 ${CYAN}fc-cache -f -v${NC}"
        echo ""
    fi

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
    uninstall_zoxide
    uninstall_fzf
    uninstall_fast_syntax_highlighting
    uninstall_fzf_tab
    uninstall_zsh_completions
    uninstall_zsh_autosuggestions
    uninstall_theme
    uninstall_rustup
    uninstall_plugin_mgr
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
        plugin-mgr)
            if command_exists sheldon; then
                echo -e "${GREEN}● sheldon${NC}"
            elif [[ -d "$HOME/.oh-my-zsh" ]]; then
                echo -e "${GREEN}● ohmyzsh${NC}"
            else
                echo -e "${RED}○${NC}"
            fi
            ;;
        rustup)       command_exists rustc && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        eza)          command_exists eza && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        yazi)         command_exists yazi && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        theme)
            if command_exists starship || [[ -f "$HOME/.local/bin/starship" ]]; then
                echo -e "${GREEN}● starship${NC}"
            elif [[ -d "$HOME/powerlevel10k" ]] || [[ -d "$HOME/.local/share/sheldon/repos/github.com/romkatv/powerlevel10k" ]]; then
                echo -e "${GREEN}● p10k${NC}"
            elif [[ -d "$HOME/.zsh/pure" ]] || [[ -d "$HOME/.local/share/sheldon/repos/github.com/sindresorhus/pure" ]]; then
                echo -e "${GREEN}● pure${NC}"
            else
                echo -e "${RED}○${NC}"
            fi
            ;;
        zsh-autosuggestions)
            if [[ -d "${ZSH_CUSTOM_DIR}/plugins/zsh-autosuggestions" ]] || [[ -d "$HOME/.local/share/sheldon/repos/github.com/zsh-users/zsh-autosuggestions" ]]; then
                echo -e "${GREEN}●${NC}"
            else
                echo -e "${RED}○${NC}"
            fi
            ;;
        fast-syntax-highlighting)
            if [[ -d "${ZSH_CUSTOM_DIR}/plugins/fast-syntax-highlighting" ]] || [[ -d "$HOME/.local/share/sheldon/repos/github.com/zdharma-continuum/fast-syntax-highlighting" ]]; then
                echo -e "${GREEN}●${NC}"
            else
                echo -e "${RED}○${NC}"
            fi
            ;;
        fzf-tab)
            if [[ -d "${ZSH_CUSTOM_DIR}/plugins/fzf-tab" ]] || [[ -d "$HOME/.local/share/sheldon/repos/github.com/Aloxaf/fzf-tab" ]]; then
                echo -e "${GREEN}●${NC}"
            else
                echo -e "${RED}○${NC}"
            fi
            ;;
        zsh-completions)
            if [[ -d "${ZSH_CUSTOM_DIR}/plugins/zsh-completions" ]] || [[ -d "$HOME/.local/share/sheldon/repos/github.com/zsh-users/zsh-completions" ]]; then
                echo -e "${GREEN}●${NC}"
            else
                echo -e "${RED}○${NC}"
            fi
            ;;
        fzf)          command_exists fzf && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
        zoxide)       command_exists zoxide && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
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

    # 基础组件 ID（安装时锁定必选，卸载时从列表排除）
    local -a protected_ids=("apt-deps" "zsh" "plugin-mgr" "theme" "zsh-autosuggestions" "fast-syntax-highlighting" "fzf-tab" "zsh-completions")

    _is_protected() {
        local id="$1"
        for pid in "${protected_ids[@]}"; do
            [[ "$id" == "$pid" ]] && return 0
        done
        return 1
    }

    local -a names=()
    local -a descs=()
    local -a statuses=()
    local -a checked=()
    local -a locked=()    # "true" = 不可切换

    # 初始化选项
    for i in "${!COMPONENTS[@]}"; do
        local comp="${COMPONENTS[$i]}"
        local id="${comp%%:*}"

        # 卸载模式：排除基础组件
        if [[ "$action" == "uninstall" ]] && _is_protected "$id"; then
            continue
        fi

        names+=("$id")
        descs+=("${comp##*:}")
        statuses+=("$(show_status_indicator "$id")")

        if [[ "$action" == "install" ]] && _is_protected "$id"; then
            # 安装模式：基础组件默认选中且锁定
            checked+=("true")
            locked+=("true")
        else
            # 其他组件默认不选
            checked+=("false")
            locked+=("false")
        fi
    done

    local total=${#names[@]}
    local cursor=0

    if [[ $total -eq 0 ]]; then
        warn "没有可${action_label}的组件"
        return
    fi

    # 绘制菜单
    _draw_menu() {
        for i in "${!descs[@]}"; do
            local pointer="  "
            [[ $i -eq $cursor ]] && pointer="${CYAN}▸${NC} "

            local checkbox
            if [[ "${locked[$i]}" == "true" ]]; then
                # 锁定项：始终选中，灰色显示
                checkbox="${GREEN}[✔]${NC} 🔒"
            elif [[ "${checked[$i]}" == "true" ]]; then
                checkbox="${GREEN}[✔]${NC}   "
            else
                checkbox="[ ]   "
            fi

            printf "\r  %b%b %-36s %b ${BOLD}[%s]${NC}\n" \
                "$pointer" "$checkbox" "${descs[$i]}" "${statuses[$i]}" "${names[$i]}"
        done
        # 操作提示
        echo -e "  ${BOLD}────────────────────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}↑/↓${NC} 移动  ${CYAN}空格${NC} 选中/取消  ${CYAN}a${NC} 全选  ${CYAN}n${NC} 全不选  ${CYAN}回车${NC} 确认  ${CYAN}q${NC} 取消"
    }

    echo -e "\n${BOLD}请选择要${action_label}的组件：${NC}"
    echo -e "  ${GREEN}●${NC} = 已安装    ${RED}○${NC} = 未安装"
    if [[ "$action" == "uninstall" ]]; then
        echo -e "  ${YELLOW}提示：基础组件（apt-deps, zsh, 插件管理器）仅可通过一键卸载移除${NC}"
    fi
    echo ""

    # 隐藏光标
    tput civis 2>/dev/null

    # 首次绘制
    _draw_menu

    # 交互循环
    while true; do
        local key
        IFS= read -rsn1 key

        case "$key" in
            $'\x1b')
                # 读取方向键序列
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A') (( cursor > 0 )) && (( cursor-- )) ;;
                    '[B') (( cursor < total - 1 )) && (( cursor++ )) ;;
                esac
                ;;
            ' ')
                # 空格：切换选中状态（跳过锁定项）
                if [[ "${locked[$cursor]}" != "true" ]]; then
                    if [[ "${checked[$cursor]}" == "true" ]]; then
                        checked[$cursor]="false"
                    else
                        checked[$cursor]="true"
                    fi
                fi
                ;;
            '')
                # 回车：确认选择
                break
                ;;
            'a'|'A')
                # 全选（跳过锁定项，它们已经是 true）
                for i in "${!checked[@]}"; do
                    [[ "${locked[$i]}" != "true" ]] && checked[$i]="true"
                done
                ;;
            'n'|'N')
                # 全不选（跳过锁定项）
                for i in "${!checked[@]}"; do
                    [[ "${locked[$i]}" != "true" ]] && checked[$i]="false"
                done
                ;;
            'q'|'Q')
                # 退出
                tput cnorm 2>/dev/null
                info "已取消"
                return
                ;;
        esac

        # 光标回到菜单顶部重绘（菜单行数 = total + 2 行提示）
        printf "\033[%dA\r" "$((total + 2))"
        _draw_menu
    done

    # 恢复光标
    tput cnorm 2>/dev/null
    echo ""

    # 收集选中项
    local selected=()
    for i in "${!checked[@]}"; do
        if [[ "${checked[$i]}" == "true" ]]; then
            selected+=("${names[$i]}")
        fi
    done

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
                    starship)  SELECTED_THEME="starship"; THEME_SET_BY_FLAG=1 ;;
                    pure)      SELECTED_THEME="pure"; THEME_SET_BY_FLAG=1 ;;
                    p10k)      SELECTED_THEME="p10k"; THEME_SET_BY_FLAG=1 ;;
                    *)         error "无效主题: ${1:-}（可选: starship, p10k, pure）"; exit 1 ;;
                esac
                shift
                ;;
            --flavor)
                shift
                case "${1:-}" in
                    mocha)      SELECTED_CATPPUCCIN_FLAVOR="mocha" ;;
                    macchiato)  SELECTED_CATPPUCCIN_FLAVOR="macchiato" ;;
                    frappe)     SELECTED_CATPPUCCIN_FLAVOR="frappe" ;;
                    latte)      SELECTED_CATPPUCCIN_FLAVOR="latte" ;;
                    *)          error "无效风味: ${1:-}（可选: mocha, macchiato, frappe, latte）"; exit 1 ;;
                esac
                shift
                ;;
            --plugin-mgr)
                shift
                case "${1:-}" in
                    sheldon)  SELECTED_PLUGIN_MGR="sheldon"; PLUGIN_MGR_SET_BY_FLAG=1 ;;
                    ohmyzsh)  SELECTED_PLUGIN_MGR="ohmyzsh"; PLUGIN_MGR_SET_BY_FLAG=1 ;;
                    *)        error "无效插件管理器: ${1:-}（可选: sheldon, ohmyzsh）"; exit 1 ;;
                esac
                shift
                ;;
            --components)
                shift
                # 支持空格分隔和逗号分隔: --components rustup eza volta 或 --components rustup,eza,volta
                local _comps=""
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    if [[ -n "$_comps" ]]; then
                        _comps="${_comps},${1}"
                    else
                        _comps="$1"
                    fi
                    shift
                done
                SELECTED_COMPONENTS="$_comps"
                ;;
            --auto-cleanup)
                AUTO_CLEANUP=1
                shift
                ;;
            --help|-h)
                echo "Linux 开发环境管理工具"
                echo ""
                echo "用法: $0 [--install | --uninstall] [--plugin-mgr sheldon|ohmyzsh] [--theme starship|p10k|pure] [--components comp1 ...] [--help]"
                echo ""
                echo "选项:"
                echo "  --install              一键安装所有组件"
                echo "  --uninstall            一键卸载所有组件"
                echo "  --plugin-mgr sheldon|ohmyzsh"
                echo "                         指定插件管理器（默认: sheldon）"
                echo "    sheldon  Sheldon      极速加载、TOML 配置、延迟加载"
                echo "    ohmyzsh  Oh My Zsh    社区生态丰富、300+ 插件"
                echo "  --theme starship|p10k|pure"
                echo "                         指定终端主题（默认: starship）"
                echo "    starship Starship     极速渲染、跨 Shell、catppuccin-powerline 预设"
                echo "    p10k     Powerlevel10k 高度可定制、丰富图标（需 Nerd Font）"
                echo "    pure     Pure          极简美观、无需特殊字体"
                echo "  --components comp1 [comp2 ...]"
                echo "                         指定要安装的可选组件，不传则安装全部"
                echo "                         例: --components rustup eza volta"
                echo "                         可选值: fzf, zoxide, rustup, eza, yazi, volta, uv, proto"
                echo "  --help, -h             显示帮助信息"
                echo "  （无参数）              进入交互界面"
                echo ""
                echo "日志文件: $LOG_FILE"
                exit 0
                ;;
            *)
                error "未知选项: $1"
                echo "用法: $0 [--install | --uninstall] [--plugin-mgr sheldon|ohmyzsh] [--theme starship|p10k|pure] [--components comp1 ...] [--help]"
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
