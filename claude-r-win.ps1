# Usage: claude-r [--update | --no-update-check | --stop] [directory] [claude args...]
# Runs Claude Code (R image) in a container that sees only <directory> (default: current dir).
#   --update            pull upstream changes (if any), rebuild the images, and exit
#   --no-update-check   skip the upstream check (also: CLAUDE_R_NO_CHECK=1)
#   --stop              stop and remove the egress proxy (it stays up between sessions)
# Env: CLAUDE_R_STACK=slim|full  CLAUDE_R_MEMORY=8g  CLAUDE_R_CPUS=4
#      CLAUDE_R_USE_API_KEY=1 (forward ANTHROPIC_API_KEY)  CLAUDE_R_ALLOW_ANY_DIR=1
#      CLAUDE_R_GIT_WRITABLE=1 (don't mount .git/hooks and .git/config read-only)
# Windows counterpart of the `claude-r` bash script; keep the guard rails in sync.
$ErrorActionPreference = 'Stop'

$repo = $PSScriptRoot
$composeFile = Join-Path $repo 'docker-compose.yml'

function Stop-Refuse([string]$Message, [int]$Code = 64) {
    [Console]::Error.WriteLine("ERROR: $Message")
    exit $Code
}

# Tells the user when upstream has new commits and offers to pull. Silent when offline, up to
# date, or throttled. -Force ignores the throttle and pulls without asking.
function Test-Upstream([switch]$Force) {
    $gitdir = git -C $repo rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0) { return }
    if (-not [System.IO.Path]::IsPathRooted($gitdir)) { $gitdir = Join-Path $repo $gitdir }
    $stamp = Join-Path $gitdir 'claude-r-last-check'
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $last = 0
    if (-not $Force -and (Test-Path -LiteralPath $stamp)) { [void][long]::TryParse((Get-Content -LiteralPath $stamp -Raw), [ref]$last) }
    if ($Force -or ($now - $last) -ge 21600) {
        $env:GIT_TERMINAL_PROMPT = '0'
        $job = Start-Job { param($r) git -C $r fetch --quiet 2>$null; $LASTEXITCODE } -ArgumentList $repo
        if (-not (Wait-Job $job -Timeout 5)) { Stop-Job $job; Remove-Job $job -Force; return }
        $code = Receive-Job $job | Select-Object -Last 1
        Remove-Job $job -Force
        if ($code -ne 0) { return }
        Set-Content -LiteralPath $stamp -Value $now
    }
    $behind = git -C $repo rev-list --count 'HEAD..@{u}' 2>$null
    if ($LASTEXITCODE -ne 0 -or [int]$behind -le 0) { return }

    [Console]::Error.WriteLine("claude-r: $behind new commit(s) upstream:")
    git --no-pager -C $repo log --oneline --max-count=10 'HEAD..@{u}' | ForEach-Object { [Console]::Error.WriteLine($_) }
    if (-not $Force) {
        if ([Console]::IsInputRedirected) { return }
        if ((Read-Host 'Update now? [y/N]') -notmatch '^[Yy]$') { return }
    }
    git -C $repo pull --ff-only --quiet
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine('claude-r: could not fast-forward (local changes or diverged); continuing with current version')
    }
}

$rest = @($args)
$updateOnly = $false
$stopOnly = $false
$skipCheck = [bool]$env:CLAUDE_R_NO_CHECK
while ($rest.Count -gt 0) {
    if ($rest[0] -eq '--update') { $updateOnly = $true }
    elseif ($rest[0] -eq '--no-update-check') { $skipCheck = $true }
    elseif ($rest[0] -eq '--stop') { $stopOnly = $true }
    else { break }
    $rest = @($rest | Select-Object -Skip 1)
}

if ($stopOnly) {
    docker compose -f $composeFile down
    exit $LASTEXITCODE
}

$stack = if ($env:CLAUDE_R_STACK) { $env:CLAUDE_R_STACK } else { 'full' }
if ($stack -notin @('slim', 'full')) { Stop-Refuse 'CLAUDE_R_STACK must be slim or full.' }

$dir = $PWD.Path
if ($rest.Count -gt 0 -and (Test-Path -LiteralPath $rest[0] -PathType Container)) {
    $dir = (Resolve-Path -LiteralPath $rest[0]).ProviderPath
    $rest = @($rest | Select-Object -Skip 1)
}

