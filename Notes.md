# 开发笔记

## PowerShell 调用原生命令的两个陷阱

### 陷阱 1: `try/catch` 无法捕获原生命令失败

PowerShell 的 `try/catch` 只能捕获 **.NET 异常**（如 `ConvertFrom-Json` 解析错误、`Get-Content` 文件不存在等）。

`wsl.exe`、`dism.exe`、`bcdedit` 等**原生可执行文件**失败时只设置 `$LASTEXITCODE`，不抛出异常，`catch` 块**永远不会执行**。

```powershell
# ❌ 错误：wsl 失败时 catch 不执行，脚本静默继续
try {
    & wsl --install -d Ubuntu
}
catch {
    Write-Error "安装失败: $_"   # 永远不会到这里
}

# ✅ 正确：显式检查退出码
& wsl --install -d Ubuntu
if ($LASTEXITCODE -ne 0) {
    Write-Error "安装失败 (退出码: $LASTEXITCODE)"
    exit 1
}
```

### 陷阱 2: 原生命令输出会污染函数返回值

PowerShell 函数的返回值 = **管道中所有未被消费的输出**，不仅仅是 `return` 的值。

如果函数内部调用了原生命令（如 `wsl`），其 stdout 输出会被收集为返回值的一部分，导致调用方拿到的不是预期的单一值，而是一个混合了命令输出和返回值的数组。

```powershell
# ❌ 错误：wsl 的输出会混入 $result
function Install-Distro {
    wsl --install -d Ubuntu      # stdout 输出变成返回值的一部分
    return "Ubuntu2404"           # 期望返回字符串
}
$result = Install-Distro
# $result = @("正在安装...", "已完成", "Ubuntu2404")  ← 数组！

# ✅ 正确：用 | Out-Host 将输出送到控制台，不进入管道
function Install-Distro {
    wsl --install -d Ubuntu | Out-Host   # 输出直接显示，不进管道
    return "Ubuntu2404"
}
$result = Install-Distro
# $result = "Ubuntu2404"  ← 纯字符串 ✓
```

**三种处理方式对比：**

| 写法 | 输出去向 | 是否污染返回值 | 用户可见 |
|------|---------|--------------|---------|
| `wsl ...` | 管道 → 函数返回值 | ✅ 会污染 | 仅赋值时不可见 |
| `wsl ... \| Out-Host` | 直接送到控制台 | ❌ 不污染 | ✅ 可见 |
| `wsl ... \| Out-Null` | 丢弃 | ❌ 不污染 | ❌ 不可见 |

### 历史教训

本项目曾同时使用 `| Out-Host` + `try/catch` 的组合：

```powershell
try {
    & wsl @wslArgs | Out-Host
}
catch {
    Write-Err "安装失败: $_"
}
```

当初遇到的问题是**返回值被污染**（陷阱 2），加了 `| Out-Host` 后问题解决。但误以为是 `| Out-Host` 让 `try/catch` 生效了，于是保留了 `try/catch`。实际上 `| Out-Host` 解决的是输出管道问题，与异常捕获完全无关——`catch` 块从头到尾都没有执行过。

**正确模式：`| Out-Host` + `$LASTEXITCODE`**

```powershell
& wsl @wslArgs | Out-Host
if ($LASTEXITCODE -ne 0) {
    Write-Err "安装失败 (退出码: $LASTEXITCODE)"
    exit 1
}
```

### 实际案例：Step-CreateUser 管道污染导致 WSL_E_USER_NOT_FOUND

**错误现象：**

```
[INFO] 正在子系统内以 uid=1000(trdx) gid=1000(trdx) groups=1000(trdx),27(sudo) trdx : trdx sudo trdx 身份执行开发环境安装...
<3>WSL (315 - Relay) ERROR: CreateProcessParseCommon:988: getpwnam("uid=1000(trdx)) failed 0
User not found.
Error code: Wsl/WSL_E_USER_NOT_FOUND
```

