# =============================================================================
# setup-wsl.ps1 — WSL2 一键安装与配置脚本
# 需以管理员权限运行
#
# 用法: 以管理员身份打开 PowerShell，运行 .\setup-wsl.ps1
# =============================================================================

#Requires -RunAsAdministrator

# ─── 远程执行配置 ─────────────────────────────────────────────────────────────
# 如果你希望通过 `irm https://.../setup-wsl.ps1 | iex` 实现完全一键安装，
# 请将此处的 URL 修改为你自己仓库中 setup-dev-env.sh 的 Raw 链接。
# 当脚本在本地找不到 setup-dev-env.sh 时，将自动从该地址下载。
$Global:RemoteDevEnvScriptUrl = "https://raw.githubusercontent.com/myxdhh/wsl2-ubuntu-one-click/main/setup-dev-env.sh"

$ErrorActionPreference = "Stop"

# ─── 颜色输出 ─────────────────────────────────────────────────────────────────
function Write-Info { param($msg) Write-Host "[INFO] " -ForegroundColor Blue -NoNewline; Write-Host $msg }
function Write-Ok { param($msg) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Write-Warn { param($msg) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-Err { param($msg) Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $msg }
function Write-Header {
    param($msg)
    Write-Host ""
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

function Read-DefaultInput {
    param(
        [string]$Prompt,
        [string]$Default
    )
    $userInput = Read-Host "$Prompt [默认: $Default]"
    if ([string]::IsNullOrWhiteSpace($userInput)) { return $Default }
    return $userInput
}

# ─── 确认提示 ─────────────────────────────────────────────────────────────────
function Confirm-Action {
    param(
        [string]$Message,
        [switch]$DefaultYes
    )
    if ($DefaultYes) {
        $prompt = "$Message (Y/n)"
        $confirm = Read-Host $prompt
        # 默认 Yes：只有明确输入 n/N 才拒绝
        return (-not ($confirm -eq "n" -or $confirm -eq "N"))
    }
    else {
        $prompt = "$Message (y/N)"
        $confirm = Read-Host $prompt
        return ($confirm -eq "y" -or $confirm -eq "Y")
    }
}

# ─── 校验实例名称 ─────────────────────────────────────────────────────────────
function Test-InstanceName {
    param([string]$Name)
    if ($Name -match '^[a-zA-Z][a-zA-Z0-9_-]*$') {
        return $true
    }
    return $false
}

# ─── 校验用户名 ───────────────────────────────────────────────────────────────
function Test-LinuxUsername {
    param([string]$Name)
    if ($Name -match '^[a-z][a-z0-9_-]*$') {
        return $true
    }
    return $false
}



# =============================================================================
# 步骤 0: WSL2 前置条件检查
# =============================================================================
function Step-Prerequisites {
    Write-Header "步骤 0: WSL2 前置条件检查"

    # 检查 Windows 版本
    # WSL2 完整支持需要 Windows 10 版本 2004 (Build 19041) 或更高
    # Build 18362 (1903) 仅支持 WSL1，不支持 WSL2
    $osVersion = [System.Environment]::OSVersion.Version
    Write-Info "当前系统: Windows $($osVersion.Major).$($osVersion.Minor) (Build $($osVersion.Build))"
    if ($osVersion.Build -lt 19041) {
        Write-Err "WSL2 需要 Windows 10 版本 2004 (Build 19041) 或更高版本"
        Write-Err "当前系统 Build $($osVersion.Build) 不满足要求，请先更新 Windows"
        exit 1
    }

    # 检查硬件虚拟化 (Intel VT-x / AMD-V)
    # WSL2 依赖 Hyper-V 虚拟化，必须在 BIOS/UEFI 中开启
    try {
        $vmFirmware = Get-CimInstance -ClassName Win32_Processor -Property VirtualizationFirmwareEnabled -ErrorAction Stop
        if ($vmFirmware.VirtualizationFirmwareEnabled -eq $true) {
            Write-Ok "硬件虚拟化 (VT-x/AMD-V) 已在 BIOS 中启用"
        }
        elseif ($vmFirmware.VirtualizationFirmwareEnabled -eq $false) {
            Write-Err "硬件虚拟化 (VT-x/AMD-V) 未启用！"
            Write-Err "请进入 BIOS/UEFI 设置（开机时按 F2/F10/Del），启用以下选项："
            Write-Host "  Intel 平台: Intel Virtualization Technology (VT-x)" -ForegroundColor Yellow
            Write-Host "  AMD 平台: SVM Mode (AMD-V)" -ForegroundColor Yellow
            Write-Host "  启用后保存并重启，再运行此脚本" -ForegroundColor Yellow
            exit 1
        }
        else {
            Write-Warn "无法确认硬件虚拟化状态，继续安装..."
        }
    }
    catch {
        Write-Warn "无法检测硬件虚拟化状态 (可能权限不足)，继续安装..."
    }

    # 检查 Hyper-V Hypervisor 启动类型
    try {
        $hvStatus = (bcdedit /enum | Select-String -Pattern "hypervisorlaunchtype\s+(\w+)" | ForEach-Object { $_.Matches.Groups[1].Value })
        if ($hvStatus -eq "Off" -or $hvStatus -eq "off") {
            Write-Warn "Hypervisor 启动类型为 Off，WSL2 可能无法正常运行"
            if (Confirm-Action "是否自动修复 (bcdedit /set hypervisorlaunchtype Auto)？" -DefaultYes) {
                bcdedit /set hypervisorlaunchtype Auto | Out-Null
                Write-Ok "已将 Hypervisor 启动类型设为 Auto（需重启生效）"
            }
        }
    }
    catch {
        # bcdedit 可能在某些环境不可用，忽略
    }

    $needRestart = $false

    # 检查 Microsoft-Windows-Subsystem-Linux
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeature.State -eq "Enabled") {
        Write-Ok "适用于 Linux 的 Windows 子系统 已启用"
    }
    else {
        Write-Warn "适用于 Linux 的 Windows 子系统 未启用"
        if (Confirm-Action "是否启用？") {
            dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
            Write-Ok "已启用 适用于 Linux 的 Windows 子系统"
            $needRestart = $true
        }
        else {
            Write-Err "WSL2 需要此功能，脚本退出"
            exit 1
        }
    }

    # 检查 VirtualMachinePlatform
    $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
    if ($vmFeature.State -eq "Enabled") {
        Write-Ok "虚拟机平台 已启用"
    }
    else {
        Write-Warn "虚拟机平台 未启用"
        if (Confirm-Action "是否启用？") {
            dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
            Write-Ok "已启用 虚拟机平台"
            $needRestart = $true
        }
        else {
            Write-Err "WSL2 需要此功能，脚本退出"
            exit 1
        }
    }

    if ($needRestart) {
        Write-Host ""
        Write-Warn "已启用新功能，需要重启计算机后再次运行此脚本"
        Write-Host ""
        if (Confirm-Action "是否立即重启？") {
            Restart-Computer
        }
        Write-Info "请重启计算机后再次运行此脚本"
        exit 0
    }

    # 设置 WSL2 为默认版本
    wsl --set-default-version 2 2>$null
    Write-Ok "已将 WSL 2 设为默认版本"

    # 更新 WSL 组件和内核到最新版本
    Write-Info "检查 WSL 组件更新..."
    $updateOutput = wsl --update 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "WSL 组件已是最新版本"
    }
    else {
        Write-Warn "WSL 更新失败 (可能网络问题)，继续安装..."
        Write-Info "如遇问题可稍后手动运行: wsl --update"
    }

    # 显示当前 WSL 状态
    Write-Info "当前 WSL 状态:"
    wsl --status 2>$null | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

# =============================================================================
# 步骤 4: 选择终端主题
# =============================================================================
function Step-SelectPluginMgr {
    Write-Header "步骤 4a: 选择插件管理器"

    Write-Host "  1) Sheldon (默认)" -ForegroundColor Cyan
    Write-Host "     优势：Rust 编写极速加载、TOML 配置清晰、延迟加载支持、插件并行安装" -ForegroundColor DarkGray
    Write-Host "     注意：不包含 oh-my-zsh 内置插件/主题生态" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  2) Oh My Zsh" -ForegroundColor Cyan
    Write-Host "     优势：社区生态丰富、内置 300+ 插件/140+ 主题、文档完善" -ForegroundColor DarkGray
    Write-Host "     注意：启动速度稍慢、插件需手动 git clone" -ForegroundColor Yellow
    Write-Host ""

    while ($true) {
        $choice = Read-Host "请选择插件管理器 (1/2) [默认: 1]"
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq "1") {
            Write-Ok "已选择: Sheldon"
            return "sheldon"
        }
        elseif ($choice -eq "2") {
            Write-Ok "已选择: Oh My Zsh"
            return "ohmyzsh"
        }
        else {
            Write-Err "无效输入，请重新选择"
        }
    }
}

