<#
.SYNOPSIS
  Syncs tracked files from the home directory into this repo.

.DESCRIPTION
  Reads a manifest of home-relative file paths and copies each existing source
  file into the matching path inside this repo. If a listed source file is
  missing, the repo copy can be removed after an explicit confirmation.

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

function Test-FileContentMatch {
    param(
        [Parameter(Mandatory)]
        [string]$PathA,

        [Parameter(Mandatory)]
        [string]$PathB
    )

    if (-not (Test-Path -LiteralPath $PathA -PathType Leaf) -or -not (Test-Path -LiteralPath $PathB -PathType Leaf)) {
        return $false
    }

    $itemA = Get-Item -LiteralPath $PathA
    $itemB = Get-Item -LiteralPath $PathB

    if ($itemA.Length -ne $itemB.Length) {
        return $false
    }

    return (Get-FileHash -LiteralPath $PathA -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $PathB -Algorithm SHA256).Hash
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
        if ((Test-Path -LiteralPath $destinationPath -PathType Leaf) -and (Test-FileContentMatch -PathA $sourcePath -PathB $destinationPath)) {
            Write-Ok "Unchanged $entry"
            Add-Result -Results ([ref]$results) -Path $entry -Status 'Unchanged' -Detail 'Home and repo files already match'
            continue
        }

        $destinationDirectory = Split-Path -Parent $destinationPath

        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($destinationDirectory, 'Create directory')) {
                New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            }
            else {
                Write-Warn "Skipped $entry"
                Add-Result -Results ([ref]$results) -Path $entry -Status 'Skipped' -Detail 'Directory creation declined or previewed'
                continue
            }
        }

        if ($PSCmdlet.ShouldProcess($destinationPath, 'Copy tracked file from home')) {
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
            Write-Ok "Synced $entry"
            Add-Result -Results ([ref]$results) -Path $entry -Status 'Synced' -Detail 'Copied from home directory'
        }
        else {
            Write-Warn "Skipped $entry"
            Add-Result -Results ([ref]$results) -Path $entry -Status 'Skipped' -Detail 'Copy declined or previewed'
        }

        continue
    }

    if (Test-Path -LiteralPath $sourcePath) {
        throw "Manifest entry '$entry' is not a file in the home directory"
    }

    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        if (-not $PSCmdlet.ShouldProcess($destinationPath, 'Delete repo copy because source file is missing')) {
            Write-Warn "Skipped $entry"
            Add-Result -Results ([ref]$results) -Path $entry -Status 'Skipped' -Detail 'Deletion declined or previewed'
            continue
        }

        $confirmationMessage = "Home source for '$entry' is missing.`nDelete '$destinationPath' from the repo?"
        if (-not $PSCmdlet.ShouldContinue($confirmationMessage, 'Confirm delete')) {
            Write-Warn "Kept $entry"
            Add-Result -Results ([ref]$results) -Path $entry -Status 'Skipped' -Detail 'Home source missing; user declined deletion'
            continue
        }

        Remove-Item -LiteralPath $destinationPath -Force
        Write-Ok "Removed $entry"
        Add-Result -Results ([ref]$results) -Path $entry -Status 'Removed' -Detail 'Home source missing and repo file deleted after confirmation'
        continue
    }

    Write-Warn "Missing source for $entry"
    Add-Result -Results ([ref]$results) -Path $entry -Status 'Skipped' -Detail 'Source file missing and no repo copy to delete'
}

Write-Host "`nSummary" -ForegroundColor White
$results | Format-Table -AutoSize
