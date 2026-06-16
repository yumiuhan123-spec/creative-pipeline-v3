[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [string]$ArchiveRoot = "",
    [string]$ReleaseIntent = "",
    [ValidateSet("patch", "minor", "major")]
    [string]$BumpOverride = "",
    [switch]$SkipAI,
    [switch]$DryRun,
    [switch]$Approve
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-DefaultArchiveRoot {
    $chars = @(
        21019, 24847, 36164, 20135, 27969, 27700, 32447, 95,
        29256, 26412, 26723, 26696
    )
    $name = -join ($chars | ForEach-Object { [char]$_ })
    return (Join-Path (Join-Path $HOME "Desktop") $name)
}

function Add-Version {
    param(
        [string]$Version,
        [ValidateSet("patch", "minor", "major")]
        [string]$Bump
    )

    $parts = $Version.Split(".") | ForEach-Object { [int]$_ }
    if ($parts.Count -ne 3) {
        throw "Invalid semantic version: $Version"
    }

    switch ($Bump) {
        "patch" { $parts[2] += 1 }
        "minor" {
            $parts[1] += 1
            $parts[2] = 0
        }
        "major" {
            $parts[0] += 1
            $parts[1] = 0
            $parts[2] = 0
        }
    }

    return ($parts -join ".")
}

function New-FallbackAnalysis {
    param(
        [object]$Changes,
        [string]$Bump
    )

    $next = Add-Version -Version $Changes.current_version -Bump $Bump
    $changed = @("Update version-manager files and release workflow")
    if ($ReleaseIntent) {
        $changed = @($ReleaseIntent)
    }

    [pscustomobject]@{
        recommended_bump = $Bump
        current_version = $Changes.current_version
        next_version = $next
        summary_for_user = ($changed | Select-Object -First 1)
        changelog = [pscustomobject]@{
            added = @()
            changed = $changed
            fixed = @()
            removed = @()
        }
        risks = @("DeepSeek was not called. Local fallback text needs manual review.")
        should_create_git_tag = $true
    }
}

function ConvertTo-ChangelogSection {
    param([object]$Analysis)

    $date = Get-Date -Format "yyyy-MM-dd"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## $($Analysis.next_version) - $date")
    $lines.Add("")

    $sections = @(
        @{ Title = "Added"; Items = @($Analysis.changelog.added) },
        @{ Title = "Changed"; Items = @($Analysis.changelog.changed) },
        @{ Title = "Fixed"; Items = @($Analysis.changelog.fixed) },
        @{ Title = "Removed"; Items = @($Analysis.changelog.removed) }
    )

    foreach ($section in $sections) {
        if ($section.Items.Count -eq 0) {
            continue
        }
        $lines.Add("### $($section.Title)")
        $lines.Add("")
        foreach ($item in $section.Items) {
            $lines.Add("- $item")
        }
        $lines.Add("")
    }

    if (@($Analysis.risks).Count -gt 0) {
        $lines.Add("### Risks")
        $lines.Add("")
        foreach ($risk in @($Analysis.risks)) {
            $lines.Add("- $risk")
        }
        $lines.Add("")
    }

    return ($lines -join "`r`n")
}

function Update-Changelog {
    param(
        [string]$Path,
        [string]$NewSection
    )

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($content, "(?m)^## ")
    if (-not $match.Success) {
        return ($content.TrimEnd() + "`r`n`r`n" + $NewSection.TrimEnd() + "`r`n")
    }

    $index = $match.Index
    $head = $content.Substring(0, $index).TrimEnd()
    $tail = $content.Substring($index).TrimStart()
    return ($head + "`r`n`r`n" + $NewSection.TrimEnd() + "`r`n" + $tail)
}

function Assert-SafeRelease {
    param([string]$RepoRoot)

    $validator = Join-Path $RepoRoot "scripts\validate-release.ps1"
    if (-not (Test-Path -LiteralPath $validator)) {
        throw "Missing release validator: $validator"
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validator | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Release validation failed."
    }
}

if (-not $ArchiveRoot) {
    $ArchiveRoot = Get-DefaultArchiveRoot
}

$workDir = Join-Path $RepoRoot "versioning\.work"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$changesPath = Join-Path $workDir "changes.json"
$analysisPath = Join-Path $workDir "analysis.json"
$releaseNotesPath = Join-Path $workDir "RELEASE_NOTES.md"

& (Join-Path $PSScriptRoot "collect-changes.ps1") -RepoRoot $RepoRoot | Set-Content -LiteralPath $changesPath -Encoding UTF8
$changes = Get-Content -LiteralPath $changesPath -Raw -Encoding UTF8 | ConvertFrom-Json

Assert-SafeRelease -RepoRoot $RepoRoot

$bump = if ($BumpOverride) { $BumpOverride } else { "patch" }
if ($SkipAI) {
    $analysis = New-FallbackAnalysis -Changes $changes -Bump $bump
}
else {
    try {
        & (Join-Path $PSScriptRoot "call-deepseek.ps1") -InputJsonPath $changesPath | Set-Content -LiteralPath $analysisPath -Encoding UTF8
        $analysis = Get-Content -LiteralPath $analysisPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Warning "Falling back to local release analysis."
        $analysis = New-FallbackAnalysis -Changes $changes -Bump $bump
    }
}

if ($BumpOverride) {
    $analysis.recommended_bump = $BumpOverride
    $analysis.next_version = Add-Version -Version $changes.current_version -Bump $BumpOverride
}

$newSection = ConvertTo-ChangelogSection -Analysis $analysis
$releaseNotes = @(
    "# Creative Pipeline V$($analysis.next_version)"
    ""
    $analysis.summary_for_user
    ""
    $newSection
    ""
    "Source branch: $($changes.branch)"
    "Source commit: $($changes.last_commit)"
) -join "`r`n"

$releaseNotes | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8

$archivePreview = & (Join-Path $PSScriptRoot "create-archive.ps1") `
    -RepoRoot $RepoRoot `
    -ArchiveRoot $ArchiveRoot `
    -Version $analysis.next_version `
    -ReleaseNotesPath $releaseNotesPath `
    -DryRun | ConvertFrom-Json

$summary = [pscustomobject]@{
    dry_run = [bool]$DryRun
    current_version = $changes.current_version
    next_version = $analysis.next_version
    recommended_bump = $analysis.recommended_bump
    summary_for_user = $analysis.summary_for_user
    changed_file_count = @($changes.changed_files).Count
    archive_path = $archivePreview.archive_path
    release_notes_path = $releaseNotesPath
    risks = $analysis.risks
}

if ($DryRun) {
    $summary | ConvertTo-Json -Depth 8
    exit 0
}

if (-not $Approve) {
    Write-Host "Next version: $($analysis.next_version)"
    Write-Host "Archive path: $($archivePreview.archive_path)"
    $answer = Read-Host "Type YES to update VERSION.json, CHANGELOG.md, and create the archive"
    if ($answer -ne "YES") {
        throw "Release cancelled by user."
    }
}

New-Item -ItemType Directory -Path $ArchiveRoot -Force | Out-Null

$versionPath = Join-Path $RepoRoot "VERSION.json"
$versionInfo = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$versionInfo.version = $analysis.next_version
$versionInfo.status = "released"
$versionInfo | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $versionPath -Encoding UTF8

$changelogPath = Join-Path $RepoRoot "CHANGELOG.md"
Update-Changelog -Path $changelogPath -NewSection $newSection | Set-Content -LiteralPath $changelogPath -Encoding UTF8

$archiveResult = & (Join-Path $PSScriptRoot "create-archive.ps1") `
    -RepoRoot $RepoRoot `
    -ArchiveRoot $ArchiveRoot `
    -Version $analysis.next_version `
    -ReleaseNotesPath $releaseNotesPath | ConvertFrom-Json

[pscustomobject]@{
    dry_run = $false
    current_version = $changes.current_version
    next_version = $analysis.next_version
    recommended_bump = $analysis.recommended_bump
    archive_path = $archiveResult.archive_path
    release_notes_path = $releaseNotesPath
} | ConvertTo-Json -Depth 8