步骤 7 的日志显示 `$Username` 变量值为 `uid=1000(trdx) gid=1000(trdx) groups=1000(trdx),27(sudo) trdx : trdx sudo trdx`，而不是预期的 `trdx`。WSL 用这个完整字符串去执行 `getpwnam()` 查找用户，自然找不到。

**根因分析：**

`Main` 函数中通过 `$username = Step-CreateUser -InstanceName $instanceName` 捕获返回值。`Step-CreateUser` 内部的 `wsl` 调用（`id`、`useradd`、`chpasswd`、`usermod`、`groups`、`wsl.conf` 配置）没有加 `| Out-Host` 或 `| Out-Null`，其 stdout 输出全部进入了函数的输出管道，与 `return $username` 的值拼接成了一个数组/字符串。

特别是验证命令 `wsl -- bash -c "id '$username' && groups '$username'"` 输出了 `uid=1000(trdx) gid=1000(trdx)...` 这样的内容，混入了 `$username`。

**引入时间线：**

| Commit | 变化 | 结果 |
|--------|------|------|
| `3438076` (feat: init) | 所有 `wsl` 调用有 `\| Out-Host` | ✅ 正常 |
| `1d79423` (refactor: ...) | 重构时移除了大部分 `\| Out-Host` | ❌ 引入 bug |
| `55bb749` ~ `d867afe` | 后续修改未关注管道问题 | ❌ bug 延续 |

**为什么之前"看起来正常"：**

如果之前的测试没有完整走到步骤 7（`Step-RunDevEnvScript`），或者是分步手动执行的，`$username` 被污染的问题就不会暴露。只有当后续代码实际使用 `wsl -u $Username` 时，被污染的用户名才会触发 `WSL_E_USER_NOT_FOUND`。

**修复：**

```diff
- wsl -d $InstanceName -u root -- bash -c "id '$username' >/dev/null 2>&1 || useradd ..."
+ wsl -d $InstanceName -u root -- bash -c "id '$username' >/dev/null 2>&1 || useradd ..." | Out-Null

- wsl -d $InstanceName -u root -- bash -c "id '$username' && groups '$username'"
+ wsl -d $InstanceName -u root -- bash -c "id '$username' && groups '$username'" | Out-Host

- wsl -d $InstanceName -u root -- bash -c $wslConfScript
+ wsl -d $InstanceName -u root -- bash -c $wslConfScript | Out-Null
```

- 内部操作命令（useradd, chpasswd, usermod, wsl.conf）：`| Out-Null`，丢弃输出
- 用户可见的验证命令（id, groups）：`| Out-Host`，输出到控制台但不进入管道

**教训：对所有 `$var = SomeFunction` 捕获返回值的函数，内部每一条会产生 stdout 的语句都必须显式处理输出。**

## chpasswd 跨 OS 管道失败问题

### 问题现象

`Step-CreateUser` 中将密码从 PowerShell 通过 stdin 管道传给 `wsl -- chpasswd`，报错：

```
chpasswd: (user trdx) pam_chauthtok() failed, error:
Authentication token manipulation error
```

### 旧版代码（可以工作）

```powershell
wsl -d $InstanceName -u root -- bash -c "echo '${username}:${pwdPlain}' | chpasswd"
```

密码通过 `echo` 在 Linux 内部管道传给 `chpasswd`，但密码会出现在 `bash -c` 的命令行参数中（`/proc/*/cmdline` 可见）。

### 重构后代码（失败）

```powershell
"${username}:${pwdPlain}" | wsl -d $InstanceName -u root -- chpasswd
```

密码通过 PowerShell stdin 管道传递，不出现在命令行参数中。但 `chpasswd` 报 `pam_chauthtok()` 错误。

### 尝试过的修复方案

