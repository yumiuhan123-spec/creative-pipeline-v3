[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [string]$ProjectName = ""
)

$ErrorActionPreference = "Stop"
$templateRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$destinationFull = [System.IO.Path]::GetFullPath($Destination)
$templateFull = [System.IO.Path]::GetFullPath($templateRoot)

if ($destinationFull.StartsWith($templateFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Destination cannot be inside the standard template."
}
if (Test-Path -LiteralPath $destinationFull) {
    throw "Destination already exists: $destinationFull"
}

New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null
Copy-Item -Path (Join-Path $templateRoot "*") -Destination $destinationFull -Recurse -Force

$projectYaml = Join-Path $destinationFull "00_project\project.yaml"
$name = if ($ProjectName) { $ProjectName } else { Split-Path $destinationFull -Leaf }
$id = [guid]::NewGuid().ToString()
$created = (Get-Date).ToString("o")
$yaml = Get-Content -LiteralPath $projectYaml -Raw -Encoding UTF8
$yaml = $yaml -replace '(?m)^project_id:.*$', "project_id: `"$id`""
$yaml = $yaml -replace '(?m)^project_name:.*$', "project_name: `"$name`""
$yaml = $yaml -replace '(?m)^created_at:.*$', "created_at: `"$created`""
Set-Content -LiteralPath $projectYaml -Value $yaml -Encoding UTF8

$projectConfig = Join-Path $destinationFull "00_project\project.config.json"
if (Test-Path -LiteralPath $projectConfig -PathType Leaf) {
    $config = Get-Content -LiteralPath $projectConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.project_name = $name
    $config | Add-Member -NotePropertyName "project_id" -NotePropertyValue $id -Force
    $config | Add-Member -NotePropertyName "created_at" -NotePropertyValue $created -Force
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $projectConfig -Encoding UTF8
}

$workflowState = Join-Path $destinationFull "00_project\workflow.state.json"
if (Test-Path -LiteralPath $workflowState -PathType Leaf) {
    $state = Get-Content -LiteralPath $workflowState -Raw -Encoding UTF8 | ConvertFrom-Json
    $state.last_updated = $created
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $workflowState -Encoding UTF8
}

[pscustomobject]@{
    status = "created"
    project = $destinationFull
    project_id = $id
    project_name = $name
} | ConvertTo-Json
