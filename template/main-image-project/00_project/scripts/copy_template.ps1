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

[pscustomobject]@{
    status = "created"
    project = $destinationFull
    project_id = $id
    project_name = $name
} | ConvertTo-Json