function Step-SelectTheme {
    Write-Header "步骤 4b: 选择默认终端主题"

    Write-Host "  1) Powerlevel10k (默认)" -ForegroundColor Cyan
    Write-Host "     优势：高度可定制、丰富图标、Git 状态即时显示、Instant Prompt 极速启动" -ForegroundColor DarkGray
    Write-Host "     注意：需要在宿主机安装 Nerd Font 字体" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  2) Pure" -ForegroundColor Cyan
    Write-Host "     优势：极简美观、零配置、不依赖特殊字体、异步 Git 检测不阻塞输入" -ForegroundColor DarkGray
    Write-Host "     注意：宿主机无需安装任何特殊字体" -ForegroundColor Green
    Write-Host ""

    while ($true) {
        $choice = Read-Host "请选择主题 (1/2) [默认: 1]"
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq "1") {
            Write-Ok "已选择: Powerlevel10k"
            return "p10k"
        }
        elseif ($choice -eq "2") {
            Write-Ok "已选择: Pure"
            return "pure"
        }
        else {
            Write-Err "无效输入，请重新选择"
        }
    }
}

# =============================================================================
# 步骤 5: 安装 Nerd Font 字体
# =============================================================================
function Step-InstallFont {
    param(
        [string]$Theme
    )

    Write-Header "步骤 5: 安装 MesloLGS Nerd Font"

    if ($Theme -eq "pure") {
        Write-Info "Pure 主题本身不需要特殊字体，但 eza 命令的文件图标需要 Nerd Font 字体才能正确显示"
    }
    else {
        Write-Info "Powerlevel10k 主题和 eza 命令都需要 Nerd Font 字体才能正确显示图标"
    }
    if (-not (Confirm-Action "是否安装 MesloLGS NF 字体并配置终端？" -DefaultYes)) {
        Write-Info "跳过字体安装"
        return
    }

    # p10k 推荐的 4 个字体文件
    $fontBaseUrl = "https://github.com/romkatv/powerlevel10k-media/raw/master"
    $fonts = @(
        @{ File = "MesloLGS NF Regular.ttf"; Url = "$fontBaseUrl/MesloLGS%20NF%20Regular.ttf" }
        @{ File = "MesloLGS NF Bold.ttf"; Url = "$fontBaseUrl/MesloLGS%20NF%20Bold.ttf" }
        @{ File = "MesloLGS NF Italic.ttf"; Url = "$fontBaseUrl/MesloLGS%20NF%20Italic.ttf" }
        @{ File = "MesloLGS NF Bold Italic.ttf"; Url = "$fontBaseUrl/MesloLGS%20NF%20Bold%20Italic.ttf" }
    )

    $fontsDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    if (-not (Test-Path $fontsDir)) {
        New-Item -Path $fontsDir -ItemType Directory -Force | Out-Null
    }

    $allInstalled = $true
    foreach ($font in $fonts) {
        $targetPath = Join-Path $fontsDir $font.File
        if (Test-Path $targetPath) {
            Write-Ok "已安装: $($font.File)"
            continue
        }
        $allInstalled = $false
    }

    if ($allInstalled) {
        Write-Ok "MesloLGS NF 字体已全部安装"
    }
    else {
        Write-Info "正在下载并安装字体..."

        $tempDir = Join-Path $env:TEMP "meslo-nf-fonts"
        if (-not (Test-Path $tempDir)) {
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        }

        foreach ($font in $fonts) {
            $targetPath = Join-Path $fontsDir $font.File
            if (Test-Path $targetPath) { continue }

            $tempPath = Join-Path $tempDir $font.File
            try {
                Write-Info "下载: $($font.File)..."
                Invoke-WebRequest -Uri $font.Url -OutFile $tempPath -UseBasicParsing

                # 复制到用户字体目录
                Copy-Item $tempPath $targetPath -Force

                # 注册字体到注册表（当前用户）
                $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
                $fontName = [System.IO.Path]::GetFileNameWithoutExtension($font.File) + " (TrueType)"
                New-ItemProperty -Path $regPath -Name $fontName -Value $targetPath -PropertyType String -Force | Out-Null

                Write-Ok "已安装: $($font.File)"
            }
            catch {
                Write-Warn "下载失败: $($font.File) - $_"
            }
        }

        # 清理临时文件
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Ok "MesloLGS NF 字体安装完成"
    }

    # 配置 Windows Terminal
    $wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $wtPreviewSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"

    $settingsFiles = @()
    if (Test-Path $wtSettingsPath) { $settingsFiles += @{ Path = $wtSettingsPath; Name = "Windows Terminal" } }
    if (Test-Path $wtPreviewSettingsPath) { $settingsFiles += @{ Path = $wtPreviewSettingsPath; Name = "Windows Terminal Preview" } }

    if ($settingsFiles.Count -eq 0) {
        Write-Warn "未检测到 Windows Terminal，请手动将字体设为 'MesloLGS NF'"
        Write-Info "  如使用其他终端，请在其设置中将字体改为 MesloLGS NF"
        return
    }

    foreach ($settingsFile in $settingsFiles) {
        try {
            Write-Info "配置 $($settingsFile.Name) 字体..."

            # 读取 JSON（去除注释，Windows Terminal 的 JSON 允许 JSONC 格式注释）
            $rawContent = Get-Content $settingsFile.Path -Raw
            # 移除独占一整行的 // 注释（不触及字符串值中的 URL 等）
            $cleanContent = $rawContent -replace '(?m)^\s*//.*$', ''
            # 移除行尾 // 注释（跟在 , 或 { 后面的注释）
            $cleanContent = $cleanContent -replace '(?m)(["{},\]\[]\s*)//(?![/"]).+$', '$1'
            $settings = $cleanContent | ConvertFrom-Json

            $modified = $false

            # 设置 profiles.defaults 的 font face
            if (-not $settings.profiles.defaults) {
                $settings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force
            }

            $defaults = $settings.profiles.defaults

            if (-not $defaults.font) {
                $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue ([PSCustomObject]@{ face = "MesloLGS NF" }) -Force
                $modified = $true
            }
            elseif ($defaults.font.face -ne "MesloLGS NF") {
                $defaults.font.face = "MesloLGS NF"
                $modified = $true
            }

            if ($modified) {
                $settings | ConvertTo-Json -Depth 32 | Set-Content $settingsFile.Path -Encoding UTF8
                Write-Ok "$($settingsFile.Name) 已配置 font face = MesloLGS NF"
            }
            else {
                Write-Ok "$($settingsFile.Name) 已是 MesloLGS NF，无需修改"
            }
        }
        catch {
            Write-Warn "$($settingsFile.Name) 配置失败: $_"
            Write-Info "  请手动在 $($settingsFile.Name) 设置中将字体改为 MesloLGS NF"
        }
    }
}

