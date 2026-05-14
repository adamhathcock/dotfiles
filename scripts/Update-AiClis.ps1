<#
.SYNOPSIS
  Updates the locally installed AI CLIs used in this workspace.

.DESCRIPTION
  Runs the supported update command for OpenCode CLI and GitHub Copilot CLI,
  and updates Codex CLI through its npm package.

.EXAMPLE
  .\Update-AiClis.ps1

.EXAMPLE
  .\Update-AiClis.ps1 -SkipCodex
#>
[CmdletBinding()] param(
    [switch]$SkipOpenCode,
    [switch]$SkipCopilot,
    [switch]$SkipCodex,
    [switch]$SkipRtk
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "  OK: $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "  WARN: $Message" -ForegroundColor Yellow
}

function Add-Result {
    param(
        [Parameter(Mandatory)]
        [ref]$Results,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Detail
    )

    $Results.Value += [pscustomobject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
    }
}

function Invoke-UpdateCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [ref]$Results
    )

    $commandInfo = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $commandInfo) {
        Write-Warn "$Name is not installed; skipping"
        Add-Result -Results $Results -Name $Name -Status 'Skipped' -Detail 'Command not found'
        return
    }

    Write-Step "Updating $Name"
    & $commandInfo.Source @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Name update failed with exit code $LASTEXITCODE"
    }

    Write-Ok "$Name updated"
    Add-Result -Results $Results -Name $Name -Status 'Updated' -Detail "$($commandInfo.Name) $($Arguments -join ' ')"
}

function Update-RtkCli {
    param(
        [Parameter(Mandatory)]
        [ref]$Results
    )

    $commandInfo = Get-Command rtk -ErrorAction SilentlyContinue
    if (-not $commandInfo) {
        Write-Warn "RTK is not installed; skipping"
        Add-Result -Results $Results -Name 'RTK CLI' -Status 'Skipped' -Detail 'Command not found'
        return
    }

    Write-Step 'Checking RTK release information'

    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/rtk-ai/rtk/releases/latest'
    $latestVersion = [version]($release.tag_name.TrimStart('v'))
    $currentVersionText = (& $commandInfo.Source --version | Select-Object -First 1).Trim()
    if (-not ($currentVersionText -match '([0-9]+\.[0-9]+\.[0-9]+)')) {
        throw "Could not parse RTK version from '$currentVersionText'"
    }

    $currentVersion = [version]$matches[1]
    if ($currentVersion -ge $latestVersion) {
        Write-Ok "RTK already current ($currentVersion)"
        Add-Result -Results $Results -Name 'RTK CLI' -Status 'Current' -Detail "Version $currentVersion"
        return
    }

    $asset = $release.assets | Where-Object { $_.name -eq 'rtk-x86_64-pc-windows-msvc.zip' } | Select-Object -First 1
    if (-not $asset) {
        throw 'Could not find Windows RTK asset in latest release'
    }

    $targetPath = $commandInfo.Source
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("rtk-update-" + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $tempRoot $asset.name
    $extractPath = Join-Path $tempRoot 'extract'

    try {
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

        Write-Step "Updating RTK from $currentVersion to $latestVersion"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        $downloadedExe = Get-ChildItem $extractPath -Filter 'rtk.exe' -Recurse | Select-Object -First 1
        if (-not $downloadedExe) {
            throw 'Downloaded RTK archive did not contain rtk.exe'
        }

        Copy-Item $downloadedExe.FullName $targetPath -Force
        Write-Ok "RTK updated at $targetPath"
        Add-Result -Results $Results -Name 'RTK CLI' -Status 'Updated' -Detail "$currentVersion -> $latestVersion"
    }
    finally {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$results = @()

if (-not $SkipOpenCode) {
    Invoke-UpdateCommand -Name 'OpenCode CLI' -Command 'opencode' -Arguments @('upgrade') -Results ([ref]$results)
}

if (-not $SkipCopilot) {
    Invoke-UpdateCommand -Name 'GitHub Copilot CLI' -Command 'copilot' -Arguments @('update') -Results ([ref]$results)
}

if (-not $SkipCodex) {
    Invoke-UpdateCommand -Name 'Codex CLI' -Command 'npm' -Arguments @('install', '-g', '@openai/codex@latest') -Results ([ref]$results)
}

if (-not $SkipRtk) {
    Update-RtkCli -Results ([ref]$results)
}

Write-Host "`nSummary" -ForegroundColor White
$results | Format-Table -AutoSize
