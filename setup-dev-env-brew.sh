#!/usr/bin/env bash
# =============================================================================
# setup-dev-env-brew.sh — 跨平台开发环境一键安装/卸载脚本 (Homebrew 版)
# 适用于 macOS 和 Linux（使用 Homebrew / Linuxbrew 作为包管理器）
#
# 用法:
#   bash setup-dev-env-brew.sh --install                一键安装（未指定插件管理器/主题时会交互询问）
#   bash setup-dev-env-brew.sh --install --plugin-mgr sheldon --theme starship  全自动安装（无交互）
#   bash setup-dev-env-brew.sh --uninstall              一键卸载所有组件（需确认）
#   bash setup-dev-env-brew.sh                          进入交互界面
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

# ─── 平台检测 ─────────────────────────────────────────────────────────────────
IS_MACOS=false
IS_LINUX=false

detect_platform() {
    case "$(uname -s)" in
        Darwin)
            IS_MACOS=true
            info "检测到系统: macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
            # 检查 Xcode Command Line Tools（Homebrew 的前置依赖）
            if ! xcode-select -p &>/dev/null; then
                warn "未检测到 Xcode Command Line Tools（Homebrew 依赖项）"
                info "正在安装 Xcode Command Line Tools..."
                xcode-select --install 2>/dev/null || true
                echo ""
                read -rp "请在弹出的安装窗口中完成安装后，按回车继续..." _
            fi
            ;;
        Linux)
            IS_LINUX=true
            local pretty_name
            pretty_name=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -sr)
            info "检测到系统: $pretty_name"
            ;;
        *)
            error "不支持的操作系统: $(uname -s)（仅支持 macOS 和 Linux）"
            exit 1
            ;;
    esac
}

# ─── Homebrew 初始化 ──────────────────────────────────────────────────────────

