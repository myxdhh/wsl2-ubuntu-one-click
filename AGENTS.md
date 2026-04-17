# AGENTS.md

本文件为 AI 编码助手提供项目上下文与开发规范，帮助 Agent 理解项目结构、修改规则和注意事项。

## 项目概述

**WSL2 一键安装与开发环境配置工具**——面向前端开发者的自动化脚本集合，用于在 Windows 上一键部署 WSL2 子系统并配置完整的 Linux 开发环境。

项目由两个核心脚本组成，可独立使用也可协同工作：

| 文件 | 语言 | 运行环境 | 权限要求 |
|---|---|---|---|
| `setup-wsl.ps1` | PowerShell | Windows 10/11 宿主机 | 管理员权限 |
| `setup-dev-env.sh` | Bash | Ubuntu / Debian（含 WSL2） | sudoers 免密 |

## 仓库结构

```
wsl2-ubuntu-one-click/
├── README.md            # 项目文档（中文）
├── AGENTS.md            # AI Agent 开发指南（本文件）
├── setup-wsl.ps1        # Windows 宿主机脚本 — 编排 WSL2 完整安装流程
└── setup-dev-env.sh     # Linux 环境脚本 — 独立的开发工具安装/卸载管理器
```

项目非常精简，**没有依赖管理文件**（无 package.json、requirements.txt 等），也**没有测试框架**。两个脚本即是全部源码。

## 架构与执行流程

### setup-wsl.ps1（Windows 端编排器）

该脚本是完整安装流程的入口，按步骤顺序执行：

```
步骤 0: 前置条件检查（Windows 版本、VT-x/AMD-V、WSL 功能、内核更新）
步骤 1: 选择并安装 WSL2 分发版（Ubuntu-24.04/22.04/20.04/Debian）
步骤 2: 配置 .wslconfig（网络模式、DNS、内存回收等，合并已有配置）
步骤 3: 创建 Linux 用户（含 sudo 免密、wsl.conf 默认用户配置）
步骤 4a: 选择插件管理器（Sheldon 或 Oh My Zsh，默认 Sheldon）
步骤 4b: 选择终端主题（Powerlevel10k 或 Pure）
步骤 5: 安装 MesloLGS Nerd Font 字体并配置 Windows Terminal
步骤 6: 选择要安装的开发工具组件
步骤 7: 将 setup-dev-env.sh 复制到子系统内并执行
```

**关键设计**：
- 支持 `irm ... | iex` 远程一键执行；本地找不到 `setup-dev-env.sh` 时自动从 `$Global:RemoteDevEnvScriptUrl` 下载
- 支持 `--font-only` 模式单独安装字体
- `.wslconfig` 采用**合并策略**（解析现有 INI → 覆盖指定键 → 重新生成），不会丢失用户自定义项
- 密码处理使用 `SecureString` + `ZeroFreeBSTR`，密码变量在 `finally` 块中清零

### setup-dev-env.sh（Linux 端组件管理器）

该脚本是独立可用的开发环境管理器，支持三种运行模式：

| 模式 | 命令 | 特点 |
|---|---|---|
| 一键安装 | `--install` | 非交互，适合自动化 |
| 一键卸载 | `--uninstall` | 非交互，反序卸载 |
| 交互模式 | （无参数） | 带状态指示器的菜单 |

**组件依赖链**：
```
基础组件（始终安装）: apt-deps → zsh → plugin-mgr (sheldon/ohmyzsh) → theme
可选组件: rustup → { eza, yazi }（cargo 编译）
独立可选: zsh-autosuggestions, zsh-syntax-highlighting, volta, uv, proto
```

> 注意：选择 eza 或 yazi 时会自动添加 rustup 依赖。

**插件管理器架构**：
- `SELECTED_PLUGIN_MGR` 变量控制当前模式（`sheldon` 或 `ohmyzsh`）
- 自动检测：已安装 Oh My Zsh 且未安装 Sheldon → 默认 ohmyzsh；否则 → 默认 sheldon
- CLI 参数：`--plugin-mgr sheldon|ohmyzsh`
- `install_plugin_mgr()` / `uninstall_plugin_mgr()` 为 dispatch 函数，委派到对应实现

**Sheldon 模式特殊逻辑**：
- 插件（zsh-autosuggestions, zsh-syntax-highlighting）和主题（p10k, pure）的 install 函数在 Sheldon 模式下为空操作
- `configure_sheldon_plugins()` 生成 `~/.config/sheldon/plugins.toml`，并执行 `sheldon lock --update` 下载所有插件
- `.zshrc` 使用 `eval "$(sheldon source)"` 代替 `source $ZSH/oh-my-zsh.sh`
- eza aliases 通过 inline plugin 在 `plugins.toml` 中定义