# =============================================================================
# 步骤 1: 选择分发版与安装
# =============================================================================
function Step-InstallDistro {
    Write-Header "步骤 1: 选择并安装 WSL2 分发版"

    # 分发版列表（均已确认支持 --web-download）
    $distros = @(
        @{ Number = 1; Name = "Ubuntu-24.04"; Label = "Ubuntu 24.04 LTS"; DefaultName = "Ubuntu2404" }
        @{ Number = 2; Name = "Ubuntu-22.04"; Label = "Ubuntu 22.04 LTS"; DefaultName = "Ubuntu2204" }
        @{ Number = 3; Name = "Ubuntu-20.04"; Label = "Ubuntu 20.04 LTS"; DefaultName = "Ubuntu2004" }
        @{ Number = 4; Name = "Debian"; Label = "Debian"; DefaultName = "Debian" }
    )

    Write-Host "可用分发版（均支持 --web-download）：" -ForegroundColor Cyan
    foreach ($d in $distros) {
        $marker = if ($d.Number -eq 1) { " ★默认" } else { "" }
        Write-Host ("  {0}) {1}{2}" -f $d.Number, $d.Label, $marker)
    }
    Write-Host ""

    $distroChoice = Read-DefaultInput -Prompt "请选择分发版编号" -Default "1"
    $distroIndex = [int]$distroChoice - 1
    if ($distroIndex -lt 0 -or $distroIndex -ge $distros.Count) {
        Write-Warn "无效选择，使用默认 Ubuntu-24.04"
        $distroIndex = 0
    }
    $selectedDistro = $distros[$distroIndex].Name
    $defaultInstanceName = $distros[$distroIndex].DefaultName
    Write-Ok "选择分发版: $selectedDistro"

    # 自定义实例名称（含校验）
    while ($true) {
        $instanceName = Read-DefaultInput -Prompt "自定义实例名称（字母开头，允许字母数字下划线连字符）" -Default $defaultInstanceName
        if (Test-InstanceName $instanceName) {
            break
        }
        Write-Err "实例名称格式无效，请使用字母开头、仅包含字母数字下划线连字符"
    }
    Write-Ok "实例名称: $instanceName"

    # 检查是否已存在同名实例
    $existingDistros = (wsl --list --quiet 2>$null) | ForEach-Object { $_.Trim().Replace("`0", "") } | Where-Object { $_ -ne "" }
    if ($existingDistros -and ($existingDistros -contains $instanceName)) {
        Write-Warn "已存在同名实例: $instanceName"
        if (-not (Confirm-Action "是否继续安装（会覆盖现有实例）？")) {
            Write-Info "已取消"
            exit 0
        }
    }

    # 安装目录
    $defaultLocation = Join-Path (Get-Location) $instanceName
    $installLocation = Read-DefaultInput -Prompt "安装目录" -Default $defaultLocation

    # 确保目录的父目录存在
    $parentDir = Split-Path $installLocation -Parent
    if (-not (Test-Path $parentDir)) {
        Write-Info "创建目录: $parentDir"
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }

    Write-Ok "安装目录: $installLocation"

    # 安装前确认
    Write-Host ""
    Write-Host "安装概要：" -ForegroundColor Cyan
    Write-Host "  分发版:    $selectedDistro"
    Write-Host "  实例名称:  $instanceName"
    Write-Host "  安装目录:  $installLocation"
    Write-Host "  下载方式:  web-download"
    Write-Host ""

    if (-not (Confirm-Action "确认安装？" -DefaultYes)) {
        Write-Info "已取消"
        exit 0
    }

    # 安装（使用 --no-launch 避免自动进入子系统）
    Write-Info "正在安装 $selectedDistro（--web-download --no-launch 模式，这可能需要几分钟）..."
    $wslArgs = @("--install", "-d", $selectedDistro, "--location", $installLocation, "--name", $instanceName, "--version", "2", "--web-download", "--no-launch")
    Write-Info "命令: wsl $($wslArgs -join ' ')"

    try {
        & wsl @wslArgs | Out-Host
    }
    catch {
        Write-Err "安装失败: $_"
        Write-Info "请检查网络连接或尝试使用代理"
        exit 1
    }

    # 等待注册完成
    Start-Sleep -Seconds 3

    # 验证分发版已注册
    $registeredDistros = (wsl --list --quiet 2>$null) | ForEach-Object { $_.Trim().Replace("`0", "") } | Where-Object { $_ -ne "" }
    if ($registeredDistros -and ($registeredDistros -contains $instanceName)) {
        Write-Ok "分发版 $instanceName 安装并注册成功"
    }
    else {
        Write-Warn "未检测到已注册的实例 '$instanceName'"
        Write-Info "已注册的分发版: $($registeredDistros -join ', ')"
        # 尝试使用原始分发版名称
        if ($registeredDistros -and ($registeredDistros -contains $selectedDistro)) {
            Write-Info "检测到以原始名称 '$selectedDistro' 注册的实例，将使用此名称"
            $instanceName = $selectedDistro
        }
        else {
            Write-Err "分发版注册失败，请手动检查 'wsl --list'"
            exit 1
        }
    }

    Write-Ok "分发版安装完成"

    return $instanceName
}

