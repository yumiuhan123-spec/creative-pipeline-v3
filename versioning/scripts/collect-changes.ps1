[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [int]$MaxDiffChars = 30000
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Invoke-Git {
    param([string[]]$Arguments)

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git -C $RepoRoot @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }

    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $output"
    }

    return @($output | Where-Object { "$_" -notmatch "^warning:" })
}

function Get-RelativePath {
    param([string]$BasePath, [string]$FullPath)

    $base = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd("\")
    $full = (Resolve-Path -LiteralPath $FullPath).Path
    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($base.Length).TrimStart("\")
    }
    return $full
}

$versionPath = Join-Path $RepoRoot "VERSION.json"
if (-not (Test-Path -LiteralPath $versionPath)) {
    throw "Missing VERSION.json at $versionPath"
}

$versionInfo = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$statusLines = @(Invoke-Git @("status", "--porcelain=v1"))
$branch = (Invoke-Git @("branch", "--show-current")) -join "`n"
$lastCommit = (Invoke-Git @("log", "-1", "--pretty=format:%H %s")) -join "`n"
$changedFiles = @()

foreach ($line in $statusLines) {
    if (-not $line) {
        continue
    }

    $status = $line.Substring(0, 2)
    $path = $line.Substring(3)
    if ($path -match " -> ") {
        $path = ($path -split " -> ")[-1]
    }

    $changedFiles += [pscustomobject]@{
        status = $status.Trim()
        path = $path
    }
}

$diffSummary = (Invoke-Git @("diff", "--stat")) -join "`n"
$diffNameStatus = (Invoke-Git @("diff", "--name-status")) -join "`n"
$stagedNameStatus = (Invoke-Git @("diff", "--cached", "--name-status")) -join "`n"
$diffText = (Invoke-Git @("diff", "--", ".")) -join "`n"
if ($diffText.Length -gt $MaxDiffChars) {
    $diffText = $diffText.Substring(0, $MaxDiffChars) + "`n[diff truncated]"
}

[pscustomobject]@{
    repository = (Resolve-Path -LiteralPath $RepoRoot).Path
    current_version = $versionInfo.version
    branch = $branch
    last_commit = $lastCommit
    changed_files = $changedFiles
    diff_summary = $diffSummary
    diff_name_status = $diffNameStatus
    staged_name_status = $stagedNameStatus
    diff_excerpt = $diffText
    collected_at = (Get-Date).ToString("s")
} | ConvertTo-Json -Depth 8
