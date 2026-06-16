[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$required = @(
    "README.md",
    "LICENSE",
    ".gitignore",
    "VERSION.json",
    "skill\creative-pipeline-v3\SKILL.md",
    "CHANGELOG.md",
    "docs\architecture.md",
    "docs\development.md",
    "docs\workflow-state.md",
    "docs\weak-codex-test.md",
    "tests\run-maintenance-tests.ps1",
    "versioning\README.md",
    "template\main-image-project\00_project\workflow.json",
    "template\main-image-project\00_project\project.config.json",
    "template\main-image-project\00_project\workflow.state.json",
    "template\main-image-project\可编辑工作流提示词\P1_输入盘点指令.md",
    "template\main-image-project\可编辑工作流提示词\P6_快速模式指令.md",
    "template\main-image-project\可编辑工作流提示词\P5_浏览器分发指令.md",
    "template\main-image-project\07_browser_jobs\scripts\distribute_prompts.mjs"
)

$errors = @()
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative))) {
        $errors += "Missing required file: $relative"
    }
}

$jsonFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -Filter *.json -File
foreach ($file in $jsonFiles) {
    try {
        Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    }
    catch {
        $errors += "Invalid JSON: $($file.FullName)"
    }
}

$forbidden = @(
    "C:\Users\bests",
    "D:\创意资产流水线"
)
$textFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
    Where-Object { $_.Extension -in @(".md", ".ps1", ".mjs", ".json", ".yaml", ".yml", ".cmd") }
foreach ($file in $textFiles) {
    if ($file.FullName -eq $PSCommandPath) {
        continue
    }

    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    foreach ($pattern in $forbidden) {
        if ($text.Contains($pattern)) {
            $errors += "Forbidden release text '$pattern' in $($file.FullName)"
        }
    }
}

$largeFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
    Where-Object { $_.Length -gt 50MB }
foreach ($file in $largeFiles) {
    $errors += "File larger than 50MB: $($file.FullName)"
}

$forbiddenFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -Force |
    Where-Object {
        $_.Name -in @("Cookies", "Login Data", "History", "Local State") -or
        $_.FullName -match "\\(edge_cdp_profile|browser_profile)\\"
    }
foreach ($file in $forbiddenFiles) {
    $errors += "Forbidden browser data: $($file.FullName)"
}

if (-not $env:CPV3_SKIP_MAINTENANCE_TESTS) {
    $maintenanceTests = Join-Path $repoRoot "tests\run-maintenance-tests.ps1"
    if (-not (Test-Path -LiteralPath $maintenanceTests)) {
        $errors += "Missing maintenance tests: tests\run-maintenance-tests.ps1"
    }
    else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $maintenanceTests -RepoRoot $repoRoot | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $errors += "Maintenance tests failed."
        }
    }
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

[pscustomobject]@{
    status = "release_valid"
    json_files = $jsonFiles.Count
    files = (Get-ChildItem -LiteralPath $repoRoot -Recurse -File).Count
} | ConvertTo-Json
