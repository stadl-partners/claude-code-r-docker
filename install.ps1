# Usage: .\install.ps1 [-Uninstall]
# Adds this repo to your user PATH so `claude-r` works from cmd, PowerShell and Git Bash
# (claude-r.cmd in cmd/PowerShell, the claude-r script in Git Bash).
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'

$repo = $PSScriptRoot.TrimEnd('\')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { $_ })
$others = @($entries | Where-Object { $_.TrimEnd('\') -ne $repo })

if ($Uninstall) {
    if ($others.Count -eq $entries.Count) {
        Write-Warning "$repo is not on your user PATH"
    } else {
        [Environment]::SetEnvironmentVariable('Path', ($others -join ';'), 'User')
        Write-Host "Removed $repo from user PATH"
    }
    exit 0
}

if ($others.Count -eq $entries.Count) {
    [Environment]::SetEnvironmentVariable('Path', (($entries + $repo) -join ';'), 'User')
    Write-Host "Added $repo to user PATH"
} else {
    Write-Host "$repo is already on your user PATH"
}
if (-not (($env:Path -split ';') | Where-Object { $_.TrimEnd('\') -eq $repo })) {
    $env:Path += ";$repo"
}
Write-Host 'Restart open terminals (including VS Code and RStudio) for the change to take effect.'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Warning 'docker not found on PATH. Install Docker Desktop.'
}
