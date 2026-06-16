[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [int]$MaxDiffChars = 12000,
    [int]$MaxFileChars = 3000,
    [int]$MaxSnapshotFiles = 12
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

function Try-Git {
    param([string[]]$Arguments)

    try {
        return @(Invoke-Git -Arguments $Arguments)
    }
    catch {
        return @()
    }
}

function Get-LastReleaseTag {
    $tag = (Try-Git @("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*.[0-9]*.[0-9]*")) -join "`n"
    if ($tag) { return $tag.Trim() }
    return $null
}

function Convert-NameStatus {
    param(
        [string[]]$Lines,
        [string]$Scope
    )

    $items = @()
    foreach ($line in $Lines) {
        if (-not $line) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -lt 2) { continue }
        $path = $parts[-1]
        $items += [pscustomobject]@{
            status = $parts[0]
            path = $path
            scope = $Scope
        }
    }
    return @($items)
}

function Test-TextReleaseFile {
    param([string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -in @(".md", ".ps1", ".mjs", ".js", ".json", ".yaml", ".yml", ".cmd", ".txt")) {
        return $true
    }
    return $false
}

function Limit-Text {
    param(
        [string]$Text,
        [int]$MaxChars
    )

    if ($null -eq $Text) { return $null }
    if ($Text.Length -le $MaxChars) { return $Text }
    return $Text.Substring(0, $MaxChars) + "`n[content truncated]"
}

function Get-GitTextAtRef {
    param(
        [string]$Ref,
        [string]$Path
    )

    if (-not $Ref) { return $null }
    try {
        return (Invoke-Git @("show", "$Ref`:$Path")) -join "`n"
    }
    catch {
        return $null
    }
}

function Get-CurrentText {
    param([string]$Path)

    $fullPath = Join-Path $RepoRoot $Path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $null
    }
    return Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
}

function New-ContentSnapshots {
    param(
        [object[]]$ChangedFiles,
        [string]$PreviousRef,
        [int]$MaxFiles,
        [int]$MaxChars
    )

    $snapshots = @()
    $seen = @{}
    foreach ($file in $ChangedFiles) {
        if (-not $file.path -or $seen.ContainsKey($file.path)) { continue }
        $seen[$file.path] = $true
        if (-not (Test-TextReleaseFile -Path $file.path)) { continue }
        if ($snapshots.Count -ge $MaxFiles) { break }

        $previous = Get-GitTextAtRef -Ref $PreviousRef -Path $file.path
        $current = Get-CurrentText -Path $file.path
        $snapshots += [pscustomobject]@{
            path = $file.path
            status = $file.status
            scope = $file.scope
            previous_content_excerpt = Limit-Text -Text $previous -MaxChars $MaxChars
            current_content_excerpt = Limit-Text -Text $current -MaxChars $MaxChars
        }
    }
    return @($snapshots)
}

$versionPath = Join-Path $RepoRoot "VERSION.json"
if (-not (Test-Path -LiteralPath $versionPath)) {
    throw "Missing VERSION.json at $versionPath"
}

$versionInfo = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$statusLines = @(Invoke-Git @("status", "--porcelain=v1"))
$branch = (Invoke-Git @("branch", "--show-current")) -join "`n"
$lastCommit = (Invoke-Git @("log", "-1", "--pretty=format:%H %s")) -join "`n"
$lastReleaseTag = Get-LastReleaseTag
$releaseRange = if ($lastReleaseTag) { "$lastReleaseTag..HEAD" } else { "" }
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
        scope = "worktree"
    }
}

$committedDiffSummary = ""
$committedNameStatus = ""
$commitLog = ""
$committedDiffText = ""
if ($releaseRange) {
    $committedDiffSummary = (Invoke-Git @("diff", "--stat", $releaseRange, "--", ".")) -join "`n"
    $committedNameStatus = (Invoke-Git @("diff", "--name-status", $releaseRange, "--", ".")) -join "`n"
    $commitLog = (Invoke-Git @("log", "--oneline", $releaseRange)) -join "`n"
    $committedDiffText = (Invoke-Git @("diff", $releaseRange, "--", ".")) -join "`n"
    $changedFiles += Convert-NameStatus -Lines @($committedNameStatus -split "`n") -Scope "committed"
}

$worktreeDiffSummary = (Invoke-Git @("diff", "--stat")) -join "`n"
$diffNameStatus = (Invoke-Git @("diff", "--name-status")) -join "`n"
$stagedNameStatus = (Invoke-Git @("diff", "--cached", "--name-status")) -join "`n"
$worktreeDiffText = (Invoke-Git @("diff", "--", ".")) -join "`n"
$stagedDiffText = (Invoke-Git @("diff", "--cached", "--", ".")) -join "`n"
$diffText = @(
    "## Committed changes since last release tag"
    "Last release tag: $lastReleaseTag"
    "Release range: $releaseRange"
    $committedDiffText
    ""
    "## Staged changes"
    $stagedDiffText
    ""
    "## Unstaged changes"
    $worktreeDiffText
) -join "`n"
if ($diffText.Length -gt $MaxDiffChars) {
    $diffText = $diffText.Substring(0, $MaxDiffChars) + "`n[diff truncated]"
}
$contentSnapshots = New-ContentSnapshots `
    -ChangedFiles $changedFiles `
    -PreviousRef $lastReleaseTag `
    -MaxFiles $MaxSnapshotFiles `
    -MaxChars $MaxFileChars

[pscustomobject]@{
    repository = (Resolve-Path -LiteralPath $RepoRoot).Path
    current_version = $versionInfo.version
    branch = $branch
    last_commit = $lastCommit
    last_release_tag = $lastReleaseTag
    release_range = $releaseRange
    commit_log = $commitLog
    changed_files = $changedFiles
    diff_summary = (@($committedDiffSummary, $worktreeDiffSummary) | Where-Object { $_ }) -join "`n"
    diff_name_status = $diffNameStatus
    committed_name_status = $committedNameStatus
    staged_name_status = $stagedNameStatus
    content_snapshots = $contentSnapshots
    diff_excerpt = $diffText
    collected_at = (Get-Date).ToString("s")
} | ConvertTo-Json -Depth 8
