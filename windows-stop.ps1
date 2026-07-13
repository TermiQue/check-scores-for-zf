[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeFile = Join-Path $Root "compose.easyconnect.yml"
$OriginalLocation = Get-Location
. (Join-Path $Root "windows-ui.ps1")

function Show-StopProgress([int]$Percent, [string]$Status) {
    $safePercent = [Math]::Max(0, [Math]::Min(100, $Percent))
    Write-Host ("[阶段 {0,3}%] {1}" -f $safePercent, $Status) -ForegroundColor Cyan
}

function Complete-StopProgress {
    # 动态行由 windows-ui.ps1 负责清除，此处保留统一的结束钩子。
}

Set-Location $Root
try {
    Write-Host "`n=== 正方成绩检查服务：安全停止 ===" -ForegroundColor Cyan
    Show-StopProgress 10 "检查 Docker Desktop 与项目配置"
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "未找到 Docker。请先安装并启动 Docker Desktop。"
    }

    Show-StopProgress 35 "停止成绩检查器与 EasyConnect 容器"
    $stopResult = Invoke-DockerWithProgress `
        -Arguments @("compose", "-f", $ComposeFile, "--profile", "vpn", "down") `
        -Activity "正在停止正方成绩检查服务" -Status "停止并移除项目容器与网络" `
        -StartPercent 35 -EndPercent 95 -WorkingDirectory $Root
    if ($stopResult.ExitCode -ne 0) {
        throw "容器停止失败，请查看上方 Docker 输出。"
    }

    Show-StopProgress 100 "服务已安全停止"
    Complete-StopProgress
    Write-Host "服务已停止；本地账号、登录会话和成绩基线均已保留。" -ForegroundColor Green
}
catch {
    Complete-StopProgress
    Write-Host "停止失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $OriginalLocation
}