**`.zshrc` 配置管理**：
- 使用 `# >>> one-click-dev-env >>>` / `# <<< one-click-dev-env <<<` 标记块管理自动生成的配置
- 标记块外的用户自定义配置不会被覆盖
- Oh My Zsh 模式：eza 的 `zstyle` 配置插入在 `source oh-my-zsh.sh` **之前**（这是 oh-my-zsh 插件系统的要求）
- Sheldon 模式：无需 oh-my-zsh 相关配置，所有插件通过 `plugins.toml` 管理
- 每次配置前自动备份 `.zshrc`，仅保留最近 3 个备份

## 开发规范

### 编码风格

**PowerShell (`setup-wsl.ps1`)**：
- 函数命名使用 `PascalCase`（如 `Step-Prerequisites`、`Test-InstanceName`）
- 步骤函数以 `Step-` 为前缀
- 用户输入校验函数以 `Test-` 为前缀
- 使用 `Write-Info`、`Write-Ok`、`Write-Warn`、`Write-Err`、`Write-Header` 输出彩色日志
- 错误处理使用 `$ErrorActionPreference = "Stop"` + `try/catch/finally`

**Bash (`setup-dev-env.sh`)**：
- 使用 `set -uo pipefail`（注意：**不使用** `set -e`，改用显式错误处理）
- 函数命名使用 `snake_case`（如 `install_rustup`、`check_network`）
- 安装函数统一命名为 `install_<组件id>`，卸载函数为 `uninstall_<组件id>`
- 日志函数：`info()`、`success()`、`warn()`、`error()`、`header()`
- 每个安装函数内部调用 `log_start` / `log_end` 记录日志到 `~/.setup-dev-env.log`
- 安装失败通过 `record_failure` 记录，最终在 `print_summary` 汇总输出
- 颜色输出仅在 `[[ -t 1 ]]`（stdout 是终端）时启用

### 添加新组件

添加一个新的可选开发工具需要修改**两个文件**中的多个位置：

**`setup-dev-env.sh` 中需要修改**：
1. `COMPONENTS` 数组 — 添加 `"<id>:<描述>"` 条目
2. 添加 `install_<id>()` 函数 — 遵循现有模式（header → log_start → 幂等检查 → 安装 → log_end）
3. 添加 `uninstall_<id>()` 函数
4. `configure_zshrc()` — 如需要，在标记块内添加 PATH/env 配置
5. 如有依赖关系，在 `run_install_all()` 的依赖处理逻辑中添加

**`setup-wsl.ps1` 中需要修改**：
1. `Step-SelectComponents` 的 `$components` 数组 — 添加对应条目

**`README.md` 中需要修改**：
1. "安装的组件" 表格 — 添加新组件说明

### 安装函数的标准模式

```bash
install_example() {
    header "安装 Example"
    log_start "example"

    if command_exists example; then
        success "Example 已安装: $(example --version)"
    else
        if ! <安装命令> 2>&1 | tee -a "$LOG_FILE"; then
            record_failure "example"
            return 1
        fi
        success "Example 安装完成"
    fi

    log_end "example" $?
}
```

关键要求：
- **幂等性**：先检查是否已安装，已安装则跳过
- **日志记录**：安装输出通过 `tee -a "$LOG_FILE"` 同时显示和记录
- **优雅降级**：安装失败调用 `record_failure` 并 `return 1`，不中断整体流程

## 安全注意事项

修改脚本时请特别注意以下安全敏感区域：

- **密码处理**（`Step-CreateUser`）：必须使用 `SecureString`，BSTR 指针必须在 `finally` 块中通过 `ZeroFreeBSTR` 释放，明文变量事后置 `$null` 并调用 GC
- **用户输入校验**：实例名（`Test-InstanceName`）和用户名（`Test-LinuxUsername`）均有正则校验，防止命令注入
- **chpasswd 管道传入**：密码通过管道传入 `chpasswd`，避免出现在命令行参数中
- **sudoers 文件权限**：必须设为 `0440`
- **远程脚本下载**：仅从 `$Global:RemoteDevEnvScriptUrl` 指定的固定地址下载

## 测试建议

项目没有自动化测试框架。修改后建议通过以下方式验证：

1. **语法检查**：
   - PowerShell: 在 PowerShell 中运行 `powershell -Command "& { Get-Content setup-wsl.ps1 | Out-Null }"` 或使用 PSScriptAnalyzer
   - Bash: `bash -n setup-dev-env.sh`（语法检查）和 `shellcheck setup-dev-env.sh`（静态分析）

2. **幂等性验证**：在已安装环境中重复执行脚本，确认不会产生副作用

3. **单组件测试**：使用交互模式单独安装/卸载特定组件

## 语言与本地化

- 项目面向中文用户，所有用户可见的提示信息、注释和文档均使用**中文**
- 代码中的变量名、函数名使用英文
- 新增的用户提示文本应保持中文
