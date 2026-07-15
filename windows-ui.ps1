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

# Windows PowerShell 5.1 otherwise inherits the legacy system code page and
# can decode UTF-8 output from Docker/Python as mojibake before it reaches the
# terminal or a WinForms error dialog.
$script:UiUtf8Encoding = [Text.UTF8Encoding]::new($false)
try {
    [Console]::InputEncoding = $script:UiUtf8Encoding
    [Console]::OutputEncoding = $script:UiUtf8Encoding
}
catch {
    # Redirected/non-console hosts may not expose mutable console encodings.
}
$global:OutputEncoding = $script:UiUtf8Encoding

function ConvertTo-ReadableText([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    # Repair the common case where UTF-8 bytes were already decoded as the
    # Simplified Chinese Windows code page (for example "正方" -> "姝ｆ柟").
    $mojibakePattern = '姝ｆ|鎴愮|妫€|湇鍔|惎鍔|璇峰|鍚庨|閲嶈|锛|銆|鈥|鏈|缁撴|澶辫触|鍚'
    if ($Text -notmatch $mojibakePattern) { return $Text }

    try {
        $legacyEncoding = [Text.Encoding]::GetEncoding(936)
        $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
        $repaired = $strictUtf8.GetString($legacyEncoding.GetBytes($Text))
        if (-not [string]::IsNullOrWhiteSpace($repaired)) { return $repaired }
    }
    catch {
        # Some bytes may already have been replaced with '?', which cannot be
        # recovered safely. Preserve the original instead of guessing.
    }
    return $Text
}

if (-not ("ZfConsoleSpinner" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Threading;

public static class ZfConsoleSpinner
{
    private static readonly object Gate = new object();
    private static readonly string[] Frames = new[] { "|", "/", "-", "\\" };
    private static Timer timer;
    private static string text = "";
    private static int frame;

    private static void StopTimer()
    {
        Timer current = timer;
        timer = null;
        if (current != null) current.Dispose();
    }

    private static void Render(object state)
    {
        lock (Gate)
        {
            if (timer == null) return;
            try
            {
                Console.Write(
                    "\x1b[2K\r\x1b[38;2;171;55;47m[运行] " +
                    Frames[frame++ % Frames.Length] + " " + text + "\x1b[0m"
                );
            }
            catch { }
        }
    }

    public static void Start(string value)
    {
        lock (Gate)
        {
            StopTimer();
            text = value ?? "";
            frame = 0;
            timer = new Timer(Render, null, 0, 180);
        }
    }

    public static void Pause()
    {
        lock (Gate)
        {
            StopTimer();
            try { Console.Write("\x1b[2K\r"); }
            catch { }
        }
    }
}
"@
}

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
    if (-not [string]::IsNullOrWhiteSpace($script:UiActiveOperation)) {
        Complete-RunningStatus
    }
    $script:UiActiveOperation = $Text
    if ($script:UiAnsiEnabled) {
        [ZfConsoleSpinner]::Start($Text)
    }
    else {
        Write-UiColor -Text "[运行] | $Text" -HexColor $script:UiRunningColor -NoNewline
    }
}

function Write-WaitingStatus([string]$Text) {
    if (-not [string]::IsNullOrWhiteSpace($script:UiActiveOperation)) {
        Clear-LiveProgress "等待输入"
    }
    Write-UiColor -Text $Text -HexColor $script:UiWaitingColor
}

function Write-SuccessStatus([string]$Text) {
    if (-not [string]::IsNullOrWhiteSpace($script:UiActiveOperation)) {
        Clear-LiveProgress $Text
    }
    Write-UiColor -Text "[成功] $Text" -HexColor $script:UiSuccessColor
    $script:UiActiveOperation = $null
}

function Complete-RunningStatus([string]$Text = "") {
    $completedText = if ([string]::IsNullOrWhiteSpace($Text)) {
        $script:UiActiveOperation
    }
    else {
        $Text
    }
    if ([string]::IsNullOrWhiteSpace($completedText)) { return }
    Write-SuccessStatus $completedText
}

function Suspend-RunningStatus {
    if (-not [string]::IsNullOrWhiteSpace($script:UiActiveOperation)) {
        Clear-LiveProgress "等待输入"
    }
}

function Write-FailureStatus([string]$Text) {
    $Text = ConvertTo-ReadableText $Text
    if (-not [string]::IsNullOrWhiteSpace($script:UiActiveOperation)) {
        Clear-LiveProgress $Text
    }
    $script:UiActiveOperation = $null
    Write-UiColor -Text "错误：$Text" -HexColor $script:UiRunningColor
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
    $line = "[运行] [$bar] $safePercent% $spinner $Status（${ElapsedSeconds} 秒）"
    Write-UiColor -Text $line -HexColor $script:UiRunningColor -NoNewline
}

function Write-ChineseWarning([string]$Text) {
    Write-WaitingStatus $Text
}

function Clear-LiveProgress([string]$Activity) {
    if ($script:UiAnsiEnabled) {
        [ZfConsoleSpinner]::Pause()
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
        Write-RunningStatus $Status
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

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue } else { "" }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue } else { "" }
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
        else {
            Complete-RunningStatus ("{0}（{1:N1} 秒）" -f $Status, $stopwatch.Elapsed.TotalSeconds)
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
