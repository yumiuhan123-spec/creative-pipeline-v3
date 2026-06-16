[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("status", "version-map", "check-archives", "sync-template", "rebuild-archive", "release")]
    [string]$Command = "status",

    [string]$RepoRoot = "",
    [string]$WorkspaceRoot = "",
    [string]$Tag = "",
    [string]$ReleaseIntent = "",
    [ValidateSet("", "patch", "minor", "major")]
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
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = (Resolve-Path (Join-Path $RepoRoot "..\..")).Path
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

function Get-RoomPath {
    param([string]$Prefix)

    $room = Get-ChildItem -LiteralPath $WorkspaceRoot -Directory -Force |
        Where-Object { $_.Name -like "$Prefix*" } |
        Select-Object -First 1
    if ($room) { return $room.FullName }
    return $null
}

function Get-TemplateTarget {
    $templateRoom = Get-RoomPath -Prefix "02_"
    if (-not $templateRoom) { return $null }

    $standardRoot = Get-ChildItem -LiteralPath $templateRoom -Directory -Force | Select-Object -First 1
    if (-not $standardRoot) { return $null }

    $template = Get-ChildItem -LiteralPath $standardRoot.FullName -Directory -Force |
        Where-Object { $_.Name -notmatch "_backup_|_sync_backup_|_before_" } |
        Select-Object -First 1
    if ($template) { return $template.FullName }
    return $null
}

function Get-ArchiveRoot {
    $archiveRoom = Get-RoomPath -Prefix "04_"
    if (-not $archiveRoom) { return $null }

    $archiveRoot = Get-ChildItem -LiteralPath $archiveRoom -Directory -Force | Select-Object -First 1
    if ($archiveRoot) { return $archiveRoot.FullName }
    return $null
}

function Get-TemplateVersion {
    param([string]$TemplatePath)

    if (-not $TemplatePath) { return $null }
    $configPath = Join-Path $TemplatePath "00_project\project.config.json"
    if (-not (Test-Path -LiteralPath $configPath)) { return $null }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return $config.template_version
}

function Get-CurrentVersion {
    $versionPath = Join-Path $RepoRoot "VERSION.json"
    if (-not (Test-Path -LiteralPath $versionPath)) { return $null }
    $version = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return $version.version
}

function Get-GitInfo {
    $branch = (Invoke-Git @("branch", "--show-current")) -join ""
    $status = @(Invoke-Git @("status", "--porcelain=v1"))
    $aheadBehind = (Invoke-Git @("rev-list", "--left-right", "--count", "HEAD...@{upstream}")) -join ""
    $ahead = $null
    $behind = $null
    if ($aheadBehind -match "^\s*(\d+)\s+(\d+)\s*$") {
        $ahead = [int]$Matches[1]
        $behind = [int]$Matches[2]
    }
    $tags = @(Invoke-Git @("tag", "--list"))

    [pscustomobject]@{
        branch = $branch
        dirty = ($status.Count -gt 0)
        changed_files = $status
        ahead = $ahead
        behind = $behind
        tags = $tags
    }
}

function Get-ArchiveVersions {
    $archiveRoot = Get-ArchiveRoot
    if (-not $archiveRoot) { return @() }

    $versions = Get-ChildItem -LiteralPath $archiveRoot -Directory -Force |
        Where-Object { $_.Name -match "^V([0-9]+(\.[0-9]+){1,2})(_|$)" } |
        ForEach-Object {
            [pscustomobject]@{
                version = $Matches[1]
                name = $_.Name
                path = $_.FullName
            }
        }
    return @($versions)
}

function Get-TagArchiveGaps {
    $git = Get-GitInfo
    $archives = Get-ArchiveVersions
    $archiveSet = @{}
    foreach ($archive in $archives) {
        $archiveSet[$archive.version] = $true
    }

    $gaps = @()
    foreach ($tag in $git.tags) {
        if ($tag -match "^v([0-9]+\.[0-9]+\.[0-9]+)$") {
            $version = $Matches[1]
            if (-not $archiveSet.ContainsKey($version)) {
                $gaps += [pscustomobject]@{
                    tag = $tag
                    version = $version
                }
            }
        }
    }
    return @($gaps)
}