# =============================================================================
# 步骤 2: 配置 .wslconfig
# =============================================================================
function Step-ConfigureWslconfig {
    Write-Header "步骤 2: 配置 .wslconfig"

    $wslconfigPath = Join-Path $env:USERPROFILE ".wslconfig"

    # 读取现有配置
    if (Test-Path $wslconfigPath) {
        Write-Info "已检测到现有 .wslconfig"
        Write-Host ""
        Write-Host "当前内容：" -ForegroundColor DarkGray
        Get-Content $wslconfigPath | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        Write-Host ""

        # 备份现有文件
        $backupPath = "$wslconfigPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $wslconfigPath $backupPath
        Write-Info "已备份到: $backupPath"
    }

    Write-Info "请逐项选择配置（直接回车采用 ★默认值）："

    # ── autoMemoryReclaim ──
    Write-Host ""
    Write-Host "autoMemoryReclaim - 自动内存回收（[experimental] 节）" -ForegroundColor Cyan
    Write-Host "  1) disabled  - 不自动回收"
    Write-Host "  2) gradual   - 渐进回收 ★默认"
    Write-Host "  3) dropCache - 立即释放缓存"
    $amrChoice = Read-DefaultInput -Prompt "请选择 (1/2/3)" -Default "2"
    switch ($amrChoice) {
        "1" { $autoMemoryReclaim = "disabled" }
        "3" { $autoMemoryReclaim = "dropCache" }
        default { $autoMemoryReclaim = "gradual" }
    }
    Write-Ok "autoMemoryReclaim=$autoMemoryReclaim"

    # ── networkingMode ──
    Write-Host ""
    Write-Host "networkingMode - 网络模式（[wsl2] 节）" -ForegroundColor Cyan
    Write-Host "  1) NAT          - 网络地址转换"
    Write-Host "  2) mirrored     - 镜像模式 ★默认"
    Write-Host "  3) bridged      - 桥接模式"
    Write-Host "  4) virtioproxy  - VirtIO 代理模式"
    Write-Host "  5) none         - 无网络"
    $nmChoice = Read-DefaultInput -Prompt "请选择 (1-5)" -Default "2"
    switch ($nmChoice) {
        "1" { $networkingMode = "NAT" }
        "3" { $networkingMode = "bridged" }
        "4" { $networkingMode = "virtioproxy" }
        "5" { $networkingMode = "none" }
        default { $networkingMode = "mirrored" }
    }
    Write-Ok "networkingMode=$networkingMode"

    # ── dnsTunneling ──
    Write-Host ""
    Write-Host "dnsTunneling - DNS 隧道（[wsl2] 节）" -ForegroundColor Cyan
    Write-Host "  1) true  ★默认"
    Write-Host "  2) false"
    $dtChoice = Read-DefaultInput -Prompt "请选择 (1/2)" -Default "1"
    $dnsTunneling = if ($dtChoice -eq "2") { "false" } else { "true" }
    Write-Ok "dnsTunneling=$dnsTunneling"

    # ── firewall ──
    Write-Host ""
    Write-Host "firewall - 防火墙（[wsl2] 节）" -ForegroundColor Cyan
    Write-Host "  1) true  ★默认"
    Write-Host "  2) false"
    $fwChoice = Read-DefaultInput -Prompt "请选择 (1/2)" -Default "1"
    $firewall = if ($fwChoice -eq "2") { "false" } else { "true" }
    Write-Ok "firewall=$firewall"

    # ── autoProxy ──
    Write-Host ""
    Write-Host "autoProxy - 自动代理（[wsl2] 节）" -ForegroundColor Cyan
    Write-Host "  1) true  ★默认"
    Write-Host "  2) false"
    $apChoice = Read-DefaultInput -Prompt "请选择 (1/2)" -Default "1"
    $autoProxy = if ($apChoice -eq "2") { "false" } else { "true" }
    Write-Ok "autoProxy=$autoProxy"

    # 构建新的配置键值
    $newWsl2Settings = @{
        "networkingMode" = $networkingMode
        "dnsTunneling"   = $dnsTunneling
        "firewall"       = $firewall
        "autoProxy"      = $autoProxy
    }
    $newExperimentalSettings = @{
        "autoMemoryReclaim" = $autoMemoryReclaim
    }

    # 解析已有 .wslconfig 内容，合并而非覆盖
    $existingSections = @{}
    $currentSection = ""
    if (Test-Path $wslconfigPath) {
        foreach ($line in (Get-Content $wslconfigPath)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[(.+)\]$') {
                $currentSection = $Matches[1]
                if (-not $existingSections.ContainsKey($currentSection)) {
                    $existingSections[$currentSection] = [ordered]@{}
                }
            }
            elseif ($trimmed -match '^([^#;][^=]*)=(.*)$' -and $currentSection) {
                $existingSections[$currentSection][$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }

    # 合并 [wsl2] 节
    if (-not $existingSections.ContainsKey("wsl2")) {
        $existingSections["wsl2"] = [ordered]@{}
    }
    foreach ($key in $newWsl2Settings.Keys) {
        $existingSections["wsl2"][$key] = $newWsl2Settings[$key]
    }

    # 合并 [experimental] 节
    if (-not $existingSections.ContainsKey("experimental")) {
        $existingSections["experimental"] = [ordered]@{}
    }
    foreach ($key in $newExperimentalSettings.Keys) {
        $existingSections["experimental"][$key] = $newExperimentalSettings[$key]
    }

    # 重新生成 .wslconfig 内容
    $lines = @("# WSL2 全局配置 - 由 setup-wsl.ps1 生成", "# 更多设置请参考: https://learn.microsoft.com/zh-cn/windows/wsl/wsl-config", "")
    foreach ($section in $existingSections.Keys) {
        $lines += "[$section]"
        foreach ($key in $existingSections[$section].Keys) {
            $lines += "$key=$($existingSections[$section][$key])"
        }
        $lines += ""
    }
    $wslconfigContent = ($lines -join "`n").TrimEnd("`n")

    # 写入文件（使用 UTF8NoBOM，避免 BOM 影响 WSL 读取）
    [System.IO.File]::WriteAllText($wslconfigPath, $wslconfigContent, [System.Text.UTF8Encoding]::new($false))
    Write-Ok ".wslconfig 已写入: $wslconfigPath"

    Write-Host ""
    Write-Host "最终配置：" -ForegroundColor Cyan
    Write-Host $wslconfigContent
    Write-Host ""
}

# =============================================================================
# 步骤 3: 创建用户
# =============================================================================
function Step-CreateUser {
    param([string]$InstanceName)

    Write-Header "步骤 3: 创建用户"

    # 输入用户名（含校验）
    while ($true) {
        $username = Read-Host "请输入 Linux 用户名（小写字母开头，允许字母数字下划线连字符）"
        if ([string]::IsNullOrWhiteSpace($username)) {
            Write-Err "用户名不能为空"
            continue
        }
        if (Test-LinuxUsername $username) {
            break
        }
        Write-Err "用户名格式无效：必须小写字母开头，仅包含小写字母、数字、下划线、连字符"
    }

    # 输入密码（含确认循环）
    while ($true) {
        $password = Read-Host "请输入密码" -AsSecureString
        $passwordConfirm = Read-Host "请确认密码" -AsSecureString

        # 安全地解密 SecureString，确保 BSTR 指针被释放
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        try {
            $pwdPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }

        $bstrConfirm = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordConfirm)
        try {
            $pwdConfirmPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstrConfirm)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrConfirm)
        }

        if ([string]::IsNullOrWhiteSpace($pwdPlain)) {
            Write-Err "密码不能为空"
            continue
        }

        if ($pwdPlain -eq $pwdConfirmPlain) {
            break
        }
        Write-Err "两次输入的密码不一致，请重新输入"
    }

    # 在 WSL 内创建用户
    Write-Info "在子系统 $InstanceName 中创建用户 $username..."

    try {
        wsl -d $InstanceName -u root -- bash -c "id '$username' >/dev/null 2>&1 || useradd -m -s /bin/bash '$username'"
        if ($LASTEXITCODE -ne 0) {
            # 再次验证用户是否存在
            wsl -d $InstanceName -u root -- bash -c "id '$username'"
            if ($LASTEXITCODE -ne 0) { throw "useradd 失败" }
        }

        # 通过管道传入密码，避免密码中的特殊字符被 shell 解释
        "${username}:${pwdPlain}" | wsl -d $InstanceName -u root -- chpasswd
        if ($LASTEXITCODE -ne 0) { throw "chpasswd 失败" }

        # 添加到 sudo 组
        wsl -d $InstanceName -u root -- bash -c "usermod -aG sudo '$username'"
        if ($LASTEXITCODE -ne 0) { throw "usermod 失败" }

        # 验证用户创建成功
        wsl -d $InstanceName -u root -- bash -c "id '$username' && groups '$username'"
        if ($LASTEXITCODE -ne 0) { throw "用户验证失败" }

        Write-Ok "用户 $username 创建完成"

        # 设置默认用户（通过 /etc/wsl.conf），合并而非覆盖已有配置
        $wslConfScript = @"
if grep -q '^\[user\]' /etc/wsl.conf 2>/dev/null; then
    if grep -q '^default=' /etc/wsl.conf; then
        sed -i '/^\[user\]/,/^\[/{s/^default=.*/default=$username/}' /etc/wsl.conf
    else
        sed -i '/^\[user\]/a default=$username' /etc/wsl.conf
    fi
else
    printf '\n[user]\ndefault=$username\n' >> /etc/wsl.conf
fi
"@
        wsl -d $InstanceName -u root -- bash -c $wslConfScript
        if ($LASTEXITCODE -ne 0) { throw "wsl.conf 配置失败" }

        Write-Ok "已将 $username 设为子系统默认用户"
    }
    catch {
        Write-Err "用户创建过程中出错: $_"
        exit 1
    }
    finally {
        $pwdPlain = $null
        $pwdConfirmPlain = $null
        [System.GC]::Collect()
    }

    # sudo 免密配置
    if (Confirm-Action "是否为 $username 配置 sudo 免密？" -DefaultYes) {
        try {
            wsl -d $InstanceName -u root -- bash -c "echo '$username ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$username && chmod 0440 /etc/sudoers.d/$username" | Out-Host
            Write-Ok "用户 $username 已配置 sudo 免密"
        }
        catch {
            Write-Warn "配置 sudoers 失败: $_（可稍后手动配置）"
        }
    }
    else {
        Write-Info "跳过 sudo 免密配置"
    }

    return $username
}

