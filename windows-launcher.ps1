[CmdletBinding()]
param(
    [ValidateSet("Menu", "Start", "Stop", "Erase", "Logs", "FollowLogs")]
    [string]$Action = "Menu",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeFile = Join-Path $Root "compose.easyconnect.yml"
$CaptchaFile = Join-Path $Root "runtime-data\kaptcha.png"
$AnswerFile = Join-Path $Root "runtime-data\captcha-answer.txt"
$ProbeSuccessFile = Join-Path $Root "runtime-data\interactive-probe-success"
$ProbeErrorFile = Join-Path $Root "runtime-data\interactive-probe-error.txt"
$VpnServerAddress = "https://newvpn.cumt.edu.cn"
. (Join-Path $Root "windows-ui.ps1")

try {
    $Host.UI.RawUI.WindowTitle = "正方成绩检查服务启动器"
}
catch {
    # Some non-console hosts do not expose a writable window title.
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-TopMostMessageBox {
    param(
        [string]$Text,
        [string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons,
        [System.Windows.Forms.MessageBoxIcon]$Icon
    )

    $owner = [System.Windows.Forms.Form]::new()
    $owner.ShowInTaskbar = $false
    $owner.TopMost = $true
    $owner.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $owner.Size = [System.Drawing.Size]::new(1, 1)
    $owner.Opacity = 0
    try {
        $owner.Show()
        $owner.Activate()
        return [System.Windows.Forms.MessageBox]::Show(
            $owner, $Text, $Title, $Buttons, $Icon
        )
    }
    finally {
        $owner.Close()
        $owner.Dispose()
    }
}

function Show-Info([string]$Text, [string]$Title = "成绩检查服务") {
    Show-TopMostMessageBox -Text $Text -Title $Title `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-ErrorMessage([string]$Text) {
    $readableText = ConvertTo-ReadableText $Text
    Show-TopMostMessageBox -Text $readableText -Title "启动失败" `
        -Buttons ([System.Windows.Forms.MessageBoxButtons]::OK) `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

function Confirm-VpnLoginInstructions([string]$VpnAddress) {
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "校园 VPN 登录注意事项"
    $form.ClientSize = [System.Drawing.Size]::new(590, 330)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.TopMost = $true
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    $intro = [System.Windows.Forms.Label]::new()
    $intro.Text = "接下来将打开本机专用的 EasyConnect 登录页面。"
    $intro.AutoSize = $true
    $intro.Location = [System.Drawing.Point]::new(20, 20)
    $form.Controls.Add($intro)

    $steps = [System.Windows.Forms.Label]::new()
    $steps.Text = "请按以下顺序操作：`r`n1. 复制下方地址并在 EasyConnect 中登录；`r`n2. 完成手机短信验证；`r`n3. 等待页面明确显示 VPN 已连接。"
    $steps.AutoSize = $true
    $steps.Location = [System.Drawing.Point]::new(20, 55)
    $form.Controls.Add($steps)

    $addressLabel = [System.Windows.Forms.Label]::new()
    $addressLabel.Text = "校园 VPN 地址（可选中复制）："
    $addressLabel.AutoSize = $true
    $addressLabel.Location = [System.Drawing.Point]::new(20, 135)
    $form.Controls.Add($addressLabel)

    $addressBox = [System.Windows.Forms.TextBox]::new()
    $addressBox.Text = $VpnAddress
    $addressBox.ReadOnly = $true
    $addressBox.Location = [System.Drawing.Point]::new(20, 158)
    $addressBox.Size = [System.Drawing.Size]::new(420, 27)
    $form.Controls.Add($addressBox)

    $copyButton = [System.Windows.Forms.Button]::new()
    $copyButton.Text = "复制地址"
    $copyButton.Location = [System.Drawing.Point]::new(450, 156)
    $copyButton.Size = [System.Drawing.Size]::new(115, 30)
    $form.Controls.Add($copyButton)

    $copyStatus = [System.Windows.Forms.Label]::new()
    $copyStatus.Text = "也可以在终端中找到同一地址。"
    $copyStatus.AutoSize = $true
    $copyStatus.Location = [System.Drawing.Point]::new(20, 192)
    $form.Controls.Add($copyStatus)

    $notice = [System.Windows.Forms.Label]::new()
    $notice.Text = "连接成功后无需返回寻找确认按钮，也不要关闭启动器。`r`n启动器会自动检测连接，并在成功后继续运行。"
    $notice.AutoSize = $true
    $notice.Location = [System.Drawing.Point]::new(20, 220)
    $form.Controls.Add($notice)

    $openButton = [System.Windows.Forms.Button]::new()
    $openButton.Text = "打开登录页面"
    $openButton.Location = [System.Drawing.Point]::new(315, 278)
    $openButton.Size = [System.Drawing.Size]::new(125, 34)
    $openButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($openButton)

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Text = "取消"
    $cancelButton.Location = [System.Drawing.Point]::new(450, 278)
    $cancelButton.Size = [System.Drawing.Size]::new(115, 34)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $copyButton.Add_Click({
        try {
            $addressBox.SelectAll()
            $addressBox.Copy()
            $copyStatus.Text = "地址已复制到剪贴板。"
        }
        catch {
            $copyStatus.Text = "自动复制失败，请选中地址后按 Ctrl+C。"
        }
    }.GetNewClosure())

    $form.AcceptButton = $openButton
    $form.CancelButton = $cancelButton
    $form.ActiveControl = $openButton
    try {
        return $form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK
    }
    finally {
        $form.Dispose()
    }
}

function Show-LoginRecoveryDialog {
    param(
        [string]$Username,
        [string]$Password,
        [string]$ErrorText
    )

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "正方教务登录未成功"
    $form.ClientSize = [System.Drawing.Size]::new(620, 390)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.TopMost = $true
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

    $heading = [System.Windows.Forms.Label]::new()
    $heading.Text = "登录验证失败，请选择下一步操作。"
    $heading.AutoSize = $true
    $heading.Location = [System.Drawing.Point]::new(20, 18)
    $form.Controls.Add($heading)

    $errorBox = [System.Windows.Forms.TextBox]::new()
    $errorBox.Text = (ConvertTo-ReadableText $ErrorText)
    $errorBox.ReadOnly = $true
    $errorBox.Multiline = $true
    $errorBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $errorBox.Location = [System.Drawing.Point]::new(20, 45)
    $errorBox.Size = [System.Drawing.Size]::new(580, 85)
    $form.Controls.Add($errorBox)

    $accountLabel = [System.Windows.Forms.Label]::new()
    $accountLabel.Text = "当前学号："
    $accountLabel.AutoSize = $true
    $accountLabel.Location = [System.Drawing.Point]::new(20, 150)
    $form.Controls.Add($accountLabel)

    $accountBox = [System.Windows.Forms.TextBox]::new()
    $accountBox.Text = $Username
    $accountBox.ReadOnly = $true
    $accountBox.Location = [System.Drawing.Point]::new(120, 146)
    $accountBox.Size = [System.Drawing.Size]::new(300, 27)
    $form.Controls.Add($accountBox)

    $passwordLabel = [System.Windows.Forms.Label]::new()
    $passwordLabel.Text = "当前密码："
    $passwordLabel.AutoSize = $true
    $passwordLabel.Location = [System.Drawing.Point]::new(20, 190)
    $form.Controls.Add($passwordLabel)

    $passwordBox = [System.Windows.Forms.TextBox]::new()
    $passwordBox.Text = $Password
    $passwordBox.ReadOnly = $true
    $passwordBox.UseSystemPasswordChar = $true
    $passwordBox.Location = [System.Drawing.Point]::new(120, 186)
    $passwordBox.Size = [System.Drawing.Size]::new(300, 27)
    $form.Controls.Add($passwordBox)

    $showPassword = [System.Windows.Forms.CheckBox]::new()
    $showPassword.Text = "显示密码"
    $showPassword.AutoSize = $true
    $showPassword.Location = [System.Drawing.Point]::new(440, 188)
    $form.Controls.Add($showPassword)

    $help = [System.Windows.Forms.Label]::new()
    $help.Text = "验证码不清楚或输入错误时，可重新获取并输入验证码。`r`n账号或密码有误时，请选择【更改账号密码】。"
    $help.AutoSize = $true
    $help.Location = [System.Drawing.Point]::new(20, 235)
    $form.Controls.Add($help)

    $retryButton = [System.Windows.Forms.Button]::new()
    $retryButton.Text = "重新输入验证码"
    $retryButton.Location = [System.Drawing.Point]::new(145, 325)
    $retryButton.Size = [System.Drawing.Size]::new(140, 38)
    $retryButton.DialogResult = [System.Windows.Forms.DialogResult]::Retry
    $form.Controls.Add($retryButton)

    $changeButton = [System.Windows.Forms.Button]::new()
    $changeButton.Text = "更改账号密码"
    $changeButton.Location = [System.Drawing.Point]::new(295, 325)
    $changeButton.Size = [System.Drawing.Size]::new(140, 38)
    $changeButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $form.Controls.Add($changeButton)

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Text = "取消启动"
    $cancelButton.Location = [System.Drawing.Point]::new(445, 325)
    $cancelButton.Size = [System.Drawing.Size]::new(120, 38)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $showPassword.Add_CheckedChanged({
        $passwordBox.UseSystemPasswordChar = -not $showPassword.Checked
    }.GetNewClosure())

    $form.AcceptButton = $retryButton
    $form.CancelButton = $cancelButton
    $form.ActiveControl = $retryButton
    try {
        $result = $form.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::Retry) { return "Retry" }
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { return "Change" }
        return "Cancel"
    }
    finally {
        $form.Dispose()
    }
}

function Show-CredentialsDialog {
    param(
        [string]$Username,
        [string]$Password
    )

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "更改正方教务账号密码"
    $form.ClientSize = [System.Drawing.Size]::new(530, 250)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.TopMost = $true

    $accountLabel = [System.Windows.Forms.Label]::new()
    $accountLabel.Text = "正方教务学号："
    $accountLabel.AutoSize = $true
    $accountLabel.Location = [System.Drawing.Point]::new(22, 32)
    $form.Controls.Add($accountLabel)

    $accountBox = [System.Windows.Forms.TextBox]::new()
    $accountBox.Text = $Username
    $accountBox.Location = [System.Drawing.Point]::new(150, 28)
    $accountBox.Size = [System.Drawing.Size]::new(345, 27)
    $form.Controls.Add($accountBox)

    $passwordLabel = [System.Windows.Forms.Label]::new()
    $passwordLabel.Text = "正方教务密码："
    $passwordLabel.AutoSize = $true
    $passwordLabel.Location = [System.Drawing.Point]::new(22, 82)
    $form.Controls.Add($passwordLabel)

    $passwordBox = [System.Windows.Forms.TextBox]::new()
    $passwordBox.Text = $Password
    $passwordBox.UseSystemPasswordChar = $true
    $passwordBox.Location = [System.Drawing.Point]::new(150, 78)
    $passwordBox.Size = [System.Drawing.Size]::new(345, 27)
    $form.Controls.Add($passwordBox)

    $showPassword = [System.Windows.Forms.CheckBox]::new()
    $showPassword.Text = "显示密码"
    $showPassword.AutoSize = $true
    $showPassword.Location = [System.Drawing.Point]::new(150, 115)
    $form.Controls.Add($showPassword)

    $validation = [System.Windows.Forms.Label]::new()
    $validation.Text = "保存后会立即使用新凭据重新验证，不会删除成绩基线。"
    $validation.AutoSize = $true
    $validation.Location = [System.Drawing.Point]::new(22, 155)
    $form.Controls.Add($validation)

    $saveButton = [System.Windows.Forms.Button]::new()
    $saveButton.Text = "保存并重新验证"
    $saveButton.Location = [System.Drawing.Point]::new(270, 195)
    $saveButton.Size = [System.Drawing.Size]::new(145, 36)
    $saveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($saveButton)

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Text = "返回"
    $cancelButton.Location = [System.Drawing.Point]::new(425, 195)
    $cancelButton.Size = [System.Drawing.Size]::new(70, 36)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $showPassword.Add_CheckedChanged({
        $passwordBox.UseSystemPasswordChar = -not $showPassword.Checked
    }.GetNewClosure())

    $form.AcceptButton = $saveButton
    $form.CancelButton = $cancelButton
    $form.ActiveControl = $accountBox
    try {
        while ($true) {
            $result = $form.ShowDialog()
            if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
            $newUsername = $accountBox.Text.Trim()
            $newPassword = $passwordBox.Text
            if (-not [string]::IsNullOrWhiteSpace($newUsername) -and -not [string]::IsNullOrEmpty($newPassword)) {
                return [pscustomobject]@{
                    Username = $newUsername
                    Password = $newPassword
                }
            }
            $validation.Text = "学号和密码不能为空，请补充后重新保存。"
            $validation.ForeColor = [System.Drawing.Color]::Firebrick
            $form.DialogResult = [System.Windows.Forms.DialogResult]::None
            $form.ActiveControl = $accountBox
        }
    }
    finally {
        $form.Dispose()
    }
}

function Read-Utf8Secret([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Trim()
}

function Get-InteractiveProbeFailureMessage($ProbeResult) {
    if (Test-Path -LiteralPath $ProbeErrorFile) {
        $message = (Get-Content -LiteralPath $ProbeErrorFile -Raw -Encoding UTF8).Trim()
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            return ConvertTo-ReadableText $message
        }
    }
    return "正方教务未接受本次登录。请检查验证码、学号和密码。"
}

function Show-StartupProgress([int]$Percent, [string]$Status) {
    Write-RunningStatus $Status
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

function Invoke-StartAction {
    $actionSucceeded = $false
    $OriginalLocation = Get-Location
    Set-Location $Root
    try {
    Clear-Host
    Write-LauncherTitle "`n正方成绩检查服务 · 智能启动"
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
        Write-WaitingStatus "首次运行，请完成教务账号与微信推送配置"
        & ".\windows-setup.ps1"
        if ($LASTEXITCODE -ne 0) { throw "初始化失败。" }
    }
    else {
        Show-StartupProgress 18 "构建并检查成绩查询镜像"
        $buildResult = Invoke-CheckerBuildWithFallback `
            -ComposeFile $ComposeFile -WorkingDirectory $Root `
            -Activity "正在启动正方成绩检查服务" `
            -StartPercent 18 -EndPercent 30
        if ($buildResult.ExitCode -ne 0) {
            throw "成绩检查镜像构建失败；已完成自动重试和备用源切换。"
        }
    }
    Show-StartupProgress 30 "本地配置与成绩查询镜像准备完成"

    New-Item -ItemType Directory -Force -Path ".\runtime-data", ".\easyconnect-data" | Out-Null
    Remove-Item -LiteralPath $CaptchaFile, $AnswerFile, $ProbeSuccessFile, $ProbeErrorFile `
        -Force -ErrorAction SilentlyContinue

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
    if (Test-WindowsZhengfangAccess $ZhengfangLoginUrl) {
        Write-SuccessStatus "Windows 宿主机可访问正方教务"
        Show-StartupProgress 42 "验证 Docker 直连教务网络"
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
        Write-SuccessStatus "Windows 网络检测完成，将检查隔离的容器 VPN"
    }

    if ($null -ne $SelectedComposeArguments) {
        Write-SuccessStatus "已选择$NetworkModeLabel，不需要启动 EasyConnect"
        Invoke-DockerCommand -Arguments ($VpnComposeArguments + @("stop", "easyconnect")) -Quiet
    }
    else {
        $EasyConnectContainer = (Get-DockerCommandOutput -Arguments ($VpnComposeArguments + @("ps", "-q", "easyconnect")) | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($EasyConnectContainer)) {
            Show-StartupProgress 44 "验证现有容器 VPN 会话"
            if (Test-DockerZhengfangAccess $VpnComposeArguments) {
                $SelectedComposeArguments = $VpnComposeArguments
                $NetworkModeLabel = "已连接的容器 VPN"
                Write-SuccessStatus "现有容器 VPN 可用，将直接复用且不打开登录页面"
            }
            else {
                Write-SuccessStatus "现有容器 VPN 检查完成，需要重新建立连接"
            }
        }

        if ($null -eq $SelectedComposeArguments) {
            if (Get-Process -Name EasyConnect -ErrorAction SilentlyContinue) {
                Write-ChineseWarning "检测到 Windows 原生 EasyConnect，但它当前未能为 Docker 提供正方连接；将使用隔离的容器 VPN。"
            }
            Invoke-DockerCommand -Arguments ($VpnComposeArguments + @("up", "-d", "easyconnect")) `
                -Status "启动隔离的校园 VPN 容器" -StartPercent 42 -EndPercent 52
            if ($script:LastDockerExitCode -ne 0) { throw "EasyConnect 容器启动失败。" }

            $VncPassword = Get-ProjectSetting "EC_VNC_PASSWORD" "zfcheck"
            $EncodedPassword = [Uri]::EscapeDataString($VncPassword)
            Write-WaitingStatus "需要登录校园 VPN，请确认操作说明"
            Write-Host "校园 VPN 地址：$VpnServerAddress"
            Write-Host "可在弹窗中点击【复制地址】，也可以直接复制终端中的地址。"
            if (-not (Confirm-VpnLoginInstructions -VpnAddress $VpnServerAddress)) {
                throw "用户取消了 VPN 登录。"
            }
            Start-Process "http://127.0.0.1:18080/vnc.html?autoconnect=true&resize=scale&password=$EncodedPassword"
            Write-WaitingStatus "请在浏览器完成 VPN 登录和短信验证；连接成功后将自动继续"
            Write-Host "无需返回寻找确认按钮。最长等待 10 分钟，按 Ctrl+C 可以取消。"
            $vpnDeadline = [DateTime]::UtcNow.AddMinutes(10)
            $vpnConnected = $false
            while ([DateTime]::UtcNow -lt $vpnDeadline) {
                Start-Sleep -Seconds 5
                if (Test-DockerZhengfangAccess $VpnComposeArguments) {
                    $vpnConnected = $true
                    break
                }
            }
            if (-not $vpnConnected) {
                throw "等待容器 VPN 连接超时。请确认 EasyConnect 页面已显示连接成功，然后重新启动。"
            }
            Show-StartupProgress 52 "已自动识别校园 VPN 连接"
            $SelectedComposeArguments = $VpnComposeArguments
            $NetworkModeLabel = "新连接的容器 VPN"
        }
    }

    Show-StartupProgress 52 "网络通道准备完成：$NetworkModeLabel"
    Show-StartupProgress 62 "验证$NetworkModeLabel"
    Invoke-DockerCommand -Arguments ($SelectedComposeArguments + @("run", "--rm", "--no-deps", "checker", "network-probe")) `
        -Status "验证教务系统网络连接" -StartPercent 62 -EndPercent 74
    if ($script:LastDockerExitCode -ne 0) {
        throw "所选网络模式无法访问正方教务，请重新运行启动程序。"
    }

    Write-Host "如教务系统要求图片验证码，将自动显示输入窗口。"
    $forceFreshLogin = $false
    while ($true) {
        Show-StartupProgress 76 "验证正方教务账号登录"
        Remove-Item -LiteralPath $CaptchaFile, $AnswerFile, $ProbeSuccessFile, $ProbeErrorFile `
            -Force -ErrorAction SilentlyContinue

        $arguments = $SelectedComposeArguments + @(
            "run", "--rm", "--no-deps", "-T",
            "-e", "ZF_CAPTCHA_INPUT_FILE=/data/captcha-answer.txt",
            "-e", "ZF_CAPTCHA_INPUT_TIMEOUT_SECONDS=300"
        )
        if ($forceFreshLogin) {
            $arguments += @("-e", "ZF_FORCE_LOGIN=1")
        }
        $arguments += @("checker", "interactive-probe")

        # Keep mutable state in a reference object. Invoke-DockerWithProgress
        # calls this block in a child scope under Windows PowerShell 5.1.
        $captchaState = [pscustomobject]@{
            LastHash = $null
            DialogOpen = $false
        }
        $captchaTick = {
            if (-not (Test-Path -LiteralPath $CaptchaFile)) { return }

            try { $hash = (Get-FileHash -LiteralPath $CaptchaFile -Algorithm SHA256).Hash }
            catch { $hash = $null }
            if ($hash -and $hash -ne $captchaState.LastHash -and -not $captchaState.DialogOpen) {
                $captchaState.LastHash = $hash
                $captchaState.DialogOpen = $true
                try {
                    Clear-LiveProgress "验证码输入"
                    Write-WaitingStatus "请在弹出的窗口中输入正方教务验证码"
                    $answer = Show-CaptchaDialog $CaptchaFile
                    if ([string]::IsNullOrWhiteSpace($answer)) {
                        Write-Utf8NoBom $AnswerFile "__CANCEL__"
                    }
                    else {
                        Write-Utf8NoBom $AnswerFile $answer
                        Write-Host "验证码已提交，正在等待教务系统验证。"
                    }
                }
                finally {
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
        if ($probeSucceeded) {
            Remove-Item -LiteralPath $ProbeErrorFile -Force -ErrorAction SilentlyContinue
            if ($probeResult.ExitCode -ne 0) {
                Write-ChineseWarning "正方验证已经成功，但 Docker 清理临时容器时返回了退出码 $($probeResult.ExitCode)；启动将继续。"
            }
            break
        }

        $failureMessage = Get-InteractiveProbeFailureMessage $probeResult
        $usernamePath = Join-Path $Root "secrets\zf_username.txt"
        $passwordPath = Join-Path $Root "secrets\zf_password.txt"
        $currentUsername = Read-Utf8Secret $usernamePath
        $currentPassword = Read-Utf8Secret $passwordPath
        Write-WaitingStatus "正方登录未成功，请在弹窗中选择重试或更改账号密码"

        while ($true) {
            $recoveryAction = Show-LoginRecoveryDialog `
                -Username $currentUsername -Password $currentPassword `
                -ErrorText $failureMessage
            if ($recoveryAction -eq "Retry") {
                $forceFreshLogin = $true
                Write-WaitingStatus "正在获取新的验证码并重新验证"
                break
            }
            if ($recoveryAction -eq "Change") {
                $credentials = Show-CredentialsDialog `
                    -Username $currentUsername -Password $currentPassword
                if ($null -eq $credentials) { continue }

                Write-Utf8NoBom $usernamePath $credentials.Username
                Write-Utf8NoBom $passwordPath $credentials.Password
                $currentUsername = $credentials.Username
                $currentPassword = $credentials.Password
                $forceFreshLogin = $true
                Write-SuccessStatus "账号密码已更新，将立即重新验证"
                break
            }

            Remove-Item -LiteralPath $CaptchaFile, $AnswerFile, $ProbeErrorFile `
                -Force -ErrorAction SilentlyContinue
            Write-WaitingStatus "已取消启动；账号、密码和成绩基线均已保留"
            return $false
        }
    }

    Show-StartupProgress 90 "启动后台成绩定时检查服务"
    Invoke-DockerCommand -Arguments ($SelectedComposeArguments + @("up", "-d", "--no-deps", "checker")) `
        -Status "启动后台成绩检查服务" -StartPercent 90 -EndPercent 99
    if ($script:LastDockerExitCode -ne 0) { throw "后台服务启动失败。" }

    Invoke-DockerCommand -Arguments ($SelectedComposeArguments + @("ps")) -Quiet
    Complete-StartupProgress
    Write-SuccessStatus "启动完成，网络模式：$NetworkModeLabel"
        Show-Info "启动完成。`n`n网络模式：$NetworkModeLabel。`n服务将在后台检查成绩；首次运行会推送全部成绩，之后无变化时保持静默。`n`nDocker Desktop 重启后，请再次双击 windows-launcher.cmd 手动启动。"
        $actionSucceeded = $true
    }
    catch {
        Complete-StartupProgress
        Write-FailureStatus "启动失败：$($_.Exception.Message)"
        Show-ErrorMessage $_.Exception.Message
    }
    finally {
        Set-Location $OriginalLocation
    }
    return $actionSucceeded
}

function Show-ActionStage([int]$Percent, [string]$Status) {
    Write-RunningStatus $Status
}

function Invoke-StopAction {
    $actionSucceeded = $false
    $OriginalLocation = Get-Location
    Set-Location $Root
    try {
        Clear-Host
        Write-LauncherTitle "`n正方成绩检查服务 · 安全停止"
        Show-ActionStage 10 "检查 Docker Desktop 与项目配置"
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            throw "未找到 Docker。请先安装并启动 Docker Desktop。"
        }
        Invoke-DockerCommand -Arguments @("info") -Quiet
        if ($script:LastDockerExitCode -ne 0) {
            throw "Docker Desktop 尚未启动。"
        }

        Show-ActionStage 30 "停止成绩检查器与校园 VPN 容器"
        $stopResult = Invoke-DockerWithProgress `
            -Arguments @("compose", "-f", $ComposeFile, "--profile", "vpn", "down") `
            -Activity "正在停止正方成绩检查服务" -Status "停止并移除项目容器与网络" `
            -StartPercent 30 -EndPercent 95 -WorkingDirectory $Root
        if ($stopResult.ExitCode -ne 0) {
            throw "容器停止失败，请查看上方诊断信息。"
        }

        Write-SuccessStatus "服务已停止；账号、登录会话和成绩基线均已保留"
        $actionSucceeded = $true
    }
    catch {
        Write-FailureStatus "停止失败：$($_.Exception.Message)"
    }
    finally {
        Set-Location $OriginalLocation
    }
    return $actionSucceeded
}

function Assert-SafeGeneratedPath([string]$Path) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $pathFull = [IO.Path]::GetFullPath($Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if (
        $pathFull -eq $rootFull -or
        -not $pathFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "拒绝删除项目目录之外的路径：$pathFull"
    }
    return $pathFull
}

function Remove-GeneratedPath([string]$Path) {
    $safePath = Assert-SafeGeneratedPath $Path
    if (Test-Path -LiteralPath $safePath) {
        Remove-Item -LiteralPath $safePath -Recurse -Force
        Write-Host "  已删除：$($safePath.Substring($Root.Length).TrimStart('\'))"
    }
}

function Ensure-ComposeSecretPlaceholders {
    $secretsPath = Assert-SafeGeneratedPath (Join-Path $Root "secrets")
    New-Item -ItemType Directory -Path $secretsPath -Force | Out-Null
    foreach ($name in @("zf_username.txt", "zf_password.txt", "push_token.txt")) {
        $secretPath = Join-Path $secretsPath $name
        if (-not (Test-Path -LiteralPath $secretPath)) {
            [IO.File]::WriteAllText($secretPath, "", [Text.UTF8Encoding]::new($false))
        }
    }
}

function Invoke-EraseAction([switch]$SkipConfirmation) {
    $actionSucceeded = $false
    $OriginalLocation = Get-Location
    Set-Location $Root
    try {
        Clear-Host
        Write-LauncherTitle "`n正方成绩检查服务 · 隐私清除"
        Write-WaitingStatus "请阅读并确认隐私数据清理范围"
        Write-Host "此操作会将工作目录恢复到刚克隆后的状态，并删除："
        Write-Host "  - 正方账号、密码和 ShowDoc Push Token"
        Write-Host "  - 正方登录会话、成绩基线、验证码、日志和故障状态"
        Write-Host "  - EasyConnect 登录配置、短信验证会话和 VPN 缓存"
        Write-Host "  - 本地 .env 配置、Python/测试缓存"
        Write-Host "  - 本项目的 Docker 容器、网络和服务镜像"
        Write-Host "`n不会删除：Git 仓库、项目源代码、Docker Desktop 或其他项目的数据。"
        Write-ChineseWarning "该操作不可撤销。再次启动时需要重新输入全部凭据并完成所有验证。"

        if (-not $SkipConfirmation) {
            $confirmation = ([string](Read-Host "确认永久清除请输入 ERASE（不区分大小写）")).Trim()
            if ($confirmation -ne "ERASE") {
                Write-WaitingStatus "已取消，未删除任何数据"
                return $true
            }
        }

        $dockerCleanupIncomplete = $false
        Show-ActionStage 10 "检查 Docker Desktop 与项目资源"
        $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
        if ($dockerCommand) {
            Invoke-DockerCommand -Arguments @("info") -Quiet
            if ($script:LastDockerExitCode -eq 0) {
                Ensure-ComposeSecretPlaceholders
                Show-ActionStage 25 "停止本项目的所有容器"
                $stopResult = Invoke-DockerWithProgress `
                    -Arguments @("compose", "-f", $ComposeFile, "--profile", "vpn", "stop") `
                    -Activity "正在清除隐私数据并重置项目" -Status "停止本项目的所有容器" `
                    -StartPercent 25 -EndPercent 42 -WorkingDirectory $Root
                if ($stopResult.ExitCode -ne 0) {
                    throw "本项目容器未能全部停止。为避免运行中的服务继续读写数据，本次未清除任何隐私文件。"
                }

                Show-ActionStage 45 "删除项目容器、网络和服务镜像"
                $removeResult = Invoke-DockerWithProgress `
                    -Arguments @(
                        "compose", "-f", $ComposeFile, "--profile", "vpn", "down",
                        "--remove-orphans", "--volumes", "--rmi", "all"
                    ) `
                    -Activity "正在清除隐私数据并重置项目" -Status "删除项目容器、网络和服务镜像" `
                    -StartPercent 45 -EndPercent 62 -WorkingDirectory $Root
                if ($removeResult.ExitCode -ne 0) {
                    $dockerCleanupIncomplete = $true
                    Write-ChineseWarning "Docker 资源未能全部删除；仍将继续清除本地隐私文件。"
                }
            }
            else {
                $dockerCleanupIncomplete = $true
                Write-ChineseWarning "Docker Desktop 未运行，暂时无法删除项目容器、网络和镜像。"
            }
        }

        Show-ActionStage 65 "删除本地账号、会话、成绩与配置数据"
        Suspend-RunningStatus
        $generatedPaths = @(
            (Join-Path $Root "secrets"),
            (Join-Path $Root "runtime-data"),
            (Join-Path $Root "easyconnect-data"),
            (Join-Path $Root ".env"),
            (Join-Path $Root ".env.poc"),
            (Join-Path $Root ".pytest_cache"),
            (Join-Path $Root ".coverage"),
            (Join-Path $Root "coverage.xml"),
            (Join-Path $Root "htmlcov"),
            (Join-Path $Root "kaptcha.png"),
            (Join-Path $Root "login-debug.log")
        )
        foreach ($path in $generatedPaths) {
            Remove-GeneratedPath $path
        }
        foreach ($directoryName in @("scripts", "tests", "zfcheck")) {
            $sourcePath = Join-Path $Root $directoryName
            if (-not (Test-Path -LiteralPath $sourcePath)) { continue }
            Get-ChildItem -LiteralPath $sourcePath -Directory -Filter "__pycache__" -Recurse -Force |
                Sort-Object FullName -Descending |
                ForEach-Object { Remove-GeneratedPath $_.FullName }
            Get-ChildItem -LiteralPath $sourcePath -File -Filter "*.pyc" -Recurse -Force |
                ForEach-Object { Remove-GeneratedPath $_.FullName }
        }

        Show-ActionStage 95 "核对隐私数据清理结果"
        if ($dockerCleanupIncomplete) {
            Write-ChineseWarning "本地隐私文件已删除，但 Docker 资源清理未完成。启动 Docker Desktop 后请再次运行清理。"
            return $false
        }

        Write-SuccessStatus "隐私数据已全部清除，项目已恢复到刚克隆后的状态"
        $actionSucceeded = $true
    }
    catch {
        Write-FailureStatus "清理失败：$($_.Exception.Message)"
    }
    finally {
        Set-Location $OriginalLocation
    }
    return $actionSucceeded
}

function Invoke-LogsAction {
    param(
        [switch]$Follow,
        [switch]$AskService
    )

    $OriginalLocation = Get-Location
    Set-Location $Root
    try {
        Clear-Host
        Write-LauncherTitle "`n正方成绩检查服务 · 运行日志"
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            throw "未找到 Docker。请先安装并启动 Docker Desktop。"
        }
        Invoke-DockerCommand -Arguments @("info") -Quiet
        if ($script:LastDockerExitCode -ne 0) {
            throw "Docker Desktop 尚未启动。"
        }

        $services = @("checker")
        if ($AskService) {
            Write-Host "[1] 成绩检查服务日志（推荐）"
            Write-Host "[2] 校园 VPN 日志"
            Write-Host "[3] 两个服务的全部日志"
            Write-Host "[0] 返回主菜单"
            Write-WaitingStatus "请选择需要查看的日志"
            $logChoice = ([string](Read-Host "请输入编号")).Trim()
            switch ($logChoice) {
                "0" { return $true }
                "2" { $services = @("easyconnect") }
                "3" { $services = @("checker", "easyconnect") }
                default { $services = @("checker") }
            }
        }

        $modeText = if ($Follow) { "实时日志" } else { "最近 120 行日志" }
        Write-RunningStatus "正在显示$modeText"
        if ($Follow) {
            Write-WaitingStatus "按 Ctrl+C 可停止跟踪并返回启动器"
        }
        $arguments = @("compose", "-f", $ComposeFile, "--profile", "vpn", "logs", "--no-color", "--tail", "120")
        if ($Follow) { $arguments += "--follow" }
        $arguments += $services
        Suspend-RunningStatus

        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            # Convert the native success stream to host output so callers can
            # capture the Boolean result without swallowing the log lines.
            & docker @arguments 2>&1 | ForEach-Object {
                Write-Host ([string]$_)
            }
            $logExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($logExitCode -ne 0 -and -not $Follow) {
            throw "日志读取失败。服务可能尚未启动，或对应容器已经被删除。"
        }
        Complete-RunningStatus "$modeText已结束"
        return $true
    }
    catch {
        Write-FailureStatus "日志查询失败：$($_.Exception.Message)"
        return $false
    }
    finally {
        Set-Location $OriginalLocation
    }
}

function Wait-ForMenuReturn {
    Write-Host ""
    Read-Host "按 Enter 返回主菜单" | Out-Null
}

function Show-LauncherMenu {
    while ($true) {
        Clear-Host
        Write-LauncherTitle "========================================"
        Write-LauncherTitle "       正方成绩检查服务启动器"
        Write-LauncherTitle "========================================"
        Write-Host "[1] 启动或恢复服务"
        Write-Host "[2] 停止服务"
        Write-Host "[3] 查看最近日志"
        Write-Host "[4] 实时跟踪日志"
        Write-Host "[5] 清除全部隐私数据并重置"
        Write-Host "[0] 退出"
        Write-Host ""
        Write-WaitingStatus "请选择需要执行的操作"
        $choice = ([string](Read-Host "请输入编号")).Trim()
        switch ($choice) {
            "1" { $null = Invoke-StartAction; Wait-ForMenuReturn }
            "2" { $null = Invoke-StopAction; Wait-ForMenuReturn }
            "3" { $null = Invoke-LogsAction -AskService; Wait-ForMenuReturn }
            "4" { $null = Invoke-LogsAction -AskService -Follow; Wait-ForMenuReturn }
            "5" { $null = Invoke-EraseAction; Wait-ForMenuReturn }
            "0" { return }
            default {
                Write-WaitingStatus "无效选项，请输入 0 到 5"
                Start-Sleep -Seconds 1
            }
        }
    }
}

$result = $true
switch ($Action) {
    "Start" { $result = Invoke-StartAction }
    "Stop" { $result = Invoke-StopAction }
    "Erase" { $result = Invoke-EraseAction -SkipConfirmation:$Force }
    "Logs" { $result = Invoke-LogsAction }
    "FollowLogs" { $result = Invoke-LogsAction -Follow }
    default { Show-LauncherMenu; $result = $true }
}

if (-not $result) {
    exit 1
}
