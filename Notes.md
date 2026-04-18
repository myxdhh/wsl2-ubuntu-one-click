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

