[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [string]$ArchiveRoot = "",
    [string]$ReleaseIntent = "",
    [ValidateSet("patch", "minor", "major")]
    [string]$BumpOverride = "",
    [int]$AiTimeoutSec = 90,
    [int]$MaxDiffChars = 12000,
    [int]$MaxFileChars = 3000,
    [int]$MaxSnapshotFiles = 12,
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

function Add-AnalysisRisk {
    param(
        [object]$Analysis,
        [string]$Risk
    )

    $risks = @($Analysis.risks)
    if ($risks -notcontains $Risk) {
        $risks += $Risk
    }
    $Analysis.risks = @($risks)
}

function Assert-ReleaseAnalysis {
    param(
        [object]$Analysis,
        [object]$Changes
    )

    $required = @(
        "recommended_bump",
        "current_version",
        "next_version",
        "summary_for_user",
        "changelog",
        "risks",
        "should_create_git_tag"
    )
    foreach ($name in $required) {
        if (-not ($Analysis.PSObject.Properties.Name -contains $name)) {
            throw "Release analysis missing required field: $name"
        }
    }

    if ($Analysis.recommended_bump -notin @("patch", "minor", "major")) {
        throw "Invalid recommended_bump: $($Analysis.recommended_bump)"
    }
    if ("$($Analysis.current_version)" -notmatch "^[0-9]+\.[0-9]+\.[0-9]+$") {
        throw "Invalid current_version in release analysis: $($Analysis.current_version)"
    }
    if ("$($Analysis.next_version)" -notmatch "^[0-9]+\.[0-9]+\.[0-9]+$") {
        throw "Invalid next_version in release analysis: $($Analysis.next_version)"
    }
    foreach ($name in @("added", "changed", "fixed", "removed")) {
        if (-not ($Analysis.changelog.PSObject.Properties.Name -contains $name)) {
            throw "Release analysis changelog missing field: $name"
        }
    }
    if (-not "$($Analysis.summary_for_user)".Trim()) {
        throw "Release analysis summary_for_user is empty."
    }
    if ($null -eq $Analysis.should_create_git_tag -or $Analysis.should_create_git_tag.GetType().Name -ne "Boolean") {
        throw "Release analysis should_create_git_tag must be boolean."
    }
}

function Normalize-ReleaseAnalysis {
    param(
        [object]$Analysis,
        [object]$Changes
    )

    Assert-ReleaseAnalysis -Analysis $Analysis -Changes $Changes

    if ($Analysis.current_version -ne $Changes.current_version) {
        Add-AnalysisRisk -Analysis $Analysis -Risk "AI current_version did not match VERSION.json; local version was used."
        $Analysis.current_version = $Changes.current_version
    }

    $expectedNext = Add-Version -Version $Changes.current_version -Bump $Analysis.recommended_bump
    if ($Analysis.next_version -ne $expectedNext) {
        Add-AnalysisRisk -Analysis $Analysis -Risk "AI next_version did not match recommended_bump; local semantic version calculation was used."
        $Analysis.next_version = $expectedNext
    }

    foreach ($name in @("added", "changed", "fixed", "removed")) {
        $Analysis.changelog.$name = @($Analysis.changelog.$name)
    }
    $Analysis.risks = @($Analysis.risks)

    return $Analysis
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

function Invoke-DeepSeekAnalysis {
    param(
        [string]$InputJsonPath,
        [string]$OutputJsonPath,
        [int]$TimeoutSec,
        [string]$WorkDir
    )

    $stdoutPath = Join-Path $WorkDir ("deepseek_stdout_" + ([guid]::NewGuid().ToString("N")) + ".json")
    $stderrPath = Join-Path $WorkDir ("deepseek_stderr_" + ([guid]::NewGuid().ToString("N")) + ".txt")
    $scriptPath = Join-Path $PSScriptRoot "call-deepseek.ps1"
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $scriptPath,
        "-InputJsonPath", $InputJsonPath,
        "-TimeoutSec", $TimeoutSec
    )

    try {
        $process = Start-Process -FilePath "powershell.exe" `
            -ArgumentList $arguments `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -NoNewWindow `
            -PassThru

        if (-not $process.WaitForExit($TimeoutSec * 1000)) {
            $process.Kill()
            throw "DeepSeek analysis timed out after $TimeoutSec seconds."
        }
        $process.Refresh()

        $stdout = if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
        }
        else {
            ""
        }
        $stderr = if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8
        }
        else {
            ""
        }

        if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
            throw "DeepSeek analysis failed with exit code $($process.ExitCode): $stderr $stdout"
        }
        if (-not $stdout.Trim()) {
            throw "DeepSeek analysis returned no JSON."
        }

        $stdout | Set-Content -LiteralPath $OutputJsonPath -Encoding UTF8
        return ($stdout | ConvertFrom-Json)
    }
    finally {
        if (Test-Path -LiteralPath $stdoutPath) { Remove-Item -LiteralPath $stdoutPath -Force }
        if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force }
    }
}

function New-AiReleaseInput {
    param(
        [object]$Changes,
        [string]$ReleaseIntent
    )

    [pscustomobject]@{
        task = "Compare the previous release with the current candidate and recommend a semantic version bump."
        release_intent = $ReleaseIntent
        repository = $Changes.repository
        current_version = $Changes.current_version
        branch = $Changes.branch
        last_release_tag = $Changes.last_release_tag
        release_range = $Changes.release_range
        last_commit = $Changes.last_commit
        commit_log = $Changes.commit_log
        changed_files = @($Changes.changed_files)
        diff_summary = $Changes.diff_summary
        name_status = [pscustomobject]@{
            committed = $Changes.committed_name_status
            worktree = $Changes.diff_name_status
            staged = $Changes.staged_name_status
        }
        previous_vs_current_files = @($Changes.content_snapshots)
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

function Assert-ReleaseReady {
    param(
        [string]$Version,
        [string]$ArchiveRoot
    )

    $branch = (Invoke-Git @("branch", "--show-current")) -join ""
    if ($branch -ne "main") {
        throw "Release must run on main. Current branch: $branch"
    }

    try {
        $aheadBehind = (Invoke-Git @("rev-list", "--left-right", "--count", "HEAD...@{upstream}")) -join ""
        if ($aheadBehind -match "^\s*(\d+)\s+(\d+)\s*$") {
            $behind = [int]$Matches[2]
            if ($behind -gt 0) {
                throw "Local branch is behind upstream by $behind commit(s). Pull or merge before release."
            }
        }
    }
    catch {
        throw $_
    }

    $tagName = "v$Version"
    $existingTags = @(Invoke-Git @("tag", "--list", $tagName))
    if ($existingTags.Count -gt 0) {
        throw "Git tag already exists: $tagName"
    }

    if (Test-Path -LiteralPath $ArchiveRoot) {
        $existingArchives = @(Get-ChildItem -LiteralPath $ArchiveRoot -Directory -Force |
            Where-Object { $_.Name -like "V$Version`_*" })
        if ($existingArchives.Count -gt 0) {
            throw "Archive already exists for version $Version`: $($existingArchives[0].FullName)"
        }
    }
}

function Complete-GitRelease {
    param(
        [string]$Version,
        [bool]$CreateTag
    )

    Invoke-Git @("add", "-A") | Out-Null
    $status = @(Invoke-Git @("status", "--porcelain=v1"))
    $commitHash = ""
    if ($status.Count -gt 0) {
        Invoke-Git @("commit", "-m", "Release v$Version") | Out-Null
        $commitHash = (Invoke-Git @("rev-parse", "HEAD")) -join ""
    }
    else {
        $commitHash = (Invoke-Git @("rev-parse", "HEAD")) -join ""
    }

    $tagName = ""
    if ($CreateTag) {
        $tagName = "v$Version"
        Invoke-Git @("tag", $tagName) | Out-Null
    }

    [pscustomobject]@{
        commit = $commitHash
        tag = $tagName
    }
}

if (-not $ArchiveRoot) {
    $ArchiveRoot = Get-DefaultArchiveRoot
}

$workDir = Join-Path $RepoRoot "versioning\.work"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$changesPath = Join-Path $workDir "changes.json"
$aiInputPath = Join-Path $workDir "ai-input.json"
$analysisPath = Join-Path $workDir "analysis.json"
$releaseNotesPath = Join-Path $workDir "RELEASE_NOTES.md"

& (Join-Path $PSScriptRoot "collect-changes.ps1") `
    -RepoRoot $RepoRoot `
    -MaxDiffChars $MaxDiffChars `
    -MaxFileChars $MaxFileChars `
    -MaxSnapshotFiles $MaxSnapshotFiles |
    Set-Content -LiteralPath $changesPath -Encoding UTF8
$changes = Get-Content -LiteralPath $changesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$aiInput = New-AiReleaseInput -Changes $changes -ReleaseIntent $ReleaseIntent
$aiInput | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $aiInputPath -Encoding UTF8

Assert-SafeRelease -RepoRoot $RepoRoot

$bump = if ($BumpOverride) { $BumpOverride } else { "patch" }
if ($SkipAI) {
    $analysis = New-FallbackAnalysis -Changes $changes -Bump $bump
}
else {
    try {
        $analysis = Invoke-DeepSeekAnalysis `
            -InputJsonPath $aiInputPath `
            -OutputJsonPath $analysisPath `
            -TimeoutSec $AiTimeoutSec `
            -WorkDir $workDir
    }
    catch {
        Write-Warning $_.Exception.Message
        Write-Warning "Falling back to local release analysis."
        $analysis = New-FallbackAnalysis -Changes $changes -Bump $bump
    }
}

if ($BumpOverride) {
    $analysis.recommended_bump = $BumpOverride
}
$analysis = Normalize-ReleaseAnalysis -Analysis $analysis -Changes $changes

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
    last_release_tag = $changes.last_release_tag
    release_range = $changes.release_range
    should_create_git_tag = $analysis.should_create_git_tag
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

Assert-ReleaseReady -Version $analysis.next_version -ArchiveRoot $ArchiveRoot

New-Item -ItemType Directory -Path $ArchiveRoot -Force | Out-Null

$versionPath = Join-Path $RepoRoot "VERSION.json"
$versionInfo = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$versionInfo.version = $analysis.next_version
$versionInfo.status = "released"
$versionInfo | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $versionPath -Encoding UTF8

$changelogPath = Join-Path $RepoRoot "CHANGELOG.md"
Update-Changelog -Path $changelogPath -NewSection $newSection | Set-Content -LiteralPath $changelogPath -Encoding UTF8

$gitRelease = Complete-GitRelease -Version $analysis.next_version -CreateTag $analysis.should_create_git_tag

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
    release_commit = $gitRelease.commit
    git_tag = $gitRelease.tag
    archive_path = $archiveResult.archive_path
    release_notes_path = $releaseNotesPath
} | ConvertTo-Json -Depth 8
