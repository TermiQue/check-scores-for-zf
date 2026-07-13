[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$SecretsDir = Join-Path $Root "secrets"
$RuntimeDir = Join-Path $Root "runtime-data"
. (Join-Path $Root "windows-ui.ps1")

function Read-SecretText([string]$Prompt) {
    $Secure = Read-Host $Prompt -AsSecureString
    $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Value) {
    [IO.File]::WriteAllText($Path, $Value.Trim(), [Text.UTF8Encoding]::new($false))
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "未找到 Docker。请自行安装并启动 Docker Desktop：https://docs.docker.com/desktop/setup/install/windows-install/"
}

New-Item -ItemType Directory -Force -Path $SecretsDir, $RuntimeDir | Out-Null

$Username = Read-Host "请输入正方教务学号"
$Password = Read-SecretText "请输入正方教务密码"
$PushToken = Read-SecretText "请输入 ShowDoc Push Token（获取方法见 README；也可粘贴完整推送 URL）"

Write-Utf8NoBom (Join-Path $SecretsDir "zf_username.txt") $Username
Write-Utf8NoBom (Join-Path $SecretsDir "zf_password.txt") $Password
Write-Utf8NoBom (Join-Path $SecretsDir "push_token.txt") $PushToken

$EnvFile = Join-Path $Root ".env"
if (-not (Test-Path $EnvFile)) {
    Copy-Item (Join-Path $Root ".env.example") $EnvFile
}

Write-Host "账号配置已安全写入本地 secrets 目录（不会提交到 Git）。"
Write-Host "正在准备成绩查询运行环境，请稍候..."
$buildResult = Invoke-DockerWithProgress `
    -Arguments @("compose", "-f", (Join-Path $Root "compose.easyconnect.yml"), "build", "checker") `
    -Activity "正在初始化正方成绩检查服务" -Status "构建成绩查询镜像" `
    -StartPercent 20 -EndPercent 95 -WorkingDirectory $Root
if ($buildResult.ExitCode -ne 0) {
    throw "Docker 镜像构建失败。"
}

Write-Host "初始化完成，启动程序将继续后续步骤。" -ForegroundColor Green
