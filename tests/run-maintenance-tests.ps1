[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [switch]$IncludeDeepSeek
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = ""
    )

    $script:Results.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
    })
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-JsonCommand {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [scriptblock]$Assert
    )

    $oldSkip = $env:CPV3_SKIP_MAINTENANCE_TESTS
    $env:CPV3_SKIP_MAINTENANCE_TESTS = "1"
    try {
        $output = & powershell.exe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $oldSkip) {
            Remove-Item Env:\CPV3_SKIP_MAINTENANCE_TESTS -ErrorAction SilentlyContinue
        }
        else {
            $env:CPV3_SKIP_MAINTENANCE_TESTS = $oldSkip
        }
    }

    if ($exitCode -ne 0) {
        throw "$Name command failed: $output"
    }

    $text = ($output | Where-Object { "$_" -notmatch "^WARNING:" }) -join "`r`n"
    $json = $text | ConvertFrom-Json
    & $Assert $json
    Add-Result -Name $Name -Status "passed"
    return $json
}

function Test-ProjectManagerStatus {
    $script = Join-Path $RepoRoot "project-manager\scripts\project-manager.ps1"
    Invoke-JsonCommand -Name "project-manager status" -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script, "status", "-RepoRoot", $RepoRoot
    ) -Assert {
        param($json)
        Assert-True ([bool]$json.versions.repo) "Missing repo version."
        Assert-True ($json.versions.repo -match "^[0-9]+\.[0-9]+\.[0-9]+$") "Repo version is not semantic."
        Assert-True (Test-Path -LiteralPath $json.rooms.development) "Development room is missing."
        Assert-True (Test-Path -LiteralPath $json.rooms.template) "Template room is missing."
        Assert-True (Test-Path -LiteralPath $json.rooms.archive) "Archive room is missing."
    } | Out-Null
}

function Test-ProjectManagerVersionMap {
    $script = Join-Path $RepoRoot "project-manager\scripts\project-manager.ps1"
    Invoke-JsonCommand -Name "project-manager version-map" -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script, "version-map", "-RepoRoot", $RepoRoot
    ) -Assert {
        param($json)
        Assert-True ([bool]$json.repo_version) "Missing repo_version."
        Assert-True (@($json.git_tags).Count -gt 0) "No Git tags reported."
        Assert-True ($null -ne $json.archive_versions) "Archive versions missing."
    } | Out-Null
}

function Test-ProjectManagerSyncTemplateDryRun {
    $script = Join-Path $RepoRoot "project-manager\scripts\project-manager.ps1"
    Invoke-JsonCommand -Name "project-manager sync-template dry-run" -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script, "sync-template", "-RepoRoot", $RepoRoot, "-DryRun"
    ) -Assert {
        param($json)
        Assert-True ($json.dry_run -eq $true) "sync-template did not run in dry-run mode."
        Assert-True (Test-Path -LiteralPath $json.source) "Template source is missing."
        Assert-True ([bool]$json.target) "Template target is missing."
    } | Out-Null
}

function Test-ProjectManagerSyncSkillDryRun {
    $script = Join-Path $RepoRoot "project-manager\scripts\project-manager.ps1"
    Invoke-JsonCommand -Name "project-manager sync-skill dry-run" -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script, "sync-skill", "-RepoRoot", $RepoRoot, "-DryRun"
    ) -Assert {
        param($json)
        Assert-True ($json.dry_run -eq $true) "sync-skill did not run in dry-run mode."
        Assert-True (Test-Path -LiteralPath $json.source) "Skill source is missing."
        Assert-True ([bool]$json.target) "Skill target is missing."
    } | Out-Null
}

function Test-ProjectManagerUpdateWorkbenchContextDryRun {
    $script = Join-Path $RepoRoot "project-manager\scripts\project-manager.ps1"
    Invoke-JsonCommand -Name "project-manager update-workbench-context dry-run" -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script, "update-workbench-context", "-RepoRoot", $RepoRoot, "-DryRun"
    ) -Assert {
        param($json)
        Assert-True ($json.dry_run -eq $true) "update-workbench-context did not run in dry-run mode."
        Assert-True ([bool]$json.path) "Workbench context path is missing."
        Assert-True ($json.repo_version -match "^[0-9]+\.[0-9]+\.[0-9]+$") "repo_version is not semantic."
    } | Out-Null
}

function Test-CollectChanges {
    $script = Join-Path $RepoRoot "versioning\scripts\collect-changes.ps1"
    Invoke-JsonCommand -Name "versioning collect-changes" -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script, "-RepoRoot", $RepoRoot, "-MaxSnapshotFiles", "2", "-MaxFileChars", "400", "-MaxDiffChars", "800"
    ) -Assert {
        param($json)
        Assert-True ($json.current_version -match "^[0-9]+\.[0-9]+\.[0-9]+$") "current_version is not semantic."
        Assert-True ($json.PSObject.Properties.Name -contains "changed_files") "changed_files is missing."
        Assert-True ($json.PSObject.Properties.Name -contains "content_snapshots") "content_snapshots is missing."
    } | Out-Null
}

