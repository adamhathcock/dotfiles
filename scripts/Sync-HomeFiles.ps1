<#
.SYNOPSIS
  Syncs tracked files from the home directory into this repo.

.DESCRIPTION
  Reads a manifest of home-relative file paths and copies each existing source
  file into the matching path inside this repo. If a listed source file is
  missing, the repo copy is removed.

.EXAMPLE
  .\Sync-HomeFiles.ps1

.EXAMPLE
  .\Sync-HomeFiles.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)] param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'home-files.txt')
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$homeRoot = [IO.Path]::GetFullPath($HOME)

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
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Detail
    )

    $Results.Value += [pscustomobject]@{
        Path = $Path
        Status = $Status
        Detail = $Detail
    }
}

function Resolve-TrackedPath {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$Label
    )

    if ([IO.Path]::IsPathRooted($RelativePath)) {
        throw "Manifest entry '$RelativePath' must be home-relative"
    }

    $normalizedBasePath = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $normalizedRelativePath = $RelativePath -replace '[\\/]+', [string][IO.Path]::DirectorySeparatorChar
    $resolvedPath = [IO.Path]::GetFullPath((Join-Path $normalizedBasePath $normalizedRelativePath))
    $expectedPrefix = $normalizedBasePath + [IO.Path]::DirectorySeparatorChar

    if ($resolvedPath -ne $normalizedBasePath -and -not $resolvedPath.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest entry '$RelativePath' escapes the $Label root"
    }

    return $resolvedPath
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifest file not found: $ManifestPath"
}

$entries = Get-Content -LiteralPath $ManifestPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') }

if (-not $entries) {
    Write-Warn "No tracked files listed in $ManifestPath"
    return
}

$results = @()

Write-Step "Syncing $(($entries | Measure-Object).Count) tracked file(s)"

foreach ($entry in $entries) {
    $sourcePath = Resolve-TrackedPath -BasePath $homeRoot -RelativePath $entry -Label 'home'
    $destinationPath = Resolve-TrackedPath -BasePath $repoRoot -RelativePath $entry -Label 'repo'

    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        $destinationDirectory = Split-Path -Parent $destinationPath

        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($destinationDirectory, 'Create directory')) {
                New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            }
        }

        if ($PSCmdlet.ShouldProcess($destinationPath, 'Copy tracked file from home')) {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }

        Write-Ok "Synced $entry"
        Add-Result -Results ([ref]$results) -Path $entry -Status 'Synced' -Detail 'Copied from home directory'
        continue
    }

    if (Test-Path -LiteralPath $sourcePath) {
        throw "Manifest entry '$entry' is not a file in the home directory"
    }

    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        if ($PSCmdlet.ShouldProcess($destinationPath, 'Delete repo copy because source file is missing')) {
            Remove-Item -LiteralPath $destinationPath -Force
        }

        Write-Ok "Removed $entry"
        Add-Result -Results ([ref]$results) -Path $entry -Status 'Removed' -Detail 'Source file is missing from home directory'
        continue
    }

    Write-Warn "Missing source for $entry"
    Add-Result -Results ([ref]$results) -Path $entry -Status 'Skipped' -Detail 'Source file missing and no repo copy to delete'
}

Write-Host "`nSummary" -ForegroundColor White
$results | Format-Table -AutoSize