# =============================================================================
# 步骤 6: 选择要安装的开发工具
# =============================================================================
function Step-SelectComponents {
    param(
        [string]$PluginMgr = "sheldon"
    )

    Write-Header "步骤 6: 选择要安装的开发工具"

    $components = @(
        @{ Id = "rustup"; Name = "Rust 工具链 (rustup)" }
        @{ Id = "eza"; Name = "eza (现代 ls 替代)" }
        @{ Id = "yazi"; Name = "yazi (终端文件管理器)" }
        @{ Id = "volta"; Name = "Volta (Node.js/npm/pnpm 版本管理)" }
        @{ Id = "uv"; Name = "uv (Python 环境管理)" }
        @{ Id = "proto"; Name = "proto (多语言版本管理)" }
    )

    if ($pluginMgr -eq "sheldon") {
        Write-Host "  基础组件 (始终安装): Zsh, Sheldon, 主题, zsh-autosuggestions, zsh-syntax-highlighting" -ForegroundColor DarkGray
    } else {
        Write-Host "  基础组件 (始终安装): Zsh, Oh My Zsh, 主题, zsh-autosuggestions, zsh-syntax-highlighting" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  可选开发工具：" -ForegroundColor Cyan

    for ($i = 0; $i -lt $components.Count; $i++) {
        $num = $i + 1
        $name = $components[$i].Name
        Write-Host "  $num) $name"
    }

    Write-Host ""
    while ($true) {
        $choice = Read-Host "请输入编号 (逗号分隔，如 1,3,4) 或输入 all 全选 [默认: all]"
        
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice.Trim().ToLower() -eq "all") {
            Write-Ok "已选择全部组件"
            return "" # empty means all in setup-dev-env.sh
        }
        
        $selectedIds = @()
        $nums = $choice -split ','
        $valid = $true
        
        foreach ($n in $nums) {
            $n = $n.Trim()
            if ($n -notmatch "^\d+$" -or [int]$n -lt 1 -or [int]$n -gt $components.Count) {
                Write-Err "无效输入: $n，请重新输入"
                $valid = $false
                break
            }
            $selectedIds += $components[[int]$n - 1].Id
        }
        
        if ($valid -and $selectedIds.Count -gt 0) {
            $compString = $selectedIds -join ","
            Write-Ok "已选择: $compString"
            return $compString
        }
    }
}

