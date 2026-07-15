function ConvertTo-NativeArgument([string]$Value) {
    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + $Value.Replace('"', '\"') + '"'
}

Set-Variable -Name UiLauncherColor -Scope Script -Value "#f0f5e5" -Force
Set-Variable -Name UiRunningColor -Scope Script -Value "#AB372F" -Force
Set-Variable -Name UiSuccessColor -Scope Script -Value "#2bae85" -Force
Set-Variable -Name UiWaitingColor -Scope Script -Value "#fbb929" -Force

function Repair-DuplicateProcessPath {
    # Some launchers pass both Path and PATH. Windows PowerShell 5.1 treats
    # them as duplicate keys when Start-Process builds a child environment.
    try { $variables = [Environment]::GetEnvironmentVariables() }
    catch { return }
    $pathKeys = @($variables.Keys | Where-Object { ([string]$_) -ieq "Path" })
    if ($pathKeys.Count -le 1) { return }

    $pathValue = $null
    foreach ($key in $pathKeys) {
        if (([string]$key) -ceq "Path") {
            $pathValue = [string]$variables[$key]
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($pathValue)) {
        $pathValue = [string]$variables[$pathKeys[0]]
    }
    foreach ($key in $pathKeys) {
        [Environment]::SetEnvironmentVariable([string]$key, $null, "Process")
    }
    [Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")
}

Repair-DuplicateProcessPath

try {
    $script:UiAnsiEnabled = -not [Console]::IsOutputRedirected
}
catch {
    $script:UiAnsiEnabled = $false
}

function Write-UiColor {
    param(
        [string]$Text,
        [string]$HexColor,
        [switch]$NoNewline
    )

    if ($script:UiAnsiEnabled -and $HexColor -match '^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$') {
        $red = [Convert]::ToInt32($Matches[1], 16)
        $green = [Convert]::ToInt32($Matches[2], 16)
        $blue = [Convert]::ToInt32($Matches[3], 16)
        $escape = [char]27
        Write-Host "$escape[38;2;$red;$green;${blue}m$Text$escape[0m" -NoNewline:$NoNewline
        return
    }
    Write-Host $Text -NoNewline:$NoNewline
}

function Write-LauncherTitle([string]$Text) {
    Write-UiColor -Text $Text -HexColor $script:UiLauncherColor
}

function Write-RunningStatus([string]$Text) {
    Write-UiColor -Text "[运行状态] $Text" -HexColor $script:UiRunningColor
}

function Write-WaitingStatus([string]$Text) {
    Write-UiColor -Text "[等待输入] $Text" -HexColor $script:UiWaitingColor
}

function Write-SuccessStatus([string]$Text) {
    Write-UiColor -Text "[运行成功] $Text" -HexColor $script:UiSuccessColor
}

function Write-FailureStatus([string]$Text) {
    Write-UiColor -Text "[运行失败] $Text" -HexColor $script:UiRunningColor
}

function Write-LiveProgress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$Percent,
        [int]$Frame,
        [int]$ElapsedSeconds
    )

    $safePercent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $width = 22
    $filled = [int][Math]::Floor($safePercent * $width / 100)
    $bar = ("#" * $filled) + ("-" * ($width - $filled))
    $spinner = @('|', '/', '-', '\')[$Frame % 4]
    Clear-LiveProgress $Activity
    $line = "[运行状态] [$bar] $safePercent% $spinner $Status（${ElapsedSeconds} 秒）"
    Write-UiColor -Text $line -HexColor $script:UiRunningColor -NoNewline
}

function Write-ChineseWarning([string]$Text) {
    Write-WaitingStatus $Text
}

function Clear-LiveProgress([string]$Activity) {
    if ($script:UiAnsiEnabled) {
        $escape = [char]27
        Write-Host "$escape[2K`r" -NoNewline
    }
    else {
        Write-Host ("`r" + (" " * 120) + "`r") -NoNewline
    }
}

function Get-FriendlyDockerError([string]$Details, [int]$ExitCode) {
    if ($Details -match '(?i)permission denied.*docker|docker_engine|cannot connect to the docker daemon') {
        return "无法连接 Docker Desktop。请确认 Docker Desktop 已启动并运行 Linux 容器。"
    }
    if ($Details -match '(?i)unauthorized|authentication required|pull access denied') {
        return "Docker 镜像下载认证失败，请检查网络或镜像仓库登录状态。"
    }
    if ($Details -match '(?i)no such host|failed to resolve|failed to do request|connectex|i/o timeout|temporary failure in name resolution') {
        return "Docker 网络或域名解析失败，请检查网络、代理和 DNS 设置。"
    }
    if ($Details -match '(?i)port is already allocated|address already in use|bind.*failed') {
        return "项目需要的本地端口已被占用，请关闭占用程序后重试。"
    }
    if ($Details -match '(?i)no matching manifest|requested image.*platform') {
        return "当前电脑架构与 Docker 镜像不兼容。"
    }
    return "Docker 操作失败，退出码为 $ExitCode。"
}

function Invoke-DockerWithProgress {
    param(
        [string[]]$Arguments,
        [string]$Activity,
        [string]$Status,
        [int]$StartPercent,
        [int]$EndPercent,
        [string]$WorkingDirectory,
        [scriptblock]$OnTick
    )

    $id = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) "zfcheck-docker-$id.out.log"
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) "zfcheck-docker-$id.err.log"
    $argumentText = (($Arguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }) -join ' ')
    $process = $null
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $progressStarted = $false
    $progressCleared = $false

    try {
        $process = Start-Process -FilePath "docker" -ArgumentList $argumentText `
            -WorkingDirectory $WorkingDirectory -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        # Keep the native process handle alive; Windows PowerShell 5.1 can
        # otherwise return a null ExitCode after a very short-lived process.
        $null = $process.Handle
        $progressStarted = $true

        $frame = 0
        do {
            $elapsed = [Math]::Max(0, [int]$stopwatch.Elapsed.TotalSeconds)
            $fraction = [Math]::Min(0.94, 1.0 - [Math]::Exp(-$stopwatch.Elapsed.TotalSeconds / 7.0))
            $percent = $StartPercent + [int][Math]::Floor(($EndPercent - $StartPercent) * $fraction)
            Write-LiveProgress -Activity $Activity -Status $Status -Percent $percent -Frame $frame -ElapsedSeconds $elapsed
            if ($OnTick) {
                & $OnTick
            }
            $frame++
            Start-Sleep -Milliseconds 200
            $process.Refresh()
        } while (-not $process.HasExited)

        $process.WaitForExit()
        $process.Refresh()
        $exitCode = $process.ExitCode
        $stopwatch.Stop()
        Clear-LiveProgress $Activity
        $progressCleared = $true

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue } else { "" }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue } else { "" }
        $details = (($stderr, $stdout) -join "`n").Trim()

        if ($exitCode -ne 0) {
            Write-FailureStatus (Get-FriendlyDockerError $details $exitCode)
            if (-not [string]::IsNullOrWhiteSpace($details)) {
                Write-Host "Docker 诊断信息（仅显示最后 12 行，可能包含英文原文）："
                $details -split "`r?`n" | Select-Object -Last 12 | ForEach-Object {
                    Write-Host "  | $_"
                }
            }
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $stdout
            ErrorOutput = $stderr
        }
    }
    finally {
        $stopwatch.Stop()
        if ($progressStarted -and -not $progressCleared) {
            Clear-LiveProgress $Activity
        }
        if ($process -and -not $process.HasExited) {
            try { $process.Kill() } catch { }
        }
        if ($process) { $process.Dispose() }
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}