function New-StatusReport {
    $devRoom = Get-RoomPath -Prefix "01_"
    $templateRoom = Get-RoomPath -Prefix "02_"
    $studioRoom = Get-RoomPath -Prefix "03_"
    $archiveRoom = Get-RoomPath -Prefix "04_"
    $templateTarget = Get-TemplateTarget
    $archiveRoot = Get-ArchiveRoot
    $sourceTemplate = Join-Path $RepoRoot "template\main-image-project"
    $repoVersion = Get-CurrentVersion
    $sourceTemplateVersion = Get-TemplateVersion -TemplatePath $sourceTemplate
    $targetTemplateVersion = Get-TemplateVersion -TemplatePath $templateTarget
    $git = Get-GitInfo
    $archives = Get-ArchiveVersions
    $gaps = Get-TagArchiveGaps
    $projects = @()
    if ($studioRoom) {
        $projects = @(Get-ChildItem -LiteralPath $studioRoom -Directory -Force | Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName "00_project\project.config.json")) -or
            (Test-Path -LiteralPath (Join-Path $_.FullName "00_project\workflow.json"))
        })
    }

    $recommendations = New-Object System.Collections.Generic.List[string]
    if (-not $devRoom -or -not $templateRoom -or -not $studioRoom -or -not $archiveRoom) {
        $recommendations.Add("Some four-room folders are missing.")
    }
    if ($sourceTemplateVersion -and $targetTemplateVersion -and $sourceTemplateVersion -ne $targetTemplateVersion) {
        $recommendations.Add("Template room is behind development template. Run sync-template.")
    }
    if ($gaps.Count -gt 0) {
        $recommendations.Add("Some Git tags do not have archive snapshots. Run check-archives, then rebuild-archive.")
    }
    if ($git.ahead -gt 0) {
        $recommendations.Add("Local Git has commits not pushed to upstream.")
    }
    if ($git.dirty) {
        $recommendations.Add("Working tree has uncommitted changes.")
    }
    if ($recommendations.Count -eq 0) {
        $recommendations.Add("Workspace looks consistent.")
    }

    [pscustomobject]@{
        workspace_root = $WorkspaceRoot
        rooms = [pscustomobject]@{
            development = $devRoom
            template = $templateRoom
            studio = $studioRoom
            archive = $archiveRoom
        }
        versions = [pscustomobject]@{
            repo = $repoVersion
            source_template = $sourceTemplateVersion
            template_room = $targetTemplateVersion
        }
        git = $git
        archives = [pscustomobject]@{
            root = $archiveRoot
            versions = $archives
            missing_tag_archives = @($gaps)
        }
        studio_projects = @($projects | ForEach-Object { $_.Name })
        recommendations = @($recommendations)
    }
}

function Assert-UnderPath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $base = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd("\")
    $resolvedTarget = if (Test-Path -LiteralPath $TargetPath) {
        (Resolve-Path -LiteralPath $TargetPath).Path
    }
    else {
        [System.IO.Path]::GetFullPath($TargetPath)
    }

    if (-not $resolvedTarget.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path outside expected base: $resolvedTarget"
    }

    return $resolvedTarget
}

function Copy-Directory {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring((Resolve-Path -LiteralPath $Source).Path.Length).TrimStart("\")
        $target = Join-Path $Destination $relative
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
        }
        else {
            $parent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }
}

function Invoke-SyncTemplate {
    $source = Join-Path $RepoRoot "template\main-image-project"
    $target = Get-TemplateTarget
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing source template: $source" }
    if (-not $target) { throw "Template target not found." }

    $templateRoom = Get-RoomPath -Prefix "02_"
    Assert-UnderPath -BasePath $templateRoom -TargetPath $target | Out-Null

    $backup = Join-Path (Split-Path -Parent $target) ((Split-Path -Leaf $target) + "_sync_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    $result = [pscustomobject]@{
        dry_run = [bool]$DryRun
        source = $source
        target = $target
        backup = $backup
        source_template_version = Get-TemplateVersion -TemplatePath $source
        target_template_version = Get-TemplateVersion -TemplatePath $target
    }

    if ($DryRun) { return $result }
    if (-not $Approve) { throw "sync-template requires -Approve or -DryRun." }

    Copy-Directory -Source $target -Destination $backup
    Remove-Item -LiteralPath $target -Recurse -Force
    Copy-Directory -Source $source -Destination $target
    return $result
}

