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
- 终端 zsh + powerlevel10k / pure + zsh-autosuggestions + zsh-syntax-highlighting
- 字体 MesloLGS NF
- 工具 Rust, Volta（包含 node、npm、pnpm 的 latest 版本）, uv（python 的 3.14 版本）, proto, eza, yazi

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
6. 选择终端默认主题 (Powerlevel10k 或 Pure)
7. 安装 MesloLGS Nerd Font 字体
8. 选择要附加安装的开发工具 (Rust, Volta, uv, 等)
9. 在子系统内自动完成环境初始化

### 独立使用 Linux 脚本 (本地执行)

在已有的 Ubuntu / Debian 系统中，进入脚本所在目录：

```bash
# 一键安装所有可选组件（默认插件管理器 Sheldon、主题 p10k）
bash setup-dev-env.sh --install

# 使用 Oh My Zsh 插件管理器并指定主题
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme pure

# 指定主题并仅安装部分组件
bash setup-dev-env.sh --install --theme pure --components "rustup,volta,uv"

# 一键卸载所有组件
bash setup-dev-env.sh --uninstall

# 交互模式（选择安装/卸载）
bash setup-dev-env.sh
```

## 安装的组件

| 组件                    | 用途                          | 管理工具       |
| ----------------------- | ----------------------------- | -------------- |
| Zsh                     | Shell 环境                    | apt-get        |
| Sheldon（默认）           | 插件管理器                      | 预编译二进制   |
| Oh My Zsh（可选）         | 插件管理器                      | install script |
| Powerlevel10k           | 终端主题 (推荐，功能丰富)     | sheldon / git  |
| Pure                    | 终端主题 (极简，无需特殊字体) | sheldon / git  |
| zsh-autosuggestions     | 命令补全建议                  | sheldon / git  |
| zsh-syntax-highlighting | 语法高亮                      | sheldon / git  |
| eza                     | 现代 `ls` 替代                | cargo          |
| yazi                    | 终端文件管理器                | cargo          |
| Rust (rustup)           | Rust 开发环境                 | rustup         |
| Volta                   | Node/npm/pnpm 版本管理        | volta          |
| uv                      | Python 版本管理               | uv             |
| proto                   | 多语言版本管理                | proto          |

## 安装后

如果使用了 Powerlevel10k 主题，进入 WSL 子系统后，通常会提示配置向导。如果没有，可手动运行：

```bash
p10k configure
```

对于 Pure 主题，无需额外配置。如果发现终端图标（如在使用 eza 时）显示为乱码，说明宿主机缺少 **MesloLGS Nerd Font** 字体。请参照下方的常用命令在日常使用的客户端操作系统中安装**并配置终端字体（如 Windows Terminal、iTerm2、Wezterm 等）**：

- **Windows / WSL 宿主机（管理员 PowerShell）**：
  `iex (iwr -useb https://raw.githubusercontent.com/romkatv/powerlevel10k-media/master/fonts.ps1)`
- **macOS（推荐使用 Homebrew）**：
  `brew tap homebrew/cask-fonts && brew install --cask font-meslo-lg-nerd-font`

## 注意事项

- `setup-wsl.ps1` 需要 **管理员权限** 运行
- 启用 WSL2 功能后可能需要 **重启计算机**
- 分发版使用 `--web-download` 模式下载，需要网络连接
- **网络要求**：脚本在安装过程中不会自动配置任何国内镜像源（如 apt, npm, rustup 等），请确保您的网络环境能够顺畅访问外网（如 GitHub 等），否则可能导致下载极其缓慢或安装失败
- eza 和 yazi 通过 cargo 编译安装，首次安装耗时较长
