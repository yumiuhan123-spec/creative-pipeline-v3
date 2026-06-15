[CmdletBinding()]
param(
    [string]$ProjectDir
)

$ErrorActionPreference = "Stop"

if (-not $ProjectDir) {
    $ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
else {
    $ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
}

$workflowPath = Join-Path $ProjectDir "00_project\workflow.json"
$workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8 | ConvertFrom-Json
$inputRoot = Join-Path $ProjectDir $workflow.input_root
$outputPath = Join-Path $ProjectDir "02_inventory\input_manifest.json"
if (-not (Test-Path -LiteralPath $inputRoot -PathType Container)) {
    throw "Input folder not found: $inputRoot"
}

$files = Get-ChildItem -LiteralPath $inputRoot -File -Recurse |
    Where-Object { $_.Name -ne "放置说明.md" -and $_.Name -ne ".gitkeep" } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($ProjectDir.Length).TrimStart("\") -replace "\\", "/"
        $category = $relative.Split("/")[1]
        [ordered]@{
            path = $relative
            category = $category
            extension = $_.Extension.ToLowerInvariant()
            bytes = $_.Length
            modified_at = $_.LastWriteTime.ToString("o")
        }
    }

$counts = [ordered]@{}
foreach ($file in $files) {
    if (-not $counts.Contains($file.category)) {
        $counts[$file.category] = 0
    }
    $counts[$file.category] += 1
}

$manifest = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    project_root = $ProjectDir
    input_root = $workflow.input_root
    file_count = @($files).Count
    counts = $counts
    files = @($files)
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outputPath -Encoding UTF8
$manifest | ConvertTo-Json -Depth 6