| # | 方案 | 结果 | 失败原因 |
|---|------|------|---------|
| 1 | chpasswd 前加 `wsl ... echo 'init'` 触发 WSL 初始化 | ❌ | 不是初始化问题，PAM 已就绪 |
| 2 | `bash -c 'read line && printf "%s\n" "$line" \| chpasswd'` | ❌ `missing new password` | `read` 可能读到空行或 stdin 数据未正确到达 |
| 3 | `bash -c 'tr -d "\r" \| chpasswd'` | 未验证 | 直接进入了方案 4 |
| 4 | stdin → tmpfile → `chpasswd < tmpfile` → shred | ❌ `syntax error` | PowerShell 破坏了 bash 脚本的转义字符（`\r` → `r`，引号嵌套混乱） |

### 诊断数据

```bash
# /etc/shadow 权限正确
-rw-r----- 1 root shadow 728 ... /etc/shadow

# PAM 配置存在
# The PAM configuration file for the Shadow 'chpasswd' service

# 用户 shadow 条目：账户锁定（useradd 默认行为）
trdx:!:20561:0:99999
```

### 根因

**PowerShell → WSL interop 的 stdin 传递机制**与 Linux 内部管道存在差异，具体表现不明确，可能涉及：

1. **CRLF 行尾**：PowerShell 管道用 `\r\n`，chpasswd 不剥离 `\r`
2. **编码差异**：`$OutputEncoding` (ASCII/UTF-8) 与 WSL 内部 stdin 的编码协商
3. **WSL stdin 桥接**：wsl.exe 如何将 Windows 管道数据转发到 Linux 进程的 stdin
4. **锁定账户交互**：shadow 字段为 `!` 的锁定账户 + 非标准 stdin 来源可能触发 PAM 更严格的检查

### 当前状态

回退为旧版 `bash -c "echo '...' | chpasswd"` 写法。接受密码短暂（毫秒级）出现在进程参数列表中的风险。

### 后续改进方向

1. **方案 A**：`openssl passwd -6 -stdin` 在 Linux 端哈希密码 + `usermod -p` 直接写入 shadow（绕过 PAM），但需确认 `openssl` 在最小安装中可用
2. **方案 B**：通过 PowerShell 先将 bash 脚本写入 WSL 文件系统，再执行该脚本文件（避免 `bash -c` 的引号地狱）
3. **方案 C**：研究 `[Console]::OutputEncoding` 和 `$OutputEncoding` 对 wsl.exe stdin 的影响，找到正确的编码设置

## fzf-tab 预览在 cd + Tab 时不生效

### 问题现象

配置了 `zstyle ':fzf-tab:complete:cd:*' fzf-preview ...`，但 `cd` + Tab 只显示左侧补全列表，没有右侧预览面板。Sheldon 和 Oh My Zsh 两种模式都有此问题。

### 排查过程

1. **确认 zstyle 已生效**：`zstyle -L ':fzf-tab:*'` 输出正确 ✅
2. **确认 fzf 支持预览**：`echo test | fzf --preview 'echo hello'` 有右侧面板 ✅
3. **确认终端尺寸足够**：180x44 ✅
4. **确认 eza 可用**：`eza -1 --color=always /tmp` 正常输出 ✅
5. **通配符测试**：`zstyle ':fzf-tab:complete:*' fzf-preview 'echo $realpath'` → 预览出现 ✅
6. **cd 专用上下文**：`':fzf-tab:complete:cd:*'` → 预览不出现 ❌

通配符匹配有效但 `cd` 专用模式无效 → **上下文名称不是 `cd`**。

```bash
❯ type cd
cd is an alias for __zoxide_z
```

### 根因

`zoxide init zsh --cmd cd` 会将 `cd` alias 到 `__zoxide_z`。fzf-tab 使用 `$words[1]`（命令行第一个词的实际解析结果）作为补全上下文中的命令名。由于 `cd` 实际是 `__zoxide_z` 的 alias，fzf-tab 的上下文变成了 `:fzf-tab:complete:__zoxide_z:*`，与 `:fzf-tab:complete:cd:*` 不匹配。

### 修复

使用 zstyle 模式的 alternation 语法同时匹配三种情况：

