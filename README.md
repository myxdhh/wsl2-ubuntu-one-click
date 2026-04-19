# WSL2 一键安装与开发环境配置（for Frontend）

每次想要新创建一个 linux 子系统的时候，又要从头安装环境实在是太麻烦了，整个脚本处理一下。

docker desktop 基本上都安装过了，就不写到脚本了。

> [!WARNING]
> **适用范围说明**
>
> - **`setup-wsl.ps1`**: 仅适用于 **Windows 10/11** 宿主机，且必须以 **管理员权限** 运行，用于自动部署和配置 WSL2 生态。
> - **`setup-dev-env.sh`**: 适用于基于 **Debian / Ubuntu** 的 Linux 环境（包括 WSL2 实例、物理机或云服务器），用于一键安装指定的开发工具包与终端环境。

一键完成 WSL2 安装、配置以及 Linux 开发环境搭建。

总览

- 子系统 Ubuntu-24.04
- 插件管理 [Sheldon](https://github.com/rossmacarthur/sheldon)（默认）或 Oh My Zsh（可选）
- 终端 zsh + [Starship](https://starship.rs/)（默认）/ powerlevel10k / pure + zsh-autosuggestions + fast-syntax-highlighting
- 字体 MesloLGS NF
- 工具 fzf, zoxide, Rust, Volta（包含 node、npm、pnpm 的 latest 版本）, uv（python 的 3.14 版本）, proto, eza, yazi

## 文件说明

| 文件               | 说明                                           |
| ------------------ | ---------------------------------------------- |
| `setup-wsl.ps1`    | Windows 宿主机脚本（PowerShell，需管理员权限） |
| `setup-dev-env.sh` | Linux 开发环境脚本（Bash，可独立使用）         |

## 快速开始

### 远程一键安装（推荐）

复制命令一键执行，无需手动下载脚本。

**1. WSL2 完整安装 (Windows 宿主机)**
以管理员身份打开 PowerShell，执行：

```powershell
irm https://raw.githubusercontent.com/myxdhh/wsl2-ubuntu-one-click/main/setup-wsl.ps1 | iex
```

**2. 仅安装或配置 Linux 开发环境 (独立使用)**
在已有的 Ubuntu / Debian 系统中：

```bash
# --auto-cleanup 参数表示在安装完毕后自动删除下载的脚本文件
bash -c "$(curl -fsSL https://raw.githubusercontent.com/myxdhh/wsl2-ubuntu-one-click/main/setup-dev-env.sh)" -- --install --auto-cleanup
```

---

### 本地执行命令

如果你已经将仓库克隆或将脚本下载到了本地：

**WSL2 完整安装**：
以管理员身份打开 PowerShell，进入本目录后执行：

```powershell
.\setup-wsl.ps1
```

你也可以单独使用该脚本为宿主机安装和配置 Nerd Font 字体：

```powershell
.\setup-wsl.ps1 --font-only
```

脚本将依次完成：

1. 检查并启用 WSL2 前置功能
2. 选择并安装分发版（Ubuntu-24.04 / 22.04 / 20.04 / Debian）-> 目前只验证过 Ubuntu-24.04
3. 配置 `.wslconfig`（网络镜像、内存回收、DNS 隧道等）
4. 创建默认用户并配置 sudo 免密
5. 选择插件管理器 (Sheldon 或 Oh My Zsh)
6. 选择终端主题 (Starship / Powerlevel10k / Pure)
7. 安装 MesloLGS Nerd Font 字体
8. 选择要附加安装的开发工具 (fzf, zoxide, Rust, Volta, uv 等)
9. 在子系统内自动完成环境初始化

### 独立使用 Linux 脚本 (本地执行)

在已有的 Ubuntu / Debian 系统中，进入脚本所在目录：

```bash
# 一键安装所有可选组件（默认插件管理器 Sheldon、主题 Starship）
bash setup-dev-env.sh --install

# 使用 Oh My Zsh 插件管理器并指定主题
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k

# 指定 Catppuccin 风味（同时影响 Starship 和 fzf 配色）
bash setup-dev-env.sh --install --theme starship --flavor latte

# 仅切换风味（Starship 已安装时不重复安装）
bash setup-dev-env.sh --install --theme starship --flavor macchiato

# 仅安装部分组件
bash setup-dev-env.sh --install --components rustup volta uv

# 一键卸载所有组件
bash setup-dev-env.sh --uninstall

# 交互模式（选择安装/卸载）
bash setup-dev-env.sh
```

`--components` 可选值：`fzf`, `zoxide`, `rustup`, `eza`, `yazi`, `volta`, `uv`, `proto`

`--flavor` 可选值：

| 风味 | 风格 | 适用场景 |
|---|---|---|
| `mocha` (默认) | 深色 | 最常用，经典款 |
| `macchiato` | 深色偏暖 | 偏好暖色调 |
| `frappe` | 中间色调 | 折中方案 |
| `latte` | 浅色 | 日间使用 |

## 安装的组件

| 组件                     | 用途                          | 管理工具       |
| ------------------------ | ----------------------------- | -------------- |
| Zsh                      | Shell 环境                    | apt-get        |
| Sheldon（默认）            | 插件管理器                    | 预编译二进制   |
| Oh My Zsh（可选）          | 插件管理器                    | install script |
| Starship（默认）           | 终端主题 (Rust 编写、极速渲染) | 预编译二进制   |
| Powerlevel10k            | 终端主题 (功能丰富)          | sheldon / git  |
| Pure                     | 终端主题 (极简、无需特殊字体) | sheldon / git  |
| zsh-autosuggestions      | 命令补全建议                  | sheldon / git  |
| fast-syntax-highlighting | 语法高亮 (极速、Chroma 引擎) | sheldon / git  |
| fzf-tab                  | Tab 补全 fzf 界面             | sheldon / git  |
| zsh-completions          | 300+ 命令补全定义          | sheldon / git  |
| fzf                      | 模糊搜索                      | git clone      |
| zoxide                   | 智能 cd (覆盖原生 cd)         | install script |
| eza                      | 现代 `ls` 替代                | cargo          |
| yazi                     | 终端文件管理器                | cargo          |
| Rust (rustup)            | Rust 开发环境                 | rustup         |
| Volta                    | Node/npm/pnpm 版本管理        | volta          |
| uv                       | Python 版本管理               | uv             |
| proto                    | 多语言版本管理                | proto          |

## 安装后

- **Starship 主题**：已自动配置 catppuccin-powerline 预设，配置文件位于 `~/.config/starship.toml`。支持 4 种 Catppuccin 风味（Mocha/Macchiato/Frappé/Latte），切换时会同步更新 fzf 配色
- **Powerlevel10k 主题**：进入 WSL 子系统后，通常会提示配置向导。如果没有，可手动运行：

```bash
p10k configure
```

- **Pure 主题**：无需额外配置

如果终端图标（如使用 eza 时）显示为乱码，说明宿主机缺少 **Nerd Font** 字体。请在终端软件（Windows Terminal、iTerm2 等）中配置字体为 **MesloLGS NF**：

- **Windows / WSL 宿主机（管理员 PowerShell）**：
  `iex (iwr -useb https://raw.githubusercontent.com/romkatv/powerlevel10k-media/master/fonts.ps1)`
- **macOS（推荐使用 Homebrew）**：
  `brew tap homebrew/cask-fonts && brew install --cask font-meslo-lg-nerd-font`
## 添加命令补全

脚本已自动为 `rustup`、`cargo`、`volta`、`uv`、`proto` 生成 Zsh 补全文件。如需为其他工具添加补全：

**Sheldon 模式**（补全文件目录：`~/.zsh/completions`）：

```bash
# 文件名必须以 _ 开头
your-cli completions zsh > ~/.zsh/completions/_your-cli
# 重建补全缓存
exec zsh
```

**Oh My Zsh 模式**（补全文件目录：`~/.oh-my-zsh/completions`）：

```bash
mkdir -p ~/.oh-my-zsh/completions
your-cli completions zsh > ~/.oh-my-zsh/completions/_your-cli
omz reload
```

## 自定义 fzf-tab 预览

脚本已为**常用文件操作命令**（`cd`、`ls`、`cat`、`vim`、`cp`、`mv`、`rm` 等）配置了 Tab 补全预览：

| 候选项类型 | 预览内容 |
|---|---|
| 目录 | eza 树形结构（嵌套 2 层） |
| 文件 | bat 语法高亮 |

此外，`kill`（进程状态）、`systemctl`（服务状态）、环境变量（变量值）已有专属预览规则。

> [!TIP]
> 脚本中还提供了一条**注释掉的通用规则**（`*:*`），取消注释即可让所有命令的文件/目录补全都有预览，并为 flags/子命令显示 `$desc` 描述文本。代价是：纯子命令/flags 场景下预览面板仍会显示（内容为空），占用屏幕空间。

### 为特定命令添加更丰富的预览

对于支持 `cmd help subcommand` 的工具，可以添加特定规则，在预览窗口中显示完整的帮助信息：

```zsh
# rustup: 路径→目录/文件预览，子命令→完整帮助文本
zstyle ':fzf-tab:complete:rustup:*' fzf-preview \
  'if [[ -d $realpath ]]; then
    eza --tree --level=2 --icons --color=always --group-directories-first $realpath 2>/dev/null
  elif [[ -f $realpath ]]; then
    batcat --color=always --style=numbers --line-range=:200 $realpath 2>/dev/null
  else
    rustup help $word 2>/dev/null
  fi'
```

> [!TIP]
> **可用变量**：
> - `$realpath`：候选项的真实路径（文件/目录补全时有效）
> - `$word`：候选项的文本内容（如子命令名称）
> - `$desc`：补全函数对该候选项的描述
>
> **帮助命令格式**：
> - `cmd help subcommand`：rustup、cargo、docker、git 等 Go/Rust CLI 工具
> - `cmd subcommand --help`：npm、pnpm 等 Node.js 系工具，需调整命令格式

> [!IMPORTANT]
> **多级子命令的限制**：
> fzf-tab 的预览环境中**无法获取完整的命令链**。例如输入 `git remote <TAB>` 时，预览只知道当前候选词 `$word` 是 `add`，但**不知道前面是 `git remote`**，因此无法自动构造 `git remote help add` 或 `git help remote add` 这样的多级帮助命令。
>
> 对于一级子命令（如 `rustup <TAB>` → `rustup help install`），特定规则可以正常工作。
> 对于多级子命令，建议使用通用规则的 `$desc` 描述文本作为 fallback。

## 注意事项

- `setup-wsl.ps1` 需要 **管理员权限** 运行
- 启用 WSL2 功能后可能需要 **重启计算机**
- 分发版使用 `--web-download` 模式下载，需要网络连接
- **网络要求**：脚本在安装过程中不会自动配置任何国内镜像源（如 apt, npm, rustup 等），请确保您的网络环境能够顺畅访问外网（如 GitHub 等），否则可能导致下载极其缓慢或安装失败
- eza 和 yazi 通过 cargo 编译安装，首次安装耗时较长
- **TODO**: `Step-CreateUser` 中 `chpasswd` 的密码目前通过 `bash -c "echo '...' | chpasswd"` 传递，密码会短暂出现在进程参数列表中（`/proc/*/cmdline`）。尝试过 PowerShell stdin 管道方案，但因 WSL interop 层的编码/转义问题无法可靠工作，待后续改进

## 测试

项目提供 Dockerfile 用于在 Ubuntu 24.04 容器中测试 `setup-dev-env.sh`：

```bash
# 1. 构建测试镜像
docker build -t wsl-dev-test .

# 2. 进入容器交互测试
docker run -it --rm wsl-dev-test

# 容器内测试命令示例：

# 一键安装（默认 Sheldon + Starship）
bash setup-dev-env.sh --install

# 指定 Oh My Zsh + Powerlevel10k
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k

# 切换测试：从 Sheldon 切换到 Oh My Zsh（验证配置覆盖）
bash setup-dev-env.sh --install --plugin-mgr sheldon --theme starship
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k

# 仅安装部分组件
bash setup-dev-env.sh --install --components volta uv

# 交互模式
bash setup-dev-env.sh

# 一键卸载
bash setup-dev-env.sh --uninstall

# 语法检查
bash -n setup-dev-env.sh
```

```bash
# 3. 测试完毕后清理
docker rmi wsl-dev-test          # 删除镜像
docker builder prune -f          # 清理构建缓存
```