function Test-ArchiveDryRun {
    $notes = Join-Path ([System.IO.Path]::GetTempPath()) ("cpv3_release_notes_" + ([guid]::NewGuid().ToString("N")) + ".md")
    $archiveRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("cpv3_archive_" + ([guid]::NewGuid().ToString("N")))
    try {
        "# Test release`r`n`r`nMaintenance test." | Set-Content -LiteralPath $notes -Encoding UTF8
        $script = Join-Path $RepoRoot "versioning\scripts\create-archive.ps1"
        Invoke-JsonCommand -Name "versioning create-archive dry-run" -Arguments @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script,
            "-RepoRoot", $RepoRoot,
            "-ArchiveRoot", $archiveRoot,
            "-Version", "0.0.0",
            "-ReleaseNotesPath", $notes,
            "-DryRun"
        ) -Assert {
            param($json)
            Assert-True ($json.dry_run -eq $true) "create-archive did not run in dry-run mode."
            Assert-True ($json.file_count -gt 0) "Archive dry-run found no files."
            Assert-True ($json.archive_path -like "*V0.0.0*") "Archive path does not include the test version."
        } | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $notes) { Remove-Item -LiteralPath $notes -Force }
        if (Test-Path -LiteralPath $archiveRoot) { Remove-Item -LiteralPath $archiveRoot -Recurse -Force }
    }
}

function Test-ReleaseDryRun {
    $script = Join-Path $RepoRoot "project-manager\scripts\project-manager.ps1"
    Invoke-JsonCommand -Name "project-manager release dry-run" -Arguments @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script,
        "release",
        "-RepoRoot", $RepoRoot,
        "-DryRun",
        "-SkipAI",
        "-BumpOverride", "patch",
        "-ReleaseIntent", "Maintenance test",
        "-AiTimeoutSec", "5",
        "-MaxSnapshotFiles", "2",
        "-MaxFileChars", "400",
        "-MaxDiffChars", "800"
    ) -Assert {
        param($json)
        Assert-True ($json.dry_run -eq $true) "release did not run in dry-run mode."
        Assert-True ($json.release_preview.next_version -match "^[0-9]+\.[0-9]+\.[0-9]+$") "release preview next_version is invalid."
        Assert-True ($json.template_sync_preview.dry_run -eq $true) "template sync preview did not run."
    } | Out-Null
}

function Test-DeepSeekOptional {
    if (-not $IncludeDeepSeek) {
        Add-Result -Name "deepseek adapter" -Status "skipped" -Detail "Use -IncludeDeepSeek to run the network test."
        return
    }

    $script = Join-Path $RepoRoot "versioning\scripts\call-deepseek.ps1"
    $inputPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cpv3_deepseek_input_" + ([guid]::NewGuid().ToString("N")) + ".json")
    $promptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cpv3_deepseek_prompt_" + ([guid]::NewGuid().ToString("N")) + ".txt")
    try {
        [pscustomobject]@{
            current_version = "0.0.0"
            diff_summary = "maintenance test"
        } | ConvertTo-Json | Set-Content -LiteralPath $inputPath -Encoding UTF8
        'Return only JSON: {"ok":true,"recommended_bump":"patch"}' |
            Set-Content -LiteralPath $promptPath -Encoding UTF8

        Invoke-JsonCommand -Name "deepseek adapter" -Arguments @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script,
            "-InputJsonPath", $inputPath,
            "-PromptPath", $promptPath,
            "-TimeoutSec", "20"
        ) -Assert {
            param($json)
            Assert-True ($json.ok -eq $true) "DeepSeek adapter did not return ok=true."
            Assert-True ($json.recommended_bump -eq "patch") "DeepSeek adapter did not return patch."
        } | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $inputPath) { Remove-Item -LiteralPath $inputPath -Force }
        if (Test-Path -LiteralPath $promptPath) { Remove-Item -LiteralPath $promptPath -Force }
    }
}

$tests = @(
    { Test-ProjectManagerStatus },
    { Test-ProjectManagerVersionMap },
    { Test-ProjectManagerSyncTemplateDryRun },
    { Test-ProjectManagerSyncSkillDryRun },
    { Test-ProjectManagerUpdateWorkbenchContextDryRun },
    { Test-CollectChanges },
    { Test-ArchiveDryRun },
    { Test-ReleaseDryRun },
    { Test-DeepSeekOptional }
)

foreach ($test in $tests) {
    try {
        & $test
    }
    catch {
        Add-Result -Name "maintenance test" -Status "failed" -Detail $_.Exception.Message
        [pscustomobject]@{
            status = "failed"
            results = $script:Results
        } | ConvertTo-Json -Depth 8
        exit 1
    }
}

[pscustomobject]@{
    status = "passed"
    include_deepseek = [bool]$IncludeDeepSeek
    results = $script:Results
} | ConvertTo-Json -Depth 8
