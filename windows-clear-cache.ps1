[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeFile = Join-Path $Root "compose.easyconnect.yml"
. (Join-Path $Root "windows-ui.ps1")
$GeneratedPaths = @(
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
$SourceDirectories = @("scripts", "tests", "zfcheck")

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

function Invoke-DockerCommand {
    param([string[]]$Arguments)

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

function Show-EraseProgress([int]$Percent, [string]$Status) {
    $safePercent = [Math]::Max(0, [Math]::Min(100, $Percent))
    Write-Host ("[阶段 {0,3}%] {1}" -f $safePercent, $Status) -ForegroundColor Cyan
}

function Complete-EraseProgress {
    # 动态行由 windows-ui.ps1 负责清除，此处保留统一的结束钩子。
}

$OriginalLocation = Get-Location
Set-Location $Root
try {
    Write-Host "`n=== 隐私数据清除与项目重置 ===" -ForegroundColor Cyan
    Show-EraseProgress 0 "等待用户确认清理范围"
    Write-Host "此操作会将工作目录恢复到刚克隆后的状态，并删除："
    Write-Host "  - 正方账号、密码和 ShowDoc Push Token"
    Write-Host "  - 正方 Cookie、成绩基线、验证码、日志和故障状态"
    Write-Host "  - EasyConnect 登录配置、短信验证会话和 VPN 缓存"
    Write-Host "  - 本地 .env 配置、Python/测试缓存"
    Write-Host "  - 本项目的 Docker 容器、网络和服务镜像"
    Write-Host "`n不会删除：Git 仓库、项目源代码、Docker Desktop 或其他项目的数据。" -ForegroundColor Green
    Write-ChineseWarning "该操作不可撤销。再次启动时需要重新输入全部凭据并完成所有验证。"

    if (-not $Force) {
        $confirmation = Read-Host "确认永久清除请输入 ERASE"
        if ($confirmation -ne "ERASE") {
            Complete-EraseProgress
            Write-Host "已取消，未删除任何数据。" -ForegroundColor Yellow
            exit 0
        }
    }

    Show-EraseProgress 10 "检查 Docker Desktop 与项目资源"
    $dockerCleanupIncomplete = $false
    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCommand) {
        Invoke-DockerCommand -Arguments @("info")
        if ($script:LastDockerExitCode -eq 0) {
            # Compose 在执行 down 时仍会解析 secrets.file；二次清理时用空文件补齐已删除的路径。
            Ensure-ComposeSecretPlaceholders
            Show-EraseProgress 25 "停止本项目的所有容器"
            $stopResult = Invoke-DockerWithProgress `
                -Arguments @("compose", "-f", $ComposeFile, "--profile", "vpn", "stop") `
                -Activity "正在清除隐私数据并重置项目" -Status "停止本项目的所有容器" `
                -StartPercent 25 -EndPercent 42 -WorkingDirectory $Root
            if ($stopResult.ExitCode -ne 0) {
                throw "本项目容器未能全部停止。为避免运行中的服务继续读写数据，本次未清除任何隐私文件。"
            }

            Show-EraseProgress 45 "删除项目容器、网络和服务镜像"
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

    Show-EraseProgress 65 "删除本地账号、会话、成绩与配置数据"
    foreach ($path in $GeneratedPaths) {
        Remove-GeneratedPath $path
    }

    foreach ($directoryName in $SourceDirectories) {
        $sourcePath = Join-Path $Root $directoryName
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            continue
        }

        Get-ChildItem -LiteralPath $sourcePath -Directory -Filter "__pycache__" -Recurse -Force |
            Sort-Object FullName -Descending |
            ForEach-Object { Remove-GeneratedPath $_.FullName }
        Get-ChildItem -LiteralPath $sourcePath -File -Filter "*.pyc" -Recurse -Force |
            ForEach-Object { Remove-GeneratedPath $_.FullName }
    }

    Show-EraseProgress 95 "核对隐私数据清理结果"
    if ($dockerCleanupIncomplete) {
        Complete-EraseProgress
        Write-ChineseWarning "本地隐私文件已删除，但 Docker 资源清理未完成。启动 Docker Desktop 后请再次运行本脚本。"
        exit 1
    }

    Show-EraseProgress 100 "隐私数据清理完成"
    Complete-EraseProgress
    Write-Host "隐私数据已全部清除，项目已恢复到刚克隆后的状态。" -ForegroundColor Green
}
catch {
    Complete-EraseProgress
    Write-Host "清理失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $OriginalLocation
}
