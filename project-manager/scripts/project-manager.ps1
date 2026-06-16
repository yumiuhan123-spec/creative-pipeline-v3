[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("status", "version-map", "check-archives", "sync-template", "sync-skill", "update-workbench-context", "rebuild-archive", "release")]
    [string]$Command = "status",

    [string]$RepoRoot = "",
    [string]$WorkspaceRoot = "",
    [string]$WorkbenchRoot = "",
    [string]$CodexHome = "",
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
if (-not $WorkbenchRoot) {
    $WorkbenchRoot = Join-Path (Join-Path $HOME "Desktop") "标准开发工作台"
}
if (-not $CodexHome) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
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

function Get-FileHashText {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-InstalledSkillReport {
    $source = Join-Path $RepoRoot "skill\creative-pipeline-v3"
    $target = Join-Path $CodexHome "skills\creative-pipeline-v3"
    $sourceSkill = Join-Path $source "SKILL.md"
    $targetSkill = Join-Path $target "SKILL.md"
    $sourceHash = Get-FileHashText -Path $sourceSkill
    $targetHash = Get-FileHashText -Path $targetSkill

    [pscustomobject]@{
        name = "creative-pipeline-v3"
        source = $source
        target = $target
        source_exists = (Test-Path -LiteralPath $source -PathType Container)
        target_exists = (Test-Path -LiteralPath $target -PathType Container)
        source_hash = $sourceHash
        target_hash = $targetHash
        in_sync = ($sourceHash -and $targetHash -and $sourceHash -eq $targetHash)
    }
}

function Get-WorkbenchContextPath {
    return (Join-Path $WorkbenchRoot "项目上下文_精简版.md")
}

function Get-WorkbenchContextReport {
    $path = Get-WorkbenchContextPath
    $repoVersion = Get-CurrentVersion
    $git = Get-GitInfo
    $tags = @($git.tags)
    $content = if (Test-Path -LiteralPath $path -PathType Leaf) {
        Get-Content -LiteralPath $path -Raw -Encoding UTF8
    }
    else {
        ""
    }
    $tagLine = "已有 tags: " + (($tags | Sort-Object) -join ", ")

    [pscustomobject]@{
        path = $path
        exists = (Test-Path -LiteralPath $path -PathType Leaf)
        expected_version = $repoVersion
        expected_ahead = $git.ahead
        expected_tag_line = $tagLine
        in_sync = (
            $content.Contains($repoVersion) -and
            $content.Contains("本地 main 领先 origin/main $($git.ahead) 个提交") -and
            $content.Contains($tagLine)
        )
    }
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
    $installedSkill = Get-InstalledSkillReport
    $workbenchContext = Get-WorkbenchContextReport
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
    if (-not $installedSkill.in_sync) {
        $recommendations.Add("Installed Codex skill is behind source. Run sync-skill.")
    }
    if (-not $workbenchContext.in_sync) {
        $recommendations.Add("Workbench context is stale. Run update-workbench-context.")
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
        installed_skill = $installedSkill
        workbench_context = $workbenchContext
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

function Invoke-SyncSkill {
    $source = Join-Path $RepoRoot "skill\creative-pipeline-v3"
    $target = Join-Path $CodexHome "skills\creative-pipeline-v3"
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Missing skill source: $source"
    }

    $before = Get-InstalledSkillReport
    $result = [pscustomobject]@{
        dry_run = [bool]$DryRun
        source = $source
        target = $target
        before = $before
    }
    if ($DryRun) { return $result }
    if (-not $Approve) { throw "sync-skill requires -Approve or -DryRun." }

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
    Copy-Directory -Source $source -Destination $target

    $configRoot = Join-Path $env:LOCALAPPDATA "CreativePipelineV3"
    $runtimeRoot = Join-Path $configRoot "runtime"
    New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    [ordered]@{
        installed_at = (Get-Date).ToString("o")
        repository_root = $RepoRoot
        template_root = (Join-Path $RepoRoot "template\main-image-project")
        skill_path = $target
        runtime_root = $runtimeRoot
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $configRoot "install.json") -Encoding UTF8

    $result | Add-Member -NotePropertyName after -NotePropertyValue (Get-InstalledSkillReport)
    return $result
}

function Update-TextOrAppend {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Replacement
    )

    if ([regex]::IsMatch($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        return [regex]::Replace($Content, $Pattern, $Replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    }
    return ($Content.TrimEnd() + "`r`n" + $Replacement + "`r`n")
}

function Invoke-UpdateWorkbenchContext {
    $path = Get-WorkbenchContextPath
    $repoVersion = Get-CurrentVersion
    $sourceTemplate = Join-Path $RepoRoot "template\main-image-project"
    $sourceTemplateVersion = Get-TemplateVersion -TemplatePath $sourceTemplate
    $git = Get-GitInfo
    $tags = @($git.tags | Sort-Object)
    $tagLine = "已有 tags: " + ($tags -join ", ")
    $archiveLine = "v$repoVersion 已有档案室快照"
    $before = Get-WorkbenchContextReport

    $result = [pscustomobject]@{
        dry_run = [bool]$DryRun
        path = $path
        before = $before
        repo_version = $repoVersion
        template_version = $sourceTemplateVersion
        ahead = $git.ahead
        tags = $tags
    }
    if ($DryRun) { return $result }
    if (-not $Approve) { throw "update-workbench-context requires -Approve or -DryRun." }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Workbench context file not found: $path"
    }

    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $content = Update-TextOrAppend -Content $content `
        -Pattern "当前仓库版本：\s*```text\s*.*?\s*```" `
        -Replacement "当前仓库版本：`r`n`r`n```text`r`n$repoVersion`r`n```"
    $content = Update-TextOrAppend -Content $content `
        -Pattern "当前模板版本：\s*```text\s*.*?\s*```" `
        -Replacement "当前模板版本：`r`n`r`n```text`r`n$sourceTemplateVersion`r`n```"
    $content = [regex]::Replace($content, "这是正常状态：.*?所以模板仍是 .*?。", "这是正常状态：$repoVersion 是维护体系更新，没有改主图模板本体，所以模板仍是 $sourceTemplateVersion。")
    $content = [regex]::Replace($content, "本地 main 领先 origin/main \d+ 个提交", "本地 main 领先 origin/main $($git.ahead) 个提交")
    $content = [regex]::Replace($content, "已有 tags: .*", $tagLine)
    $content = [regex]::Replace($content, "v\d+\.\d+\.\d+ 已有档案室快照", $archiveLine)
    $content = [regex]::Replace($content, "1\. 本地 main 领先 GitHub \d+ 个提交，当前没有立即 push 需求。", "1. 本地 main 领先 GitHub $($git.ahead) 个提交，当前没有立即 push 需求。")
    if ($content -notmatch "项目管理器已经有 release 总控、DeepSeek 发布分析和维护测试层") {
        $content = [regex]::Replace($content, "2\. 项目管理器.*", "2. 项目管理器已经有 release 总控、DeepSeek 发布分析和维护测试层，并会检查/同步已安装 skill 与工作台上下文。")
    }

    Set-Content -LiteralPath $path -Value $content -Encoding UTF8
    $result | Add-Member -NotePropertyName after -NotePropertyValue (Get-WorkbenchContextReport)
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
    $skillPreview = $null
    $skillSync = $null
    $contextPreview = $null
    $contextUpdate = $null

    if ($DryRun) {
        $releaseArgs += "-DryRun"
        $releaseResult = Invoke-JsonScript -Arguments $releaseArgs
        $templatePreview = Invoke-SyncTemplate
        $skillPreview = Invoke-SyncSkill
        $contextPreview = Invoke-UpdateWorkbenchContext
        return [pscustomobject]@{
            dry_run = $true
            status_before = $before
            release_preview = $releaseResult
            template_sync_preview = $templatePreview
            skill_sync_preview = $skillPreview
            workbench_context_preview = $contextPreview
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

    $skillSync = Invoke-JsonScript -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $script,
        "sync-skill",
        "-RepoRoot", $RepoRoot,
        "-WorkspaceRoot", $WorkspaceRoot,
        "-WorkbenchRoot", $WorkbenchRoot,
        "-CodexHome", $CodexHome,
        "-Approve"
    )
    $contextUpdate = Invoke-JsonScript -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $script,
        "update-workbench-context",
        "-RepoRoot", $RepoRoot,
        "-WorkspaceRoot", $WorkspaceRoot,
        "-WorkbenchRoot", $WorkbenchRoot,
        "-CodexHome", $CodexHome,
        "-Approve"
    )

    $after = New-StatusReport
    return [pscustomobject]@{
        dry_run = $false
        status_before = $before
        release_result = $releaseResult
        template_sync_preview = $templatePreview
        template_sync_result = $templateSync
        skill_sync_result = $skillSync
        workbench_context_result = $contextUpdate
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
            installed_skill = $report.installed_skill
            workbench_context = $report.workbench_context
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
    "sync-skill" {
        Invoke-SyncSkill | ConvertTo-Json -Depth 10
    }
    "update-workbench-context" {
        Invoke-UpdateWorkbenchContext | ConvertTo-Json -Depth 10
    }
    "rebuild-archive" {
        Invoke-RebuildArchive | ConvertTo-Json -Depth 10
    }
    "release" {
        Invoke-Release | ConvertTo-Json -Depth 12
    }
}