# 查找 brew 可执行文件路径
_find_brew() {
    if command -v brew &>/dev/null; then
        command -v brew
        return 0
    fi
    # 常见安装路径
    local candidates=(
        "/opt/homebrew/bin/brew"          # macOS Apple Silicon
        "/usr/local/bin/brew"             # macOS Intel
        "/home/linuxbrew/.linuxbrew/bin/brew"  # Linux
        "$HOME/.linuxbrew/bin/brew"       # Linux（用户目录安装）
    )
    for path in "${candidates[@]}"; do
        if [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

# 确保 Homebrew 已安装并加载到当前 shell
ensure_homebrew() {
    header "检查 Homebrew"

    local brew_bin
    if brew_bin=$(_find_brew); then
        # 加载 brew shellenv 到当前 shell
        eval "$("$brew_bin" shellenv)"
        success "Homebrew 已安装: $(brew --version | head -1)"
        return 0
    fi

    # Homebrew 未安装，询问用户
    warn "未检测到 Homebrew"
    echo -e "  Homebrew 是本脚本的核心包管理器，安装后将用于管理所有开发工具。"
    echo -e "  官网: ${CYAN}https://brew.sh${NC}"
    echo ""
    read -rp "是否自动安装 Homebrew？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        error "Homebrew 是必要依赖，无法继续"
        exit 1
    fi

    info "正在安装 Homebrew..."
    if ! NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1 | tee -a "$LOG_FILE"; then
        error "Homebrew 安装失败"
        exit 1
    fi

    # 安装后重新查找并加载
    if brew_bin=$(_find_brew); then
        eval "$("$brew_bin" shellenv)"
        success "Homebrew 安装完成: $(brew --version | head -1)"
    else
        error "Homebrew 安装后仍无法找到 brew 命令"
        exit 1
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
# 自动检测: 优先尊重已有 oh-my-zsh 配置；仅当无 oh-my-zsh 时才默认 sheldon
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    SELECTED_PLUGIN_MGR="ohmyzsh"
else
    SELECTED_PLUGIN_MGR="sheldon"
fi
# Catppuccin 风味: mocha (默认), macchiato, frappe, latte
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
    "brew-deps:基础依赖包 (Homebrew)"
    "zsh:Zsh Shell"
    "plugin-mgr:插件管理器 (Sheldon/Oh My Zsh)"
    "theme:终端主题 (starship/p10k/pure)"
    "zsh-autosuggestions:zsh-autosuggestions 插件"
    "fast-syntax-highlighting:fast-syntax-highlighting 插件"
    "fzf:fzf (模糊搜索)"
    "fzf-tab:fzf-tab (模糊补全)"
    "zsh-completions:zsh-completions (补全定义)"
    "zoxide:zoxide (智能 cd)"
    "rustup:Rust 工具链 (rustup)"
    "eza:eza (现代 ls 替代)"
    "yazi:yazi (终端文件管理器)"
    "volta:Volta (Node/npm/pnpm 版本管理)"
    "uv:uv (Python 版本管理)"
    "proto:proto (多语言版本管理)"
)

# ─── 跨平台工具函数 ───────────────────────────────────────────────────────────
# ZSH_CUSTOM_DIR 仅在 Oh My Zsh 模式下使用
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

command_exists() { command -v "$1" &>/dev/null; }

# 跨平台 sed -i：macOS BSD sed 要求 -i 后跟空字符串参数，GNU sed 不需要
sed_inplace() {
    if [[ "$IS_MACOS" == true ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# 跨平台 readlink -f：macOS 不支持 readlink -f
portable_readlink() {
    if [[ "$IS_MACOS" == true ]]; then
        # macOS: 使用 python 或 perl 解析（避免依赖 coreutils）
        # 使用 sys.argv 传参避免文件名中特殊字符（如单引号）导致注入
        python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null \
            || perl -MCwd -e 'print Cwd::abs_path shift' "$1" 2>/dev/null \
            || echo "$1"
    else
        readlink -f "$1"
    fi
}

# 统一重写 oh-my-zsh 的 plugins=(...) 配置。
# 兼容：
# - plugins=(git eza)
# - plugins = ( git eza )
# - 多行数组 / inline + 多行混合格式
# 若未找到 plugins 块，则自动插入到 source oh-my-zsh.sh 之前。
update_omz_plugins_block() {
    local zshrc="$1"
    local plugins_line="$2"

    [[ -f "$zshrc" ]] || return 0

    awk -v repl="$plugins_line" '
        BEGIN { in_plugins=0; replaced=0; inserted=0 }

        !replaced && !in_plugins && $0 ~ /^[[:space:]]*plugins[[:space:]]*=[[:space:]]*\(/ {
            print repl
            replaced=1
            if ($0 ~ /\)/) {
                next
            }
            in_plugins=1
            next
        }

        in_plugins {
            if ($0 ~ /\)/) {
                in_plugins=0
            }
            next
        }

        !replaced && !inserted && $0 ~ /^[[:space:]]*source[[:space:]]+.*oh-my-zsh\.sh/ {
            print repl
            inserted=1
        }

        { print }

        END {
            if (!replaced && !inserted) {
                print repl
            }
        }
    ' "$zshrc" > "${zshrc}.tmp" && mv "${zshrc}.tmp" "$zshrc"
}

# 在匹配行之前插入多行文本（跨平台兼容 GNU/BSD）。
# 使用 awk + ENVIRON 避免 sed 在 macOS 和 Linux 间的换行符处理差异
# 注意：pattern 中避免使用 [[:space:]] 等 POSIX 字符类——macOS nawk 在动态
#       regex（字符串变量 ~ 匹配）中不一定支持 POSIX 字符类，仅在 /regex/
#       字面量中可靠。改用 index() 做固定字符串匹配以确保跨平台兼容。
insert_before_pattern() {
    local file="$1"
    local pattern="$2"   # 此参数现在作为 index() 的固定子串而非正则
    local text="$3"

    [[ -f "$file" ]] || return 0

    _IBFP_TEXT="$text" _IBFP_PAT="$pattern" awk '
        !done && index($0, ENVIRON["_IBFP_PAT"]) { print ENVIRON["_IBFP_TEXT"]; done=1 }
        { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# 删除 oh-my-zsh 的 plugins=(...) 块（兼容单行和多行格式）。
remove_omz_plugins_block() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    awk '
        /^[[:space:]]*plugins[[:space:]]*=[[:space:]]*\(/ {
            if (/\)/) { next }
            in_plugins=1
            next
        }
        in_plugins {
            if (/\)/) { in_plugins=0 }
            next
        }
        { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# ─── 已有环境检测 ─────────────────────────────────────────────────────────────

detect_existing_setup() {
    info "检测已有环境..."

    # Oh My Zsh
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        info "检测到已安装 Oh My Zsh"
    fi

    # Sheldon
    if command_exists sheldon; then
        info "检测到已安装 Sheldon: $(sheldon --version 2>/dev/null)"
    fi

    # zsh-syntax-highlighting → fast-syntax-highlighting 迁移提示
    local omz_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    if [[ -d "${omz_custom}/plugins/zsh-syntax-highlighting" ]]; then
        warn "检测到 zsh-syntax-highlighting 插件"
        warn "  本脚本使用 fast-syntax-highlighting 替代（性能更好、高亮更丰富）"
        warn "  已有 zsh-syntax-highlighting 不会被删除，但不再加载"
    fi

    # 检测现有 .zshrc 管理块
    if [[ -f "$HOME/.zshrc" ]] && grep -q "one-click-dev-env" "$HOME/.zshrc" 2>/dev/null; then
        info "检测到 .zshrc 中已有本工具的配置块，将会更新"
    fi

    # 检测已有主题
    if command_exists starship; then
        info "检测到已安装 Starship: $(starship --version 2>&1 | head -1)"
    fi
    if [[ -d "$HOME/powerlevel10k" ]]; then
        info "检测到已安装 Powerlevel10k"
    fi
    if [[ -d "$HOME/.zsh/pure" ]]; then
        info "检测到已安装 Pure 主题"
    fi

    echo ""
}

# ─── 网络检测 ─────────────────────────────────────────────────────────────────

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

# ─── Cargo / Volta / uv / proto 环境加载 ─────────────────────────────────────

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
                    printf "${bg}${fg}    --prompt='\''\\u276f '\''${R}\n"
                    printf "${bg}${fg}  \"${R}\n"
                ' \
                --preview-window=right:55%:wrap)

        SELECTED_CATPPUCCIN_FLAVOR="${selected:-$SELECTED_CATPPUCCIN_FLAVOR}"
    fi

    success "已选择 Catppuccin 风味: $SELECTED_CATPPUCCIN_FLAVOR"
}

# ─── 补全文件生成 ─────────────────────────────────────────────────────────────

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
    # volta
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
    # eza（brew 安装通常已包含补全文件，但仍可从 GitHub 下载确保匹配）
    if command_exists eza; then
        local eza_ver
        # 使用 grep -oE（跨平台兼容，不依赖 PCRE 的 -P 参数）
        eza_ver="$(eza --version | grep -oE 'v[0-9.]+' | head -1)"
        if [[ -n "$eza_ver" ]]; then
            curl -fsSL "https://raw.githubusercontent.com/eza-community/eza/${eza_ver}/completions/zsh/_eza" \
                > "$comp_dir/_eza" 2>>"$LOG_FILE" && generated+=(eza)
            if [[ ! -s "$comp_dir/_eza" ]]; then
                warn "eza ${eza_ver} 的补全文件不存在，回退到 main 分支"
                curl -fsSL "https://raw.githubusercontent.com/eza-community/eza/main/completions/zsh/_eza" \
                    > "$comp_dir/_eza" 2>>"$LOG_FILE"
            fi
        fi
    fi
    # docker
    if command_exists docker; then
        docker completion zsh > "$comp_dir/_docker" 2>>"$LOG_FILE" && generated+=(docker)
    fi
    # gh (GitHub CLI)
    if command_exists gh; then
        gh completion -s zsh > "$comp_dir/_gh" 2>>"$LOG_FILE" && generated+=(gh)
    fi
    # pnpm
    if command_exists pnpm; then
        pnpm completion zsh > "$comp_dir/_pnpm" 2>>"$LOG_FILE" && generated+=(pnpm)
    fi
    # rg (ripgrep ≥ 14.0)
    if command_exists rg; then
        rg --generate complete-zsh > "$comp_dir/_rg" 2>>"$LOG_FILE" && generated+=(rg)
    fi
    # bun
    if command_exists bun; then
        bun completions > "$comp_dir/_bun" 2>>"$LOG_FILE" && generated+=(bun)
    fi
    # turbo
    if command_exists turbo; then
        turbo completion zsh > "$comp_dir/_turbo" 2>>"$LOG_FILE" && generated+=(turbo)
    fi
    # just
    if command_exists just; then
        just --completions zsh > "$comp_dir/_just" 2>>"$LOG_FILE" && generated+=(just)
    fi
    # yazi (ya = yazi-cli)
    if command_exists ya; then
        ya completion zsh > "$comp_dir/_ya" 2>>"$LOG_FILE" && generated+=(yazi)
    fi

    # 验证：删除空文件（可能是命令静默失败）
    local f fname
    for f in "$comp_dir"/_*; do
        [[ -f "$f" ]] || continue
        if [[ ! -s "$f" ]]; then
            fname="$(basename "$f")"
            warn "补全文件为空，已删除: ${fname}（请检查日志 ${LOG_FILE}）"
            rm -f "$f"
        fi
    done

    if [[ ${#generated[@]} -gt 0 ]]; then
        info "补全文件已生成到: $comp_dir (${generated[*]})"
    else
        info "未检测到可生成补全的工具"
    fi
}

# ─── 安装函数 ─────────────────────────────────────────────────────────────────

install_brew_deps() {
    header "安装基础依赖包 (Homebrew)"
    log_start "brew-deps"

    info "更新 Homebrew..."
    brew update 2>&1 | tee -a "$LOG_FILE" || warn "brew update 部分失败，继续..."

    local packages=(
        curl wget git
        fd bat ripgrep jq
        imagemagick p7zip poppler ffmpeg
    )

    local missing_pkgs=()
    for pkg in "${packages[@]}"; do
        if ! brew ls --versions "$pkg" &>/dev/null; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
        success "所有基础依赖已安装"
    else
        info "需要安装: ${missing_pkgs[*]}"
        if brew install "${missing_pkgs[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            success "基础依赖安装完成"
        else
            # 逐个尝试安装，避免某个包失败导致全部失败
            warn "批量安装失败，尝试逐个安装..."
            for pkg in "${missing_pkgs[@]}"; do
                brew install "$pkg" 2>&1 | tee -a "$LOG_FILE" || warn "包 $pkg 安装失败，跳过"
            done
        fi
    fi

    log_end "brew-deps" $?
}

install_zsh() {
    header "安装 Zsh"
    log_start "zsh"

    if command_exists zsh; then
        # 检查版本是否 >= 5.9
        local zsh_ver major minor
        zsh_ver="$(zsh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
        major="${zsh_ver%%.*}"
        minor="${zsh_ver##*.}"

        if [[ "${major:-0}" -gt 5 ]] || { [[ "${major:-0}" -eq 5 ]] && [[ "${minor:-0}" -ge 9 ]]; }; then
            success "Zsh 已安装且版本足够新: $(zsh --version)"
        else
            info "Zsh 版本过旧 ($zsh_ver)，通过 Homebrew 安装最新版..."
            if ! brew install zsh 2>&1 | tee -a "$LOG_FILE"; then
                record_failure "zsh"
                return 1
            fi
            success "Zsh 已更新: $(zsh --version)"
        fi
    else
        info "通过 Homebrew 安装 Zsh..."
        if ! brew install zsh 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "zsh"
            return 1
        fi
        success "Zsh 安装完成: $(zsh --version)"
    fi

    # 设置 zsh 为默认 shell
    if [[ "$SHELL" != *"zsh"* ]]; then
        local target_zsh
        target_zsh="$(which zsh)"

        # 确保目标 zsh 在 /etc/shells 中（brew 安装的 zsh 路径可能不在）
        if ! grep -qF "$target_zsh" /etc/shells 2>/dev/null; then
            info "将 $target_zsh 添加到 /etc/shells..."
            echo "$target_zsh" | sudo tee -a /etc/shells >/dev/null
        fi

        # macOS 和 Linux 的 chsh 处理
        if [[ "$IS_MACOS" == true ]]; then
            info "正在切换默认 shell 为 Zsh（可能需要输入密码）..."
            chsh -s "$target_zsh" 2>&1 | tee -a "$LOG_FILE" || warn "chsh 失败，可手动运行: chsh -s $target_zsh"
        else
            if sudo chsh -s "$target_zsh" "$USER" 2>&1 | tee -a "$LOG_FILE"; then
                info "已将 Zsh 设为默认 shell（下次登录生效）"
            else
                warn "chsh 失败，可手动运行: chsh -s \$(which zsh)"
            fi
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

    # 确保 ZSH_CUSTOM_DIR 更新
    ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    log_end "ohmyzsh" $?
}

install_sheldon() {
    header "安装 Sheldon 插件管理器"
    log_start "sheldon"

    if command_exists sheldon; then
        success "Sheldon 已安装: $(sheldon --version)"
    else
        info "通过 Homebrew 安装 Sheldon..."
        if brew install sheldon 2>&1 | tee -a "$LOG_FILE"; then
            success "Sheldon 安装完成: $(sheldon --version)"
        else
            # 回退到 curl 安装方式
            warn "brew install sheldon 失败，尝试预编译二进制安装..."
            mkdir -p "$HOME/.local/bin"
            export PATH="$HOME/.local/bin:$PATH"

            if ! curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
                | bash -s -- --repo rossmacarthur/sheldon --to "$HOME/.local/bin" 2>&1 \
                | tee -a "$LOG_FILE"; then
                record_failure "sheldon"
                return 1
            fi
            success "Sheldon 安装完成（二进制）: $(sheldon --version)"
        fi
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

    if command_exists starship; then
        success "Starship 已安装: $(starship --version 2>&1 | head -1)"
    else
        info "通过 Homebrew 安装 Starship..."
        if brew install starship 2>&1 | tee -a "$LOG_FILE"; then
            success "Starship 安装完成"
        else
            # 回退到 curl 安装方式
            warn "brew install starship 失败，尝试脚本安装..."
            mkdir -p "$HOME/.local/bin"
            if ! curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin" 2>&1 | tee -a "$LOG_FILE"; then
                record_failure "starship-theme"
                return 1
            fi
            export PATH="$HOME/.local/bin:$PATH"
            success "Starship 安装完成（脚本方式）"
        fi
    fi

    # 配置 catppuccin-powerline 预设
    local starship_config="$HOME/.config/starship.toml"
    if [[ -f "$starship_config" ]]; then
        if grep -q '^palette' "$starship_config"; then
            sed_inplace "s/^palette.*/palette = \"catppuccin_${SELECTED_CATPPUCCIN_FLAVOR}\"/" "$starship_config"
            success "Catppuccin 风味已更新为: $SELECTED_CATPPUCCIN_FLAVOR"
        else
            info "Starship 配置已存在但非 Catppuccin 预设，保留现有配置"
        fi
    else
        info "正在生成 catppuccin-powerline 预设..."
        mkdir -p "$HOME/.config"
        if starship preset catppuccin-powerline -o "$starship_config" 2>&1 | tee -a "$LOG_FILE"; then
            if grep -q '^palette' "$starship_config"; then
                sed_inplace "s/^palette.*/palette = \"catppuccin_${SELECTED_CATPPUCCIN_FLAVOR}\"/" "$starship_config"
            fi
            # 确保 line_break 不被禁用
            if grep -q '^\[line_break\]' "$starship_config"; then
                # 跨平台：用 awk 替代 sed 多行范围操作
                awk '
                    /^\[line_break\]/ { in_section=1 }
                    in_section && /^\[/ && !/^\[line_break\]/ { in_section=0 }
                    in_section && /disabled = true/ { sub(/disabled = true/, "disabled = false") }
                    { print }
                ' "$starship_config" > "${starship_config}.tmp" && mv "${starship_config}.tmp" "$starship_config"
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
        # 检测并提示 zsh-syntax-highlighting 迁移
        local old_dir="${ZSH_CUSTOM_DIR}/plugins/zsh-syntax-highlighting"
        if [[ -d "$old_dir" ]]; then
            warn "检测到旧版 zsh-syntax-highlighting，fast-syntax-highlighting 将替代其功能"
            warn "  旧插件目录保留在: ${old_dir}（不会自动删除）"
        fi

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
        info "通过 Homebrew 安装 fzf..."
        if ! brew install fzf 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "fzf"
            return 1
        fi

        # 设置 shell 集成（创建 ~/.fzf.zsh 等）
        local fzf_install="$(brew --prefix)/opt/fzf/install"
        if [[ -x "$fzf_install" ]]; then
            "$fzf_install" --key-bindings --completion --no-update-rc --no-bash --no-fish 2>&1 | tee -a "$LOG_FILE"
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
        info "通过 Homebrew 安装 zoxide..."
        if ! brew install zoxide 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "zoxide"
            return 1
        fi
        success "zoxide 安装完成"
    fi

    log_end "zoxide" $?
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

    if command_exists eza; then
        success "eza 已安装: $(eza --version | head -1)"
    else
        info "通过 Homebrew 安装 eza..."
        if ! brew install eza 2>&1 | tee -a "$LOG_FILE"; then
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

    if command_exists yazi; then
        success "yazi 已安装"
    else
        info "通过 Homebrew 安装 yazi..."
        if ! brew install yazi 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "yazi"
            return 1
        fi
        success "yazi 安装完成"
    fi

    log_end "yazi" $?
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
# Generated by setup-dev-env-brew.sh
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

    # compinit
    cat >> "$plugins_toml" << 'COMPINIT_BLOCK'
[plugins.compinit]
inline = '''
autoload -Uz compinit && compinit
'''

COMPINIT_BLOCK

    # 插件（顺序：fzf-tab → completion-styles → ohmyzsh-git → autosuggestions → syntax-highlighting）
    # 注意：fzf-tab 预览中优先使用 bat（brew 安装的命令名），batcat 作为 apt 回退
    # kill 预览使用 tail -n +2 跳过 ps 表头（跨平台兼容 BSD/GNU ps）
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
# 目录 → eza 树形，文件 → bat 语法高亮，其他 → 补全描述
zstyle ':fzf-tab:complete:*:*' fzf-preview 'if [[ -d $realpath ]]; then eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath; elif [[ -f $realpath ]]; then bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -100 $realpath; elif [[ -n $desc ]]; then echo -E $desc; fi'
zstyle ':fzf-tab:complete:*:*' fzf-flags --preview-window=hidden,wrap

# fzf-tab: 白名单命令覆盖（预览默认可见）
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi|ls|eza|exa|ll|la|tree|cat|less|more|head|tail|bat|vim|nvim|nano|code|view|cp|mv|rm|chmod|chown|source|\.|file|diff|stat):*' fzf-preview '[[ -d $realpath ]] && { eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath; } || { [[ -f $realpath ]] && { bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -100 $realpath; }; }'
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi|ls|eza|exa|ll|la|tree|cat|less|more|head|tail|bat|vim|nvim|nano|code|view|cp|mv|rm|chmod|chown|source|\.|file|diff|stat):*' fzf-flags --preview-window=wrap

# fzf-tab: 特定命令预览覆盖（预览默认可见）
# kill: 使用 tail -n +2 跳过 ps 表头（跨平台兼容 BSD/GNU ps）
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps -p $word -o pid,user,%cpu,%mem,etime,command 2>/dev/null | tail -n +2'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-flags --preview-window=wrap
# systemctl: 仅在 Linux 上有效，macOS 上会静默跳过
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word 2>/dev/null'
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-flags --preview-window=wrap
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-preview 'echo ${(P)word}'
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-flags --preview-window=wrap
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

    # sudo: ESC ESC 在命令前加/去 sudo
    cat >> "$plugins_toml" << 'SUDO_PLUGIN'
[plugins.ohmyzsh-sudo]
github = "ohmyzsh/ohmyzsh"
use = ["plugins/sudo/sudo.plugin.zsh"]
apply = ["defer"]

SUDO_PLUGIN

    # ssh-agent: 自动启动 SSH agent
    cat >> "$plugins_toml" << 'SSH_AGENT_PLUGIN'
[plugins.ohmyzsh-ssh-agent]
github = "ohmyzsh/ohmyzsh"
use = ["plugins/ssh-agent/ssh-agent.plugin.zsh"]
apply = ["defer"]

SSH_AGENT_PLUGIN

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

    # fzf integration（跨平台：优先 fzf --zsh，回退到 brew 路径或 ~/.fzf.zsh）
    cat >> "$plugins_toml" << 'FZF_PLUGIN'
[plugins.fzf]
inline = '''
if [[ -f "$HOME/.fzf.zsh" ]]; then
  source "$HOME/.fzf.zsh"
elif (( $+commands[fzf] )); then
  if fzf --zsh &>/dev/null; then
    source <(fzf --zsh)
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
        # 清理旧备份（跨平台：不使用 xargs -r）
        local old_backups
        old_backups=$(ls -t "${zshrc}".bak.* 2>/dev/null | tail -n +4)
        if [[ -n "$old_backups" ]]; then
            echo "$old_backups" | while read -r f; do rm -f "$f"; done
        fi
    fi

    # 生成管理块标记
    local MARKER_START="# >>> one-click-dev-env >>>"
    local MARKER_END="# <<< one-click-dev-env <<<"

    # 移除旧的管理块
    if [[ -f "$zshrc" ]]; then
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip
        ' "$zshrc" > "${zshrc}.tmp" && mv "${zshrc}.tmp" "$zshrc"
    fi

    # 检测 .zshrc 中是否已有 Homebrew shellenv（在管理块之外）
    local has_brew_outside=false
    if [[ -f "$zshrc" ]] && grep -q 'brew shellenv' "$zshrc" 2>/dev/null; then
        has_brew_outside=true
        info "检测到 .zshrc 中已有 Homebrew shellenv 配置（管理块外），跳过重复添加"
    fi
    # 也检测 .zprofile（macOS Homebrew 安装器默认写入位置）
    if [[ -f "$HOME/.zprofile" ]] && grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
        has_brew_outside=true
        info "检测到 .zprofile 中已有 Homebrew shellenv 配置，跳过重复添加"
    fi

    if [[ "$SELECTED_PLUGIN_MGR" == "sheldon" ]]; then
        # ── Sheldon 模式 ──

        # 清理 oh-my-zsh 模板行（避免 ohmyzsh 与 sheldon 双重加载）
        if [[ -f "$zshrc" ]] && grep -q 'oh-my-zsh' "$zshrc" 2>/dev/null; then
            warn "切换到 Sheldon 模式：将清理 .zshrc 中的 oh-my-zsh 相关配置"
            warn "  (plugins=(...), source oh-my-zsh.sh, eza zstyle 等)"
            warn "  原文件已备份为 ${zshrc}.bak.*"
            # 允许行首有可选空格（兼容不同缩进风格）
            sed_inplace '/^[[:space:]]*export ZSH=.*\.oh-my-zsh/d' "$zshrc"
            sed_inplace '/^[[:space:]]*ZSH_THEME=/d' "$zshrc"
            remove_omz_plugins_block "$zshrc"
            sed_inplace '/^[[:space:]]*source.*oh-my-zsh\.sh/d' "$zshrc"
            sed_inplace "/^[[:space:]]*zstyle ':omz:plugins:eza'/d" "$zshrc"
            sed_inplace '/^[[:space:]]*# ── eza 插件配置/d' "$zshrc"
            sed_inplace '/^[[:space:]]*fpath.*zsh-completions/d' "$zshrc"
            sed_inplace '/^[[:space:]]*# ── zsh-completions fpath/d' "$zshrc"
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

            # Homebrew shellenv（如果外部没有配置，则添加）
            if [[ "$has_brew_outside" == false ]]; then
                cat << 'BREW_BLOCK'
# ── Homebrew ──
# Homebrew 路径：macOS Apple Silicon /opt/homebrew，Intel /usr/local，Linux /home/linuxbrew
if [[ -f "/opt/homebrew/bin/brew" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif [[ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

BREW_BLOCK
            fi

            cat << 'ENV_BLOCK'
# ── PATH ──
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

        # 动态构建 plugins 列表
        local omz_plugins="git sudo ssh-agent"
        # command-not-found 仅在 Linux 上可用（依赖 apt 的 command-not-found 处理器）
        if [[ "$IS_LINUX" == true ]]; then
            omz_plugins+=" command-not-found"
        fi
        omz_plugins+=" eza fzf-tab zsh-autosuggestions fast-syntax-highlighting"
        if command_exists docker; then
            omz_plugins+=" docker docker-compose"
        fi
        local plugins_line="plugins=(${omz_plugins})"
        info "Oh My Zsh 插件列表: ${omz_plugins}"

        # 确保 oh-my-zsh 基础模板存在（含 .zshrc 不存在的全新系统）
        if ! [[ -f "$zshrc" ]] || ! grep -q 'source.*oh-my-zsh\.sh' "$zshrc"; then
            info "检测到 .zshrc 缺少 oh-my-zsh 模板，正在补充..."
            local omz_template
            omz_template=$(cat << 'OMZ_TPL'

# ── Oh My Zsh 基础配置（由 setup-dev-env-brew.sh 自动生成）──
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
__PLUGINS_PLACEHOLDER__

# ── zsh-completions fpath（必须在 compinit / source oh-my-zsh.sh 之前）──
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

# ── eza 插件配置（需在 source oh-my-zsh.sh 之前）──
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'icons' yes

source $ZSH/oh-my-zsh.sh
OMZ_TPL
)
            omz_template="${omz_template/__PLUGINS_PLACEHOLDER__/$plugins_line}"
            if [[ -f "$zshrc" ]]; then
                # 追加到文件末尾（而非前置），保留用户已有配置的加载顺序
                # （如 OPENSPEC fpath、conda init 等不会被重排）
                info "将 oh-my-zsh 配置追加到 .zshrc 末尾"
                printf '%s\n' "$omz_template" >> "$zshrc"
            else
                printf '%s\n' "$omz_template" > "$zshrc"
            fi
        fi
        if [[ -f "$zshrc" ]] && grep -q "^ZSH_THEME=" "$zshrc"; then
            sed_inplace 's/^ZSH_THEME=.*/ZSH_THEME=""/' "$zshrc"
        fi

        # 更新 plugins 列表
        if [[ -f "$zshrc" ]]; then
            update_omz_plugins_block "$zshrc" "$plugins_line"
        fi

        # 清理旧的 pre-source 配置（幂等性）
        if [[ -f "$zshrc" ]]; then
            sed_inplace "/^zstyle ':omz:plugins:eza'/d" "$zshrc"
            sed_inplace '/^# ── eza 插件配置/d' "$zshrc"
            sed_inplace '/^fpath.*zsh-completions/d' "$zshrc"
            sed_inplace '/^# ── zsh-completions fpath/d' "$zshrc"
        fi
        # 在 source $ZSH/oh-my-zsh.sh 之前插入 pre-source 配置
        local pre_source_config
        pre_source_config="$(cat <<'EOF'
# ── zsh-completions fpath（必须在 compinit / source oh-my-zsh.sh 之前）──
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src

# ── eza 插件配置（需在 source oh-my-zsh.sh 之前）──
zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'icons' yes
EOF
)"
        if [[ -f "$zshrc" ]]; then
            insert_before_pattern "$zshrc" 'oh-my-zsh.sh' "$pre_source_config"
        fi

        # 追加配置块
        {
            echo ""
            echo "# >>> one-click-dev-env >>>"
            echo ""

            # Homebrew shellenv
            if [[ "$has_brew_outside" == false ]]; then
                cat << 'BREW_BLOCK2'
# ── Homebrew ──
if [[ -f "/opt/homebrew/bin/brew" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif [[ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

BREW_BLOCK2
            fi

            cat << 'ENV_BLOCK1'
# ── PATH ──
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
  if fzf --zsh &>/dev/null; then
    source <(fzf --zsh)
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
zstyle ':fzf-tab:*' fzf-min-height 15
zstyle ':fzf-tab:*' fzf-bindings 'ctrl-/:toggle-preview'

# 通用预览（默认隐藏）
zstyle ':fzf-tab:complete:*:*' fzf-preview 'if [[ -d $realpath ]]; then eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath; elif [[ -f $realpath ]]; then bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -100 $realpath; elif [[ -n $desc ]]; then echo -E $desc; fi'
zstyle ':fzf-tab:complete:*:*' fzf-flags --preview-window=hidden,wrap

# 白名单命令覆盖
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi|ls|eza|exa|ll|la|tree|cat|less|more|head|tail|bat|vim|nvim|nano|code|view|cp|mv|rm|chmod|chown|source|\.|file|diff|stat):*' fzf-preview '[[ -d $realpath ]] && { eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath; } || { [[ -f $realpath ]] && { bat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null || head -100 $realpath; }; }'
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi|ls|eza|exa|ll|la|tree|cat|less|more|head|tail|bat|vim|nvim|nano|code|view|cp|mv|rm|chmod|chown|source|\.|file|diff|stat):*' fzf-flags --preview-window=wrap

# 特定命令预览
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps -p $word -o pid,user,%cpu,%mem,etime,command 2>/dev/null | tail -n +2'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-flags --preview-window=wrap
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word 2>/dev/null'
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-flags --preview-window=wrap
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-preview 'echo ${(P)word}'
zstyle ':fzf-tab:complete:(-command-|-parameter-|-brace-parameter-|export|unset|expand):*' fzf-flags --preview-window=wrap

ENV_BLOCK2

            case "$SELECTED_THEME" in
                pure)
                    echo ""
                    cat << 'PURE_BLOCK'
# ── Pure Theme ──
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

    # 检测潜在的重复配置并警告
    if [[ -f "$zshrc" ]]; then
        local dup_count
        dup_count=$(grep -c 'eval.*starship init' "$zshrc" 2>/dev/null | tr -dc '0-9')
        dup_count=${dup_count:-0}
        if [[ "$dup_count" -gt 1 ]]; then
            warn "检测到 .zshrc 中 starship init 出现 ${dup_count} 次，建议手动检查是否有重复配置"
        fi
        dup_count=$(grep -c 'eval.*sheldon source' "$zshrc" 2>/dev/null | tr -dc '0-9')
        dup_count=${dup_count:-0}
        if [[ "$dup_count" -gt 1 ]]; then
            warn "检测到 .zshrc 中 sheldon source 出现 ${dup_count} 次，建议手动检查是否有重复配置"
        fi
        dup_count=$(grep -c 'brew shellenv' "$zshrc" 2>/dev/null | tr -dc '0-9')
        dup_count=${dup_count:-0}
        if [[ "$dup_count" -gt 1 ]]; then
            warn "检测到 .zshrc 中 brew shellenv 出现 ${dup_count} 次，建议手动检查是否有重复配置"
        fi
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
    if brew ls --versions fzf &>/dev/null; then
        brew uninstall fzf 2>&1 | tee -a "$LOG_FILE"
        rm -f "$HOME/.fzf.zsh" "$HOME/.fzf.bash"
        success "fzf 已卸载 (brew)"
    elif [[ -d "$HOME/.fzf" ]]; then
        rm -rf "$HOME/.fzf"
        rm -f "$HOME/.fzf.zsh" "$HOME/.fzf.bash"
        success "fzf 已卸载 (git clone)"
    elif command_exists fzf; then
        rm -f "$(which fzf)" 2>/dev/null || true
        success "fzf 已卸载"
    else
        info "fzf 未安装，跳过"
    fi
}

uninstall_zoxide() {
    header "卸载 zoxide"
    if brew ls --versions zoxide &>/dev/null; then
        brew uninstall zoxide 2>&1 | tee -a "$LOG_FILE"
        rm -rf "$HOME/.local/share/zoxide"
        success "zoxide 已卸载 (brew)"
    elif command_exists zoxide || [[ -f "$HOME/.local/bin/zoxide" ]]; then
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

uninstall_starship_theme() {
    header "卸载 Starship"
    if brew ls --versions starship &>/dev/null; then
        brew uninstall starship 2>&1 | tee -a "$LOG_FILE"
        rm -f "$HOME/.config/starship.toml"
        success "Starship 已卸载 (brew)"
    elif command_exists starship || [[ -f "$HOME/.local/bin/starship" ]]; then
        rm -f "$HOME/.local/bin/starship"
        rm -f "$HOME/.config/starship.toml"
        success "Starship 已卸载"
    else
        info "Starship 未安装，跳过"
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
    if brew ls --versions yazi &>/dev/null; then
        brew uninstall yazi 2>&1 | tee -a "$LOG_FILE"
        success "yazi 已卸载 (brew)"
    elif command_exists yazi; then
        source_cargo_env
        cargo uninstall yazi-fm yazi-cli yazi-build 2>/dev/null || true
        success "yazi 已卸载 (cargo)"
    else
        info "yazi 未安装，跳过"
    fi
}

uninstall_eza() {
    header "卸载 eza"
    if brew ls --versions eza &>/dev/null; then
        brew uninstall eza 2>&1 | tee -a "$LOG_FILE"
        success "eza 已卸载 (brew)"
    elif command_exists eza; then
        source_cargo_env
        cargo uninstall eza 2>/dev/null || true
        success "eza 已卸载 (cargo)"
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
    if brew ls --versions sheldon &>/dev/null; then
        brew uninstall sheldon 2>&1 | tee -a "$LOG_FILE"
        rm -rf "$HOME/.config/sheldon" "$HOME/.local/share/sheldon"
        success "Sheldon 已卸载 (brew)"
    elif command_exists sheldon || [[ -f "$HOME/.local/bin/sheldon" ]]; then
        rm -f "$HOME/.local/bin/sheldon"
        rm -rf "$HOME/.config/sheldon" "$HOME/.local/share/sheldon"
        success "Sheldon 已卸载"
    else
        info "Sheldon 未安装，跳过"
    fi
}

uninstall_plugin_mgr() {
    uninstall_sheldon
    uninstall_ohmyzsh
}

uninstall_zsh() {
    header "恢复默认 Shell 为 Bash"
    if [[ "$SHELL" == *"zsh"* ]]; then
        if [[ "$IS_MACOS" == true ]]; then
            chsh -s /bin/bash 2>/dev/null || true
        else
            chsh -s "$(which bash)" 2>/dev/null || true
        fi
        success "默认 Shell 已切换回 Bash（下次登录生效）"
    else
        info "当前默认 Shell 已是 Bash，跳过"
    fi
}

uninstall_brew_deps() {
    header "卸载基础依赖包"
    info "跳过基础依赖卸载（避免影响系统其他程序和 Homebrew 依赖关系）"
}

remove_zshrc_config() {
    header "清理 .zshrc 配置"
    local zshrc="$HOME/.zshrc"
    local MARKER_START="# >>> one-click-dev-env >>>"
    local MARKER_END="# <<< one-click-dev-env <<<"
    if [[ -f "$zshrc" ]]; then
        # 移除管理块
        awk -v start="$MARKER_START" -v end="$MARKER_END" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip
        ' "$zshrc" > "${zshrc}.tmp" && mv "${zshrc}.tmp" "$zshrc"
        # 清理 oh-my-zsh 相关配置
        sed_inplace '/^export ZSH=.*\.oh-my-zsh/d' "$zshrc"
        sed_inplace '/^ZSH_THEME=/d' "$zshrc"
        remove_omz_plugins_block "$zshrc"
        sed_inplace '/^source.*oh-my-zsh\.sh/d' "$zshrc"
        # 清理 eza / zsh-completions 相关 pre-source 配置
        sed_inplace "/^zstyle ':omz:plugins:eza'/d" "$zshrc"
        sed_inplace "/^# ── eza 插件配置/d" "$zshrc"
        sed_inplace '/^fpath.*zsh-completions/d' "$zshrc"
        sed_inplace '/^# ── zsh-completions fpath/d' "$zshrc"
        success ".zshrc 中的 one-click-dev-env 配置已移除"
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
    echo "  • eza + yazi (Homebrew):  ~1 分钟"
    echo "  • Volta + Node/npm/pnpm:  ~2 分钟"
    echo "  • uv + Python:  ~2 分钟"
    echo "  • 其他:  ~1 分钟"
    echo -e "  ${BOLD}总计约 8-15 分钟${NC}（取决于网络和机器性能）"
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
    echo -e "     ${YELLOW}注意：${NC}${BOLD}无需${NC}${YELLOW}安装任何特殊字体${NC}"
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

    if [[ "$SELECTED_THEME" == "starship" ]]; then
        echo ""
        select_catppuccin_flavor
    fi
}

run_install_all() {
    header "🚀 开始一键安装所有开发环境组件"

    detect_platform
    check_network
    ensure_homebrew
    detect_existing_setup

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

    # 组件过滤（不再需要 eza/yazi 的 rustup 自动依赖，因为用 brew 安装）
    local comps=",${SELECTED_COMPONENTS},"
    should_install() {
        [[ -z "$SELECTED_COMPONENTS" ]] && return 0
        [[ "$comps" == *",$1,"* ]] && return 0
        return 1
    }

    # 基础环境始终安装
    install_brew_deps
    install_zsh
    install_plugin_mgr
    install_theme
    install_zsh_autosuggestions
    install_fast_syntax_highlighting
    install_fzf
    install_fzf_tab
    install_zsh_completions

    # 可选组件
    should_install "zoxide" && install_zoxide
    should_install "rustup" && install_rustup
    should_install "eza" && install_eza
    should_install "yazi" && install_yazi
    should_install "volta" && install_volta
    should_install "uv" && install_uv
    should_install "proto" && install_proto

    # 生成 CLI 工具的补全文件
    generate_completions

    # 清除旧的 zcompdump 缓存
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
    echo "  • fzf (模糊搜索)"
    echo "  • fzf-tab"
    echo "  • zsh-completions"

    echo -e "\n${BOLD}可选组件配置结果：${NC}"
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
        echo -e "  ${YELLOW}字体安装方式：${NC}"
        echo -e "    • ${BOLD}macOS${NC}: ${CYAN}brew install --cask font-meslo-lg-nerd-font${NC}"
        echo -e "    • ${BOLD}Linux${NC}: 下载并移动字体至 ${CYAN}~/.local/share/fonts${NC}，然后 ${CYAN}fc-cache -f -v${NC}"
        echo ""
    fi

    info "运行 ${BOLD}exec zsh${NC} 或重新登录以启用新配置"

    # 自动清理
    if [[ "$AUTO_CLEANUP" == "1" ]]; then
        local script_path
        script_path=$(portable_readlink "$0")
        if [[ -f "$script_path" ]]; then
            info "清理安装脚本: $script_path"
            rm -f "$script_path"
        fi
    fi
}

# ─── 一键卸载 ─────────────────────────────────────────────────────────────────

run_uninstall_all() {
    header "🗑️  开始一键卸载所有开发环境组件"

    detect_platform

    warn "即将卸载所有开发环境组件，此操作不可逆！"
    echo ""
    read -rp "确认卸载全部组件？(输入 yes 继续): " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "已取消卸载"
        return
    fi
    echo ""

    remove_zshrc_config
    uninstall_proto
    uninstall_uv
    uninstall_volta
    uninstall_yazi
    uninstall_eza
    uninstall_zoxide
    uninstall_fast_syntax_highlighting
    uninstall_zsh_completions
    uninstall_fzf_tab
    uninstall_fzf
    uninstall_zsh_autosuggestions
    uninstall_theme
    uninstall_rustup
    uninstall_plugin_mgr
    uninstall_zsh
    uninstall_brew_deps

    header "✅ 卸载完成"
}

# ─── 交互模式 ─────────────────────────────────────────────────────────────────

show_status_indicator() {
    local comp_id="$1"
    case "$comp_id" in
        brew-deps)    brew ls --versions bat &>/dev/null && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}" ;;
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
            if command_exists starship; then
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
    local action="$1"
    local action_label
    if [[ "$action" == "install" ]]; then
        action_label="安装"
    else
        action_label="卸载"
    fi

    local -a protected_ids=("brew-deps" "zsh" "plugin-mgr" "theme" "zsh-autosuggestions" "fast-syntax-highlighting" "fzf-tab" "zsh-completions")

    _is_protected() {
        local id="$1"
        for pid in "${protected_ids[@]}"; do
            [[ "$id" == "$pid" ]] && return 0
        done
        return 1
    }

    local -a names=() descs=() statuses=() checked=() locked=()

    for i in "${!COMPONENTS[@]}"; do
        local comp="${COMPONENTS[$i]}"
        local id="${comp%%:*}"

        if [[ "$action" == "uninstall" ]] && _is_protected "$id"; then
            continue
        fi

        names+=("$id")
        descs+=("${comp##*:}")
        statuses+=("$(show_status_indicator "$id")")

        if [[ "$action" == "install" ]] && _is_protected "$id"; then
            checked+=("true")
            locked+=("true")
        else
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

    _draw_menu() {
        for i in "${!descs[@]}"; do
            local pointer="  "
            [[ $i -eq $cursor ]] && pointer="${CYAN}▸${NC} "

            local checkbox
            if [[ "${locked[$i]}" == "true" ]]; then
                checkbox="${GREEN}[✔]${NC} 🔒"
            elif [[ "${checked[$i]}" == "true" ]]; then
                checkbox="${GREEN}[✔]${NC}   "
            else
                checkbox="[ ]   "
            fi

            printf "\r  %b%b %-36s %b ${BOLD}[%s]${NC}\n" \
                "$pointer" "$checkbox" "${descs[$i]}" "${statuses[$i]}" "${names[$i]}"
        done
        echo -e "  ${BOLD}────────────────────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}↑/↓${NC} 移动  ${CYAN}空格${NC} 选中/取消  ${CYAN}a${NC} 全选  ${CYAN}n${NC} 全不选  ${CYAN}回车${NC} 确认  ${CYAN}q${NC} 取消"
    }

    echo -e "\n${BOLD}请选择要${action_label}的组件：${NC}"
    echo -e "  ${GREEN}●${NC} = 已安装    ${RED}○${NC} = 未安装"
    if [[ "$action" == "uninstall" ]]; then
        echo -e "  ${YELLOW}提示：基础组件仅可通过一键卸载移除${NC}"
    fi
    echo ""

    tput civis 2>/dev/null
    _draw_menu

    while true; do
        local key
        IFS= read -rsn1 key

        case "$key" in
            $'\x1b')
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A') (( cursor > 0 )) && (( cursor-- )) ;;
                    '[B') (( cursor < total - 1 )) && (( cursor++ )) ;;
                esac
                ;;
            ' ')
                if [[ "${locked[$cursor]}" != "true" ]]; then
                    if [[ "${checked[$cursor]}" == "true" ]]; then
                        checked[$cursor]="false"
                    else
                        checked[$cursor]="true"
                    fi
                fi
                ;;
            '')
                break
                ;;
            'a'|'A')
                for i in "${!checked[@]}"; do
                    [[ "${locked[$i]}" != "true" ]] && checked[$i]="true"
                done
                ;;
            'n'|'N')
                for i in "${!checked[@]}"; do
                    [[ "${locked[$i]}" != "true" ]] && checked[$i]="false"
                done
                ;;
            'q'|'Q')
                tput cnorm 2>/dev/null
                info "已取消"
                return
                ;;
        esac

        printf "\033[%dA\r" "$((total + 2))"
        _draw_menu
    done

    tput cnorm 2>/dev/null
    echo ""

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
        detect_platform
        ensure_homebrew
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
        configure_zshrc
    else
        detect_platform
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
    echo -e "${BOLD}${CYAN}  跨平台开发环境管理工具 (Homebrew)${NC}"
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
                echo "跨平台开发环境管理工具 (Homebrew 版)"
                echo ""
                echo "用法: $0 [--install | --uninstall] [--plugin-mgr sheldon|ohmyzsh] [--theme starship|p10k|pure] [--components comp1 ...] [--help]"
                echo ""
                echo "选项:"
                echo "  --install              一键安装所有组件"
                echo "  --uninstall            一键卸载所有组件"
                echo "  --plugin-mgr sheldon|ohmyzsh"
                echo "                         指定插件管理器（默认: sheldon）"
                echo "  --theme starship|p10k|pure"
                echo "                         指定终端主题（默认: starship）"
                echo "  --flavor mocha|macchiato|frappe|latte"
                echo "                         指定 Catppuccin 风味（默认: mocha）"
                echo "  --components comp1 [comp2 ...]"
                echo "                         指定要安装的可选组件，不传则安装全部"
                echo "                         可选值: fzf, zoxide, rustup, eza, yazi, volta, uv, proto"
                echo "  --auto-cleanup         安装完成后自动删除本脚本"
                echo "  --help, -h             显示帮助信息"
                echo "  （无参数）              进入交互界面"
                echo ""
                echo "支持平台: macOS (Homebrew), Linux (Linuxbrew)"
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