function New-Manifest {
    param(
        [string]$Root,
        [string]$Version,
        [string]$TagName
    )

    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Where-Object { $_.Name -ne "RELEASE_MANIFEST.json" } |
        ForEach-Object {
            [pscustomobject]@{
                path = $_.FullName.Substring((Resolve-Path -LiteralPath $Root).Path.Length).TrimStart("\")
                bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }

    [pscustomobject]@{
        version = $Version
        tag = $TagName
        rebuilt_at = (Get-Date).ToString("s")
        files = $files
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Root "RELEASE_MANIFEST.json") -Encoding UTF8
}

function Invoke-RebuildArchive {
    if (-not $Tag) {
        $gaps = Get-TagArchiveGaps
        if ($gaps.Count -eq 1) {
            $Tag = $gaps[0].tag
        }
        elseif ($gaps.Count -gt 1) {
            throw "Multiple missing archives found. Pass -Tag explicitly."
        }
        else {
            throw "No missing archive tag found."
        }
    }
    if ($Tag -notmatch "^v([0-9]+\.[0-9]+\.[0-9]+)$") {
        throw "Only semantic tags like v3.2.0 are supported."
    }

    $version = $Matches[1]
    $archiveRoot = Get-ArchiveRoot
    if (-not $archiveRoot) { throw "Archive root not found." }

    $existing = @(Get-ArchiveVersions | Where-Object { $_.version -eq $version })
    if ($existing.Count -gt 0) {
        return [pscustomobject]@{
            skipped = $true
            reason = "Archive already exists."
            tag = $Tag
            version = $version
            archive_path = $existing[0].path
        }
    }

    $archivePath = Join-Path $archiveRoot ("V" + $version + "_" + (Get-Date -Format "yyyy-MM-dd") + "_rebuilt-from-" + $Tag)
    $tempZip = Join-Path (Join-Path $RepoRoot "project-manager\reports") ("archive_" + $Tag + "_" + ([guid]::NewGuid().ToString("N")) + ".zip")
    $tempDir = Join-Path (Join-Path $RepoRoot "project-manager\reports") ("archive_" + $Tag + "_" + ([guid]::NewGuid().ToString("N")))

    $result = [pscustomobject]@{
        dry_run = [bool]$DryRun
        tag = $Tag
        version = $version
        archive_path = $archivePath
    }
    if ($DryRun) { return $result }
    if (-not $Approve) { throw "rebuild-archive requires -Approve or -DryRun." }

    Assert-UnderPath -BasePath $archiveRoot -TargetPath $archivePath | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $tempZip) -Force | Out-Null
    try {
        Invoke-Git @("archive", "--format=zip", "--output", $tempZip, $Tag) | Out-Null
        Expand-Archive -LiteralPath $tempZip -DestinationPath $tempDir -Force
        Move-Item -LiteralPath $tempDir -Destination $archivePath
        "# Rebuilt archive for $Tag`r`n`r`nCreated from Git tag $Tag." |
            Set-Content -LiteralPath (Join-Path $archivePath "RELEASE_NOTES.md") -Encoding UTF8
        New-Manifest -Root $archivePath -Version $version -TagName $Tag
    }
    finally {
        if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force }
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    }
    return $result
}

function Invoke-JsonScript {
    param([string[]]$Arguments)

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & powershell.exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }

    if ($exitCode -ne 0) {
        throw "Command failed: powershell.exe $($Arguments -join ' ')`r`n$output"
    }

    $text = ($output | Where-Object { "$_" -notmatch "^WARNING:" }) -join "`r`n"
    if (-not $text.Trim()) { return $null }
    try {
        return $text | ConvertFrom-Json
    }
    catch {
        $start = $text.LastIndexOf("{")
        while ($start -ge 0) {
            $candidate = $text.Substring($start).Trim()
            try {
                return $candidate | ConvertFrom-Json
            }
            catch {
                if ($start -eq 0) { break }
                $start = $text.LastIndexOf("{", $start - 1)
            }
        }
        throw
    }
}