# Docker Desktop doesn't map host ownership, so the default 1000 is fine.
$env:HOST_UID = '1000'
$env:HOST_GID = '1000'
$env:WORKDIR = $dir
# Windows terminals support truecolor but don't set COLORTERM; keep any explicit value.
if ($null -eq $env:COLORTERM) { $env:COLORTERM = 'truecolor' }

if ($updateOnly) {
    Test-Upstream -Force
    docker compose -f $composeFile build --pull
    exit $LASTEXITCODE
}
if (-not $skipCheck) { Test-Upstream }

# --- Guard rails on what gets mounted --------------------------------------------------------
$full = [System.IO.Path]::GetFullPath($dir).TrimEnd('\')
$userHome = [System.IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
$usersDir = (Split-Path $userHome -Parent).TrimEnd('\')
if ($full -match '^[A-Za-z]:$' -or $full -eq $usersDir) {
    Stop-Refuse "refusing to mount a broad system directory: $dir"
}
if ($full -eq $userHome) { Stop-Refuse 'refusing to mount your entire home directory.' }
if ($dir.Contains(',') -or $dir.Contains("`n")) {
    Stop-Refuse 'project path contains a newline or comma; move the project to a simpler path.'
}

# Per-invocation CLI flags must not widen or replace the managed security boundary.
$blocked = '^(--add-dir|--settings|--setting-sources|--allowedTools|--allowed-tools|--disallowedTools|--disallowed-tools|--permission-mode|--plugin-dir|--plugin-url|--agents|--mcp-config)(=.*)?$'
foreach ($a in $rest) {
    if ($a -match $blocked -or $a -eq '--dangerously-skip-permissions') {
        Stop-Refuse "refusing Claude CLI option that can widen or replace the managed security boundary: $a"
    }
}

if ($env:CLAUDE_R_ALLOW_ANY_DIR -ne '1') {
    $looksLikeR = (Test-Path -LiteralPath (Join-Path $dir 'renv.lock') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $dir 'DESCRIPTION') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $dir 'R') -PathType Container) -or
        (Test-Path -LiteralPath (Join-Path $dir 'tests') -PathType Container) -or
        (Test-Path -LiteralPath (Join-Path $dir '.git') -PathType Container) -or
        (@(Get-ChildItem -LiteralPath $dir -Filter '*.Rproj' -File -ErrorAction SilentlyContinue).Count -gt 0)
    if (-not $looksLikeR) {
        [Console]::Error.WriteLine("ERROR: $dir does not look like an R project.")
        Stop-Refuse 'Run from the project root, or set CLAUDE_R_ALLOW_ANY_DIR=1 deliberately.'
    }
}

$runArgs = @('--rm', '--build')

# Git hooks and config are executed by git on the HOST later; keep them out of Claude's reach.
$gitDir = Join-Path $dir '.git'
if ($env:CLAUDE_R_GIT_WRITABLE -ne '1' -and (Test-Path -LiteralPath $gitDir -PathType Container) -and
    -not ((Get-Item -LiteralPath $gitDir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    $dirFwd = $dir -replace '\\', '/'
    if (Test-Path -LiteralPath (Join-Path $gitDir 'hooks') -PathType Container) {
        $runArgs += @('-v', "${dirFwd}/.git/hooks:/workspace/.git/hooks:ro")
    }
    if (Test-Path -LiteralPath (Join-Path $gitDir 'config') -PathType Leaf) {
        $runArgs += @('-v', "${dirFwd}/.git/config:/workspace/.git/config:ro")
    }
}

# No host credentials are forwarded by default. API-key mode is an explicit opt-in;
# subscription/OAuth login (stored in the claude-home volume) is preferred.
if ($env:CLAUDE_R_USE_API_KEY -eq '1') {
    if (-not $env:ANTHROPIC_API_KEY) { Stop-Refuse 'CLAUDE_R_USE_API_KEY=1 but ANTHROPIC_API_KEY is not set.' 65 }
    $runArgs += @('-e', 'ANTHROPIC_API_KEY')
}

docker compose -f $composeFile run @runArgs claude @rest
exit $LASTEXITCODE