```bash
# 匹配原生 cd、zoxide 的 __zoxide_z 和交互模式 __zoxide_zi
zstyle ':fzf-tab:complete:(cd|__zoxide_z|__zoxide_zi):*' fzf-preview \
  'eza -1 --color=always --icons --group-directories-first $realpath 2>/dev/null || ls -1 --color=always $realpath'
```

### 教训

**任何通过 alias/function 替换原生命令的工具（zoxide、thefuck 等），都会改变 fzf-tab 的补全上下文名称。** 配置 fzf-tab 的 zstyle 时必须用实际的命令名，而非用户输入的 alias 名。

### 附：关于 zstyle 与 OMZ 加载顺序的误解

网上有说法称"zstyle 必须放在 `source oh-my-zsh.sh` 之前才能被 fzf-tab 读取"——这是**错误**的。

- `zstyle` 是全局注册表，**相同模式最后一次写入胜出**
- fzf-tab 在**按 Tab 时**实时查询 zstyle，而非在插件加载时缓存
- `zstyle ':completion:*'` 放在 OMZ **之后**才能覆盖 `lib/completion.zsh` 的默认值
- 唯一需要前置的是 `zstyle ':omz:plugins:*'`，因为 OMZ 在初始化时读取这些配置项

## Zsh 补全系统的上下文机制

### 补全位置感知

zsh 的补全函数（如 `_ls`、`_cp`、`_eza`）会根据**光标位置和上下文**判断该补全什么内容：

```
ls <TAB>          → 补全函数判断在"参数位"   → 提供文件/目录
ls -<TAB>         → 补全函数判断在"选项位"   → 提供 -l, -a, -h 等 flags
ls -l <TAB>       → 回到"参数位"            → 提供文件/目录
cp file.txt <TAB> → 补全函数知道第二参数是目标 → 提供目录
```

**fzf-tab 是纯 UI 层**，它只接管补全的*显示方式*（从 zsh 原生列表变为 fzf 窗口），不改变"补全什么"。`zstyle fzf-preview` 只影响预览面板内容，不影响候选项是否出现。

### fzf-tab 预览规则的命令分类

| 类别 | 命令 | 预览逻辑 |
|---|---|---|
| 导航 | `cd`, `__zoxide_z`, `__zoxide_zi` | 目录→eza 树形 |
| 列表 | `ls`, `eza`, `exa`, `ll`, `la`, `tree` | 目录→eza 树形，文件→bat |
| 查看 | `cat`, `less`, `more`, `head`, `tail`, `bat`, `batcat` | 文件→bat 语法高亮 |
| 编辑 | `vim`, `nvim`, `nano`, `code`, `view` | 文件→bat 语法高亮 |
| 操作 | `cp`, `mv`, `rm` | 操作前预览=安全保障 |
| 权限 | `chmod`, `chown`, `stat` | 确认当前状态 |
| 脚本 | `source`, `.` | source 前确认内容 |
| 对比 | `file`, `diff` | 文件类型/内容预览 |
| 进程 | `kill` | `ps` 进程详情 |
| 服务 | `systemctl-*` | 服务状态 |
| 变量 | `export`, `unset`, `expand` | 当前变量值 |

### OMZ 下 eza 别名补全失效问题

**现象**：Sheldon 模式 `ls -<TAB>` 正常显示 eza flags，OMZ 模式无补全。

**原因**：zsh 对别名的补全有两种策略：
- `unsetopt COMPLETE_ALIASES`（默认）：zsh 先展开别名 `ls→eza`，再用 `_eza` 补全
- `setopt COMPLETE_ALIASES`：zsh 用别名名 `ls` 查找 `_ls` 补全函数

OMZ 的 eza 插件定义了别名但没有设置 `compdef` 来关联补全函数。当 OMZ 的补全初始化时序导致自动展开失败时，需要显式绑定：

```zsh
# 在 .zshrc 中显式告诉 zsh "这些别名用 _eza 补全"
compdef ls=eza ll=eza la=eza
```