function Invoke-Release {
    $versionManager = Join-Path $RepoRoot "versioning\scripts\version-manager.ps1"
    if (-not (Test-Path -LiteralPath $versionManager)) {
        throw "Missing version manager: $versionManager"
    }

    $archiveRoot = Get-ArchiveRoot
    if (-not $archiveRoot) { throw "Archive root not found." }

    $before = New-StatusReport
    $releaseArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $versionManager,
        "-RepoRoot", $RepoRoot,
        "-ArchiveRoot", $archiveRoot
    )
    if ($ReleaseIntent) { $releaseArgs += @("-ReleaseIntent", $ReleaseIntent) }
    if ($BumpOverride) { $releaseArgs += @("-BumpOverride", $BumpOverride) }
    if ($AiTimeoutSec) { $releaseArgs += @("-AiTimeoutSec", $AiTimeoutSec) }
    if ($MaxDiffChars) { $releaseArgs += @("-MaxDiffChars", $MaxDiffChars) }
    if ($MaxFileChars) { $releaseArgs += @("-MaxFileChars", $MaxFileChars) }
    if ($MaxSnapshotFiles) { $releaseArgs += @("-MaxSnapshotFiles", $MaxSnapshotFiles) }
    if ($SkipAI) { $releaseArgs += "-SkipAI" }

    $templatePreview = $null
    $templateSync = $null

    if ($DryRun) {
        $releaseArgs += "-DryRun"
        $releaseResult = Invoke-JsonScript -Arguments $releaseArgs
        $templatePreview = Invoke-SyncTemplate
        return [pscustomobject]@{
            dry_run = $true
            status_before = $before
            release_preview = $releaseResult
            template_sync_preview = $templatePreview
        }
    }

    if (-not $Approve) {
        throw "release requires -DryRun or -Approve."
    }

    $releaseArgs += "-Approve"
    $releaseResult = Invoke-JsonScript -Arguments $releaseArgs

    $script = $PSCommandPath
    $templatePreview = Invoke-JsonScript -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $script,
        "sync-template",
        "-RepoRoot", $RepoRoot,
        "-WorkspaceRoot", $WorkspaceRoot,
        "-DryRun"
    )
    if (
        $templatePreview.source_template_version -and
        $templatePreview.target_template_version -and
        $templatePreview.source_template_version -ne $templatePreview.target_template_version
    ) {
        $templateSync = Invoke-JsonScript -Arguments @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $script,
            "sync-template",
            "-RepoRoot", $RepoRoot,
            "-WorkspaceRoot", $WorkspaceRoot,
            "-Approve"
        )
    }

    $after = New-StatusReport
    return [pscustomobject]@{
        dry_run = $false
        status_before = $before
        release_result = $releaseResult
        template_sync_preview = $templatePreview
        template_sync_result = $templateSync
        status_after = $after
    }
}

switch ($Command) {
    "status" {
        New-StatusReport | ConvertTo-Json -Depth 10
    }
    "version-map" {
        $report = New-StatusReport
        [pscustomobject]@{
            repo_version = $report.versions.repo
            source_template_version = $report.versions.source_template
            template_room_version = $report.versions.template_room
            git_tags = $report.git.tags
            archive_versions = $report.archives.versions
            missing_tag_archives = $report.archives.missing_tag_archives
        } | ConvertTo-Json -Depth 10
    }
    "check-archives" {
        [pscustomobject]@{
            archive_root = Get-ArchiveRoot
            missing_tag_archives = @(Get-TagArchiveGaps)
        } | ConvertTo-Json -Depth 10
    }
    "sync-template" {
        Invoke-SyncTemplate | ConvertTo-Json -Depth 10
    }
    "rebuild-archive" {
        Invoke-RebuildArchive | ConvertTo-Json -Depth 10
    }
    "release" {
        Invoke-Release | ConvertTo-Json -Depth 12
    }
}
