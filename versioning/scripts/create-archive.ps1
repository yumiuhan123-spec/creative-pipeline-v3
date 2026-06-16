[CmdletBinding()]
param(
    [string]$RepoRoot = "",
    [Parameter(Mandatory = $true)]
    [string]$ArchiveRoot,
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseNotesPath,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-RelativePath {
    param([string]$BasePath, [string]$FullPath)

    $base = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd("\")
    $full = $FullPath
    if (Test-Path -LiteralPath $FullPath) {
        $full = (Resolve-Path -LiteralPath $FullPath).Path
    }
    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($base.Length).TrimStart("\")
    }
    return $full
}

function Test-ExcludedPath {
    param([string]$RelativePath)

    $normalized = $RelativePath -replace "/", "\"
    $parts = $normalized -split "\\"

    if ($parts -contains ".git") { return $true }
    if ($normalized -match "(^|\\)versioning\\.work\\") { return $true }
    if ($parts -contains "node_modules") { return $true }
    if ($parts -contains "__pycache__") { return $true }
    if ($parts -contains ".vscode") { return $true }
    if ($parts -contains ".idea") { return $true }
    if ($parts -contains "EdgeProfile") { return $true }
    if ($parts -contains "browser_profile") { return $true }
    if ($parts -contains "edge_cdp_profile") { return $true }
    if ($normalized -match "(^|\\)07_browser_jobs\\(run_log\.jsonl|tab_assignments\.json|failures\\)") { return $true }
    if ($normalized -match "(^|\\)08_outputs\\") { return $true }
    if ($normalized -match "(^|\\)01_inputs\\(product_views|competitor_main_images|reviews|brand_assets|other_references)\\") { return $true }
    if ($normalized -match "(^|\\)(Cookies|Cookies-journal|Login Data.*|History.*|Local State)$") { return $true }
    if ($normalized -match "(^|\\)(Sessions|Session Storage)\\") { return $true }
    if ($normalized -match "(^|\\)\.env(\..*)?$") { return $true }
    if ($normalized -match "\.(pem|key|pyc)$") { return $true }
    if ($normalized -match "(^|\\)install\.json$") { return $true }

    return $false
}

function New-Slug {
    param([string]$Text)

    $slug = $Text -replace '[\\/:*?"<>|]', ""
    $slug = $slug -replace "\s+", ""
    if ($slug.Length -gt 24) {
        $slug = $slug.Substring(0, 24)
    }
    if (-not $slug) {
        $slug = "release"
    }
    return $slug
}

$releaseNotes = Get-Content -LiteralPath $ReleaseNotesPath -Raw -Encoding UTF8
$firstLine = (($releaseNotes -split "`r?`n") |
    Where-Object { $_.Trim() -and $_.Trim() -notmatch "^#" } |
    Select-Object -First 1)
$slug = New-Slug -Text $firstLine
$archiveName = "V$Version`_$(Get-Date -Format yyyy-MM-dd)_$slug"
$finalPath = Join-Path $ArchiveRoot $archiveName
$tempPath = Join-Path $ArchiveRoot (".tmp_" + $archiveName + "_" + ([guid]::NewGuid().ToString("N")))

$files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Force | Where-Object {
    $relative = Get-RelativePath -BasePath $RepoRoot -FullPath $_.FullName
    -not (Test-ExcludedPath -RelativePath $relative)
}

if ($DryRun) {
    [pscustomobject]@{
        dry_run = $true
        archive_path = $finalPath
        file_count = @($files).Count
    } | ConvertTo-Json -Depth 5
    exit 0
}

if (Test-Path -LiteralPath $finalPath) {
    throw "Archive already exists: $finalPath"
}

New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
try {
    foreach ($file in $files) {
        $relative = Get-RelativePath -BasePath $RepoRoot -FullPath $file.FullName
        $target = Join-Path $tempPath $relative
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }

    Copy-Item -LiteralPath $ReleaseNotesPath -Destination (Join-Path $tempPath "RELEASE_NOTES.md") -Force

    $manifestFiles = Get-ChildItem -LiteralPath $tempPath -Recurse -File -Force | ForEach-Object {
        $relative = Get-RelativePath -BasePath $tempPath -FullPath $_.FullName
        [pscustomobject]@{
            path = $relative
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    [pscustomobject]@{
        version = $Version
        created_at = (Get-Date).ToString("s")
        source_repository = (Resolve-Path -LiteralPath $RepoRoot).Path
        files = $manifestFiles
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempPath "RELEASE_MANIFEST.json") -Encoding UTF8

    Move-Item -LiteralPath $tempPath -Destination $finalPath

    [pscustomobject]@{
        dry_run = $false
        archive_path = $finalPath
        file_count = @($manifestFiles).Count
    } | ConvertTo-Json -Depth 5
}
catch {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Recurse -Force
    }
    throw
}
