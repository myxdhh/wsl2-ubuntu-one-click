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
