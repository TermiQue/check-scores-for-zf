[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeFile = Join-Path $Root "compose.easyconnect.yml"
$CaptchaFile = Join-Path $Root "runtime-data\kaptcha.png"
$AnswerFile = Join-Path $Root "runtime-data\captcha-answer.txt"
$ProbeSuccessFile = Join-Path $Root "runtime-data\interactive-probe-success"

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
    $form.Add_Shown({ $input.Focus() })

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

$OriginalLocation = Get-Location
Set-Location $Root
try {
    Write-Host "`n=== 正方成绩检查服务 ===" -ForegroundColor Cyan
    Write-Host "正在检查运行环境..."

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "未找到 Docker。请先安装并启动 Docker Desktop。"
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Desktop 尚未启动。请启动 Docker Desktop 后重试。"
    }
    if (Get-Process -Name EasyConnect -ErrorAction SilentlyContinue) {
        throw "检测到 Windows 原生 EasyConnect。请从系统托盘完全退出后重试。"
    }

    if (-not (Test-Path ".\secrets\zf_username.txt")) {
        Write-Host "这是首次运行，先完成账号和推送配置。" -ForegroundColor Yellow
        & ".\windows-setup.ps1"
        if ($LASTEXITCODE -ne 0) { throw "初始化失败。" }
    }
    else {
        Write-Host "正在检查成绩检查镜像..."
        docker compose -f $ComposeFile build checker
        if ($LASTEXITCODE -ne 0) { throw "成绩检查镜像构建失败。" }
    }

    New-Item -ItemType Directory -Force -Path ".\runtime-data", ".\easyconnect-data" | Out-Null
    Remove-Item -LiteralPath $CaptchaFile, $AnswerFile, $ProbeSuccessFile -Force -ErrorAction SilentlyContinue

    Write-Host "正在启动 EasyConnect 容器..."
    docker compose -f $ComposeFile up -d easyconnect
    if ($LASTEXITCODE -ne 0) { throw "EasyConnect 容器启动失败。" }
    docker compose -f $ComposeFile stop checker *> $null

    Start-Sleep -Seconds 2
    docker compose -f $ComposeFile exec -T easyconnect sh -c "test -d /sys/class/net/tun0" *> $null
    if ($LASTEXITCODE -ne 0) {
        $VncPassword = "zfcheck"
        if (Test-Path ".env") {
            foreach ($line in Get-Content -LiteralPath ".env") {
                if ($line -match '^\s*EC_VNC_PASSWORD\s*=\s*(.*?)\s*$') {
                    $VncPassword = $Matches[1].Trim('"', "'")
                }
            }
        }
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
    }

    Write-Host "正在验证校园 VPN 与正方教务连接..."
    docker compose -f $ComposeFile run --rm --no-deps checker network-probe
    if ($LASTEXITCODE -ne 0) {
        throw "无法访问正方教务。请确认 EasyConnect 页面显示已连接。"
    }

    Write-Host "正在验证正方登录；如需要验证码，将自动弹出输入窗口..."
    $arguments = @(
        "compose", "-f", ".\compose.easyconnect.yml",
        "run", "--rm", "--no-deps", "-T",
        "-e", "ZF_CAPTCHA_INPUT_FILE=/data/captcha-answer.txt",
        "-e", "ZF_CAPTCHA_INPUT_TIMEOUT_SECONDS=300",
        "checker", "interactive-probe"
    )
    $probe = Start-Process -FilePath "docker" -ArgumentList $arguments `
        -WorkingDirectory $Root -NoNewWindow -PassThru
    $lastCaptchaHash = $null
    while (-not $probe.HasExited) {
        if (Test-Path -LiteralPath $CaptchaFile) {
            try { $hash = (Get-FileHash -LiteralPath $CaptchaFile -Algorithm SHA256).Hash }
            catch { $hash = $null }
            if ($hash -and $hash -ne $lastCaptchaHash) {
                $lastCaptchaHash = $hash
                $answer = Show-CaptchaDialog $CaptchaFile
                if ([string]::IsNullOrWhiteSpace($answer)) {
                    Write-Utf8NoBom $AnswerFile "__CANCEL__"
                }
                else {
                    Write-Utf8NoBom $AnswerFile $answer
                }
            }
        }
        Start-Sleep -Milliseconds 200
        $probe.Refresh()
    }
    $probe.WaitForExit()
    $probeSucceeded = Test-Path -LiteralPath $ProbeSuccessFile
    Remove-Item -LiteralPath $ProbeSuccessFile -Force -ErrorAction SilentlyContinue
    if (-not $probeSucceeded) {
        throw "正方登录验证失败。请查看上方日志后重新运行 windows-start.cmd。"
    }
    if ($probe.ExitCode -ne 0) {
        Write-Warning "正方验证已经成功，但 Docker 清理临时容器时返回了退出码 $($probe.ExitCode)；启动将继续。"
    }

    Write-Host "正在启动后台成绩检查服务..."
    docker compose -f $ComposeFile up -d checker
    if ($LASTEXITCODE -ne 0) { throw "后台服务启动失败。" }

    docker compose -f $ComposeFile ps
    Write-Host "`n启动完成。以后可直接双击 windows-start.cmd。" -ForegroundColor Green
    Show-Info "启动完成。`n`n服务将在后台检查成绩；首次运行会推送全部成绩，之后无变化时保持静默。`n`nDocker Desktop 重启后，请再次双击 windows-start.cmd 手动启动。"
}
catch {
    Write-Host "`n启动失败：$($_.Exception.Message)" -ForegroundColor Red
    Show-ErrorMessage $_.Exception.Message
    exit 1
}
finally {
    Set-Location $OriginalLocation
}
