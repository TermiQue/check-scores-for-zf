function ConvertTo-NativeArgument([string]$Value) {
    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + $Value.Replace('"', '\"') + '"'
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
    # Keep the repeatedly redrawn line ASCII-only. Windows PowerShell 5.1
    # miscalculates cursor positions for double-width Chinese characters,
    # which causes duplicated and overlapping text in Windows Terminal.
    $line = "`r[$bar] $safePercent% $spinner T+${ElapsedSeconds}s"
    Write-Host $line.PadRight(64) -NoNewline -ForegroundColor Cyan
}

function Write-ChineseWarning([string]$Text) {
    Write-Host "[警告] $Text" -ForegroundColor Yellow
}

function Clear-LiveProgress([string]$Activity) {
    Write-Host ("`r" + (" " * 72) + "`r") -NoNewline
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
        Write-Host "[进行中] $Status" -ForegroundColor Cyan
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

        if ($exitCode -eq 0) {
            Write-Host ("[完成] {0}（{1:N1} 秒）" -f $Status, $stopwatch.Elapsed.TotalSeconds) -ForegroundColor Green
        }
        else {
            Write-Host ("[失败] {0}" -f (Get-FriendlyDockerError $details $exitCode)) -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($details)) {
                Write-Host "Docker 诊断信息（仅显示最后 12 行，可能包含英文原文）：" -ForegroundColor DarkYellow
                $details -split "`r?`n" | Select-Object -Last 12 | ForEach-Object {
                    Write-Host "  | $_" -ForegroundColor DarkGray
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