# =============================================================================
# 步骤 7: 执行 Linux 开发环境安装脚本
# =============================================================================
function Step-RunDevEnvScript {
    param(
        [string]$InstanceName,
        [string]$Username,
        [string]$PluginMgr,
        [string]$Theme,
        [string]$Components
    )

    Write-Header "步骤 7: 安装开发环境"

    # 获取脚本路径
    $scriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptDir)) {
        $scriptDir = Get-Location
    }
    $devEnvScript = Join-Path $scriptDir "setup-dev-env.sh"

    $isTempDownload = $false
    if (-not (Test-Path $devEnvScript)) {
        Write-Info "本地未找到 setup-dev-env.sh，尝试从远程下载..."
        try {
            $devEnvScript = Join-Path $env:TEMP "setup-dev-env.sh"
            $isTempDownload = $true
            Write-Info "下载地址: $Global:RemoteDevEnvScriptUrl"
            # 兼容 PowerShell 5.1 TLS 版本问题
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $Global:RemoteDevEnvScriptUrl -OutFile $devEnvScript -UseBasicParsing | Out-Null
            Write-Ok "下载成功: $devEnvScript"
        }
        catch {
            Write-Err "无法从远程下载 setup-dev-env.sh，请检查脚本顶部的 `$Global:RemoteDevEnvScriptUrl 是否配置正确。"
            Write-Err "错误详情: $_"
            exit 1
        }
    }

    # 将脚本转换为 LF 行尾（WSL 需要）
    Write-Info "处理脚本行尾格式..."
    $content = Get-Content $devEnvScript -Raw
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($devEnvScript, $content, [System.Text.UTF8Encoding]::new($false))

    # 将 Windows 路径转为 WSL 路径
    $wslScriptPath = wsl -d $InstanceName -- wslpath -u ($devEnvScript -replace '\\', '/')
    $wslScriptPath = $wslScriptPath.Trim()

    # 复制到用户 home 目录
    Write-Info "复制安装脚本到子系统..."
    wsl -d $InstanceName -u $Username -- bash -c "cp '$wslScriptPath' ~/setup-dev-env.sh && chmod +x ~/setup-dev-env.sh"

    # 移除 Windows 端的临时下载文件
    if ($isTempDownload) {
        Remove-Item $devEnvScript -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Info "正在子系统内以 $Username 身份执行开发环境安装..."
    Write-Warn "这可能需要 20-30 分钟（Rust 编译 eza/yazi 耗时较长），请耐心等待..."
    Write-Host ""

    # 终止并重启 WSL 实例以应用 wsl.conf 的默认用户设置
    wsl --terminate $InstanceName 2>$null
    Start-Sleep -Seconds 2

    # 执行脚本
    $cmd = "bash ~/setup-dev-env.sh --install --auto-cleanup"
    if (-not [string]::IsNullOrEmpty($PluginMgr)) {
        $cmd += " --plugin-mgr $PluginMgr"
    }
    if (-not [string]::IsNullOrEmpty($Theme)) {
        $cmd += " --theme $Theme"
    }
    if (-not [string]::IsNullOrEmpty($Components)) {
        $cmd += " --components `"$Components`""
    }
    
    wsl -d $InstanceName -u $Username -- bash -c $cmd

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "开发环境安装完成"
    }
    else {
        Write-Warn "开发环境安装过程中出现部分错误，请查看上方输出日志"
    }
}

# =============================================================================
# 辅助函数: 检查管理员权限
# =============================================================================
function Test-Admin {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = [System.Security.Principal.WindowsPrincipal]::new($wid)
    $isAdmin = $prp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host ""
        Write-Host " [错误] 此脚本需要管理员权限运行！" -ForegroundColor Red
        Write-Host " 请右键点击 PowerShell 并选择 '以管理员身份运行'，然后再执行此脚本。" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

# =============================================================================
# 主函数
# =============================================================================
function Main {
    param(
        [switch]$FontOnly
    )

    Test-Admin

    $startTime = Get-Date

    if ($FontOnly) {
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  MesloLGS Nerd Font 字体安装" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""
        $theme = Step-SelectTheme
        Step-InstallFont -Theme $theme

        $elapsed = (Get-Date) - $startTime
        $elapsedStr = "{0:D2}:{1:D2}:{2:D2}" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds
        Write-Host ""
        Write-Header "🎉 字体安装完成！(耗时 $elapsedStr)"
        return
    }

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  WSL2 一键安装与开发环境配置脚本" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  本脚本将完成以下步骤：" -ForegroundColor DarkGray
    Write-Host "    0) 检查并启用 WSL2 前置功能" -ForegroundColor DarkGray
    Write-Host "    1) 选择并安装 Linux 分发版" -ForegroundColor DarkGray
    Write-Host "    2) 配置 .wslconfig" -ForegroundColor DarkGray
    Write-Host "    3) 创建用户（含 sudo 免密）" -ForegroundColor DarkGray
    Write-Host "    4) 选择插件管理器和终端主题" -ForegroundColor DarkGray
    Write-Host "    5) 安装 MesloLGS Nerd Font 字体（依据主题选择）" -ForegroundColor DarkGray
    Write-Host "    6) 选择要安装的开发工具" -ForegroundColor DarkGray
    Write-Host "    7) 执行 Linux 开发环境安装脚本" -ForegroundColor DarkGray
    Write-Host ""

    # 步骤 0: 前置检查
    Step-Prerequisites

    # 步骤 1: 安装分发版
    $instanceName = Step-InstallDistro

    # 步骤 2: 配置 .wslconfig
    Step-ConfigureWslconfig

    # 步骤 3: 创建用户
    $username = Step-CreateUser -InstanceName $instanceName

    # 步骤 4a: 选择插件管理器
    $pluginMgr = Step-SelectPluginMgr

    # 步骤 4b: 选择主题
    $theme = Step-SelectTheme

    # 步骤 5: 安装字体
    Step-InstallFont -Theme $theme

    # 步骤 6: 选择组件
    $components = Step-SelectComponents -PluginMgr $pluginMgr

    # 关闭 WSL 使 .wslconfig + wsl.conf 生效
    Write-Info "正在重启 WSL 以应用配置..."
    wsl --shutdown
    Start-Sleep -Seconds 3

    # 步骤 7: 执行开发环境脚本
    Step-RunDevEnvScript -InstanceName $instanceName -Username $username -PluginMgr $pluginMgr -Theme $theme -Components $components

    $elapsed = (Get-Date) - $startTime
    $elapsedStr = "{0:D2}:{1:D2}:{2:D2}" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds

    Write-Host ""
    Write-Header "🎉 全部完成！(耗时 $elapsedStr)"
    Write-Host "  分发版: $instanceName" -ForegroundColor Green
    Write-Host "  用户名: $username" -ForegroundColor Green
    if ($pluginMgr -eq "sheldon") {
        Write-Host "  插件管理器: Sheldon" -ForegroundColor Green
    } else {
        Write-Host "  插件管理器: Oh My Zsh" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  进入子系统:  " -ForegroundColor Yellow -NoNewline
    Write-Host "wsl -d $instanceName" -ForegroundColor White
    Write-Host ""
    if ($theme -eq "pure") {
        Write-Info "Pure 主题已配置，无需额外步骤"
    }
    else {
        Write-Info "如使用 Powerlevel10k 主题，请在子系统内运行 p10k configure 配置主题偏好"
    }
    Write-Host ""
}

# 解析参数并运行
if ($args -contains "--font-only") {
    Main -FontOnly
}
else {
    Main
}