### fzf-tab 候选项前的 `·` 前缀

fzf-tab 默认会在每个补全候选项前添加 `·`（中间点 U+00B7）作为视觉分隔符。可通过 zstyle 控制：

```zsh
# 移除前缀
zstyle ':fzf-tab:*' prefix ''

# 自定义前缀
zstyle ':fzf-tab:*' prefix '▸ '
```

## Zsh 补全问题排查方法

### 诊断步骤

遇到某个命令 `cmd -<TAB>` 无补全时，按以下顺序检查：

```bash
# 1. 检查是否是别名以及展开结果
type cmd               # 确认是否是 alias
alias cmd               # 查看别名内容

# 2. 检查 COMPLETE_ALIASES 选项
[[ -o COMPLETE_ALIASES ]] && echo "SET" || echo "UNSET"
# UNSET = zsh 展开别名后再补全（通常更好）
# SET   = zsh 用别名名本身查找补全函数

# 3. 检查目标命令的补全函数是否存在
whence -v _target_cmd   # 例如 whence -v _eza

# 4. 直接用目标命令测试（绕过别名）
target_cmd -<TAB>       # 例如 eza -<TAB>

# 5. 排除 fzf-tab 干扰
disable-fzf-tab         # 关闭 fzf-tab
cmd -<TAB>              # 测试原生补全是否工作
enable-fzf-tab          # 恢复

# 6. 查看补全上下文调试信息
cmd -<Ctrl+X h>         # 显示哪个补全函数被调用

# 7. 强制绑定补全函数
compdef cmd=target_cmd  # 例如 compdef ls=eza
```

### 常见原因

| 现象 | 原因 | 修复 |
|---|---|---|
| 别名补全不工作，原命令补全正常 | 别名展开后上下文丢失 | `compdef alias=cmd` |
| `compdef` 后依然不行 | fzf-tab 干扰 | `disable-fzf-tab` 测试 |
| 原生补全也不行 | 补全函数未加载 | 检查 fpath 和 `_cmd` 文件 |
| 补全函数存在但不工作 | compinit 缓存过期 | `rm -f ~/.zcompdump*; exec zsh` |
| `compdef` + 无 fzf-tab 也不行 | 别名展开后 `_arguments` 解析错位 | 排查别名中的问题 flag |

### 实例：OMZ 下 `ls -<TAB>` 无补全（Sheldon 正常）

**现象**：Sheldon 和 OMZ 使用同一个 eza 二进制（v0.23.4），但只有 OMZ 的 `ls -<TAB>` 无补全。

**根因：`_eza` 补全文件与安装版本不匹配**

我们通过 `cargo install eza` 安装的是 v0.23.4，但 `_eza` 补全文件从 `main` 分支（未发布版本）下载。main 分支已将 `--hyperlink` 改为接受值（`--hyperlink=WHEN`），但 v0.23.4 中 `--hyperlink` 是纯布尔 flag：

```bash
❯ eza --hyperlink=auto
eza: Flag --hyperlink cannot take a value   # v0.23.4: 布尔 flag
```

OMZ eza 插件在 `zstyle 'hyperlink' yes` 时将 `--hyperlink` 加入别名。别名展开后，`_arguments` 按 main 分支的 spec 认为 `--hyperlink` 需要值，贪婪消费下一个 token（`-`），补全失败。

Sheldon 的别名不含 `--hyperlink`（由本脚本自行定义），因此不触发。

**修复**：从安装版本对应的 tag 下载 `_eza`，而非 `main` 分支：

```bash
eza_ver="$(eza --version | head -1 | grep -oP 'v[\d.]+')"
curl -fsSL "https://raw.githubusercontent.com/eza-community/eza/${eza_ver}/completions/zsh/_eza"
# 回退: tag 不存在时用 main
```

> **教训**：补全文件必须与安装版本匹配。从 `main` 分支下载的补全定义可能包含未发布的 flag 变更，导致 `_arguments` 解析已有参数时错位。




