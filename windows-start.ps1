[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeFile = Join-Path $Root "compose.easyconnect.yml"
$CaptchaFile = Join-Path $Root "runtime-data\kaptcha.png"
$AnswerFile = Join-Path $Root "runtime-data\captcha-answer.txt"
$ProbeSuccessFile = Join-Path $Root "runtime-data\interactive-probe-success"
. (Join-Path $Root "windows-ui.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-Info([string]$Text, [string]$Title = "成绩检查服务") {
    [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-ErrorMessage([string]$Text) {
    [System.Windows.Forms.MessageBox]::Show(
        $Text,
        "启动失败",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Show-StartupProgress([int]$Percent, [string]$Status) {
    $safePercent = [Math]::Max(0, [Math]::Min(100, $Percent))
    Write-Host ("[阶段 {0,3}%] {1}" -f $safePercent, $Status) -ForegroundColor Cyan
}

function Complete-StartupProgress {
    # 动态行由 windows-ui.ps1 负责清除，此处保留统一的结束钩子。
}

function Show-CaptchaDialog([string]$ImagePath) {
    $bitmap = $null
    for ($attempt = 0; $attempt -lt 20 -and $null -eq $bitmap; $attempt++) {
        try {
            $stream = [IO.File]::Open(
                $ImagePath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::ReadWrite
            )
            try {
                $source = [System.Drawing.Image]::FromStream($stream)
                try { $bitmap = [System.Drawing.Bitmap]::new($source) }
                finally { $source.Dispose() }
            }
            finally { $stream.Dispose() }
        }
        catch {
            Start-Sleep -Milliseconds 150
        }
    }
    if ($null -eq $bitmap) {
        throw "无法读取验证码图片，请重新运行启动程序。"
    }

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "请输入正方教务验证码"
    $form.ClientSize = [System.Drawing.Size]::new(460, 245)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.TopMost = $true

    $picture = [System.Windows.Forms.PictureBox]::new()
    $picture.Location = [System.Drawing.Point]::new(20, 18)
    $picture.Size = [System.Drawing.Size]::new(420, 105)
    $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $picture.Image = $bitmap
    $form.Controls.Add($picture)

    $label = [System.Windows.Forms.Label]::new()
    $label.Text = "请按图片原样输入 6 位验证码："
    $label.AutoSize = $true
    $label.Location = [System.Drawing.Point]::new(20, 137)
    $form.Controls.Add($label)

    $input = [System.Windows.Forms.TextBox]::new()
    $input.Font = [System.Drawing.Font]::new("Segoe UI", 14)
    $input.Location = [System.Drawing.Point]::new(20, 162)
    $input.Size = [System.Drawing.Size]::new(270, 34)
    $input.MaxLength = 12
    $form.Controls.Add($input)

    $ok = [System.Windows.Forms.Button]::new()
    $ok.Text = "确定"
    $ok.Location = [System.Drawing.Point]::new(305, 161)
    $ok.Size = [System.Drawing.Size]::new(65, 35)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($ok)

    $cancel = [System.Windows.Forms.Button]::new()
    $cancel.Text = "取消"
    $cancel.Location = [System.Drawing.Point]::new(375, 161)
    $cancel.Size = [System.Drawing.Size]::new(65, 35)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)

    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    # Avoid a PowerShell script-block Shown handler here. Under Windows
    # PowerShell 5.1 the callback can lose the outer $input variable and
    # raise a WinForms JIT dialog even though captcha entry still works.
    $form.ActiveControl = $input

    try {
        $result = $form.ShowDialog()
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        return $input.Text.Trim()
    }
    finally {
        $bitmap.Dispose()
        $form.Dispose()
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Value) {
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}

function Get-ProjectSetting([string]$Name, [string]$DefaultValue) {
    $processValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($processValue)) {
        return $processValue.Trim().Trim('"', "'")
    }
    $envPath = Join-Path $Root ".env"
    if (Test-Path -LiteralPath $envPath) {
        foreach ($line in Get-Content -LiteralPath $envPath) {
            if ($line -match "^\s*$([regex]::Escape($Name))\s*=\s*(.*?)\s*$") {
                return $Matches[1].Trim().Trim('"', "'")
            }
        }
    }
    return $DefaultValue
}

function Get-ZhengfangLoginUrl {
    $baseUrl = Get-ProjectSetting "ZF_URL" "http://jwxt.cumt.edu.cn/jwglxt/"
    if ($baseUrl -match "login_slogin\.html(?:\?.*)?$") {
        return $baseUrl
    }
    return $baseUrl.TrimEnd('/') + "/xtgl/login_slogin.html"
}

function Test-WindowsZhengfangAccess([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 6
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 400
    }
    catch {
        return $false
    }
}

function Invoke-DockerCommand {
    param(
        [string[]]$Arguments,
        [switch]$Quiet,
        [string]$Status = "执行 Docker 操作",
        [int]$StartPercent = 0,
        [int]$EndPercent = 100
    )

    if (-not $Quiet) {
        $result = Invoke-DockerWithProgress -Arguments $Arguments `
            -Activity "正在启动正方成绩检查服务" -Status $Status `
            -StartPercent $StartPercent -EndPercent $EndPercent -WorkingDirectory $Root
        $script:LastDockerExitCode = $result.ExitCode
        return
    }

    # Docker Compose writes normal progress to stderr. Windows PowerShell 5.1
    # turns that stream into NativeCommandError when ErrorActionPreference=Stop.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & docker @Arguments *> $null
        $script:LastDockerExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Get-DockerCommandOutput {
    param([string[]]$Arguments)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& docker @Arguments 2>$null)
        $script:LastDockerExitCode = $LASTEXITCODE
        return $output
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Test-DockerZhengfangAccess([string[]]$ComposeArguments) {
    $arguments = $ComposeArguments + @("run", "--rm", "--no-deps", "checker", "network-probe")
    Invoke-DockerCommand -Arguments $arguments -Quiet
    return $script:LastDockerExitCode -eq 0
}

$OriginalLocation = Get-Location
Set-Location $Root
try {
    Write-Host "`n=== 正方成绩检查服务：智能启动 ===" -ForegroundColor Cyan
    Show-StartupProgress 5 "检查 Docker Desktop 与项目运行环境"

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "未找到 Docker。请自行安装并启动 Docker Desktop：https://docs.docker.com/desktop/setup/install/windows-install/"
    }
    Invoke-DockerCommand -Arguments @("info") -Quiet
    if ($script:LastDockerExitCode -ne 0) {
        throw "Docker Desktop 尚未启动。请启动 Docker Desktop 后重试。"
    }
    Show-StartupProgress 12 "运行环境检查通过"
    if (-not (Test-Path ".\secrets\zf_username.txt")) {
        Show-StartupProgress 18 "首次运行：配置教务账号与微信推送"
        Write-Host "检测到首次运行，请按照提示完成账号和推送配置。" -ForegroundColor Yellow
        & ".\windows-setup.ps1"
        if ($LASTEXITCODE -ne 0) { throw "初始化失败。" }
    }
    else {
        Show-StartupProgress 18 "构建并检查成绩查询镜像"
        Invoke-DockerCommand -Arguments @("compose", "-f", $ComposeFile, "build", "checker") `
            -Status "构建成绩查询镜像" -StartPercent 18 -EndPercent 30
        if ($script:LastDockerExitCode -ne 0) { throw "成绩检查镜像构建失败。" }
    }
    Show-StartupProgress 30 "本地配置与成绩查询镜像准备完成"

    New-Item -ItemType Directory -Force -Path ".\runtime-data", ".\easyconnect-data" | Out-Null
    Remove-Item -LiteralPath $CaptchaFile, $AnswerFile, $ProbeSuccessFile -Force -ErrorAction SilentlyContinue

    $DirectComposeArguments = @("compose", "-f", ".\compose.easyconnect.yml")
    $HostComposeArguments = @(
        "compose", "-f", ".\compose.easyconnect.yml",
        "-f", ".\compose.host.yml"
    )
    $VpnComposeArguments = @(
        "compose", "-f", ".\compose.easyconnect.yml",
        "-f", ".\compose.vpn.yml", "--profile", "vpn"
    )
    $SelectedComposeArguments = $null
    $NetworkModeLabel = $null

    Invoke-DockerCommand -Arguments ($DirectComposeArguments + @("stop", "checker")) -Quiet

    $ZhengfangLoginUrl = Get-ZhengfangLoginUrl
    Show-StartupProgress 38 "检测 Windows 与 Docker 的教务网络"
    Write-Host "正在检测 Windows 宿主机能否访问正方教务..."
    if (Test-WindowsZhengfangAccess $ZhengfangLoginUrl) {
        Write-Host "宿主机已经可以访问正方，优先尝试 Docker 直连。" -ForegroundColor Green
        if (Test-DockerZhengfangAccess $DirectComposeArguments) {
            $SelectedComposeArguments = $DirectComposeArguments
            $NetworkModeLabel = "宿主机直连"
        }
        elseif (Test-DockerZhengfangAccess $HostComposeArguments) {
            $SelectedComposeArguments = $HostComposeArguments
            $NetworkModeLabel = "Docker Desktop Host 网络直连"
        }
        else {
            throw "Windows 宿主机可以访问正方，但 Docker 无法复用该网络。请在 Docker Desktop 的 Settings > Resources > Network 中启用 Host networking 后重试；为避免重复连接 VPN，本次不会启动 EasyConnect 容器。"
        }
    }
    else {
        Write-Host "宿主机当前无法直接访问正方，将检查容器 VPN。"
    }

    if ($null -ne $SelectedComposeArguments) {
        Write-Host "已选择$NetworkModeLabel，不启动 EasyConnect 容器。" -ForegroundColor Green
        Invoke-DockerCommand -Arguments ($VpnComposeArguments + @("stop", "easyconnect")) -Quiet
    }
    else {
        $EasyConnectContainer = (Get-DockerCommandOutput -Arguments ($VpnComposeArguments + @("ps", "-q", "easyconnect")) | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($EasyConnectContainer)) {
            Write-Host "检测到 EasyConnect 容器正在运行，正在验证现有 VPN 会话..."
            if (Test-DockerZhengfangAccess $VpnComposeArguments) {
                $SelectedComposeArguments = $VpnComposeArguments
                $NetworkModeLabel = "已连接的容器 VPN"
                Write-Host "现有容器 VPN 可用，将直接复用，不打开登录页面。" -ForegroundColor Green
            }
        }

        if ($null -eq $SelectedComposeArguments) {
            if (Get-Process -Name EasyConnect -ErrorAction SilentlyContinue) {
                Write-ChineseWarning "检测到 Windows 原生 EasyConnect，但它当前未能为 Docker 提供正方连接；将使用隔离的容器 VPN。"
            }
            Write-Host "容器 VPN 尚未连接，正在启动 EasyConnect..."
            Invoke-DockerCommand -Arguments ($VpnComposeArguments + @("up", "-d", "easyconnect")) `
                -Status "启动隔离的校园 VPN 容器" -StartPercent 42 -EndPercent 52
            if ($script:LastDockerExitCode -ne 0) { throw "EasyConnect 容器启动失败。" }

            $VncPassword = Get-ProjectSetting "EC_VNC_PASSWORD" "zfcheck"
            $EncodedPassword = [Uri]::EscapeDataString($VncPassword)
            Start-Process "http://127.0.0.1:18080/vnc.html?autoconnect=true&resize=scale&password=$EncodedPassword"
            $choice = [System.Windows.Forms.MessageBox]::Show(
                "请在刚打开的 EasyConnect 页面中登录 https://newvpn.cumt.edu.cn，并完成短信验证。`n`n显示 VPN 已连接后，点击【确定】继续。",
                "连接校园 VPN",
                [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            if ($choice -ne [System.Windows.Forms.DialogResult]::OK) {
                throw "用户取消了 VPN 登录。"
            }

            if (-not (Test-DockerZhengfangAccess $VpnComposeArguments)) {
                throw "容器 VPN 仍无法访问正方教务。请确认 EasyConnect 页面显示已连接。"
            }
            $SelectedComposeArguments = $VpnComposeArguments
            $NetworkModeLabel = "新连接的容器 VPN"
        }
    }

    Show-StartupProgress 52 "网络通道准备完成：$NetworkModeLabel"
    Show-StartupProgress 62 "验证$NetworkModeLabel"
    Write-Host "正在通过$NetworkModeLabel验证正方教务连接..."
    Invoke-DockerCommand -Arguments ($SelectedComposeArguments + @("run", "--rm", "--no-deps", "checker", "network-probe")) `
        -Status "验证教务系统网络连接" -StartPercent 62 -EndPercent 74
    if ($script:LastDockerExitCode -ne 0) {
        throw "所选网络模式无法访问正方教务，请重新运行启动程序。"
    }

    Show-StartupProgress 76 "验证正方教务账号登录"
    Write-Host "正在验证正方教务登录；如需验证码，将自动弹出输入窗口..."
    $arguments = $SelectedComposeArguments + @(
        "run", "--rm", "--no-deps", "-T",
        "-e", "ZF_CAPTCHA_INPUT_FILE=/data/captcha-answer.txt",
        "-e", "ZF_CAPTCHA_INPUT_TIMEOUT_SECONDS=300",
        "checker", "interactive-probe"
    )
    # Keep mutable state in a reference object. Invoke-DockerWithProgress calls
    # this block in a child scope under Windows PowerShell 5.1, where assigning
    # a plain outer variable can be lost and make one image open twice.
    $captchaState = [pscustomobject]@{
        LastHash = $null
        DialogOpen = $false
    }
    $captchaTick = {
        if (-not (Test-Path -LiteralPath $CaptchaFile)) {
            return
        }

        try { $hash = (Get-FileHash -LiteralPath $CaptchaFile -Algorithm SHA256).Hash }
        catch { $hash = $null }
        if ($hash -and $hash -ne $captchaState.LastHash -and -not $captchaState.DialogOpen) {
            $captchaState.LastHash = $hash
            $captchaState.DialogOpen = $true
            try {
                Write-Host "[验证码] 检测到新的验证码图片，正在打开输入窗口。" -ForegroundColor Yellow
                $answer = Show-CaptchaDialog $CaptchaFile
                if ([string]::IsNullOrWhiteSpace($answer)) {
                    Write-Utf8NoBom $AnswerFile "__CANCEL__"
                }
                else {
                    Write-Utf8NoBom $AnswerFile $answer
                    Write-Host "[验证码] 已提交本次输入，正在等待教务系统验证。" -ForegroundColor Green
                }
            }
            finally {
                # The image has been consumed. Removing it prevents the polling
                # loop from reopening the same file; a genuine retry writes a
                # new image and is allowed to open another dialog.
                Remove-Item -LiteralPath $CaptchaFile -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path -LiteralPath $CaptchaFile)) {
                    $captchaState.LastHash = $null
                }
                $captchaState.DialogOpen = $false
            }
        }
    }.GetNewClosure()
    $probeResult = Invoke-DockerWithProgress -Arguments $arguments `
        -Activity "正在启动正方成绩检查服务" -Status "登录正方教务并读取成绩" `
        -StartPercent 76 -EndPercent 89 -WorkingDirectory $Root -OnTick $captchaTick
    $probeSucceeded = Test-Path -LiteralPath $ProbeSuccessFile
    Remove-Item -LiteralPath $ProbeSuccessFile -Force -ErrorAction SilentlyContinue
    if (-not $probeSucceeded) {
        throw "正方登录验证失败。请查看上方日志后重新运行 windows-start.cmd。"
    }
    if ($probeResult.ExitCode -ne 0) {
        Write-ChineseWarning "正方验证已经成功，但 Docker 清理临时容器时返回了退出码 $($probeResult.ExitCode)；启动将继续。"
    }

    Show-StartupProgress 90 "启动后台成绩定时检查服务"
    Invoke-DockerCommand -Arguments ($SelectedComposeArguments + @("up", "-d", "--no-deps", "checker")) `
        -Status "启动后台成绩检查服务" -StartPercent 90 -EndPercent 99
    if ($script:LastDockerExitCode -ne 0) { throw "后台服务启动失败。" }

    Invoke-DockerCommand -Arguments ($SelectedComposeArguments + @("ps")) -Quiet
    Show-StartupProgress 100 "启动完成"
    Complete-StartupProgress
    Write-Host "`n启动完成，网络模式：$NetworkModeLabel。" -ForegroundColor Green
    Show-Info "启动完成。`n`n网络模式：$NetworkModeLabel。`n服务将在后台检查成绩；首次运行会推送全部成绩，之后无变化时保持静默。`n`nDocker Desktop 重启后，请再次双击 windows-start.cmd 手动启动。"
}
catch {
    Complete-StartupProgress
    Write-Host "`n启动失败：$($_.Exception.Message)" -ForegroundColor Red
    Show-ErrorMessage $_.Exception.Message
    exit 1
}
finally {
    Set-Location $OriginalLocation
}
