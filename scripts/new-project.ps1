[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [string]$ProjectName = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$template = Join-Path $repoRoot "template\main-image-project"
$copyScript = Join-Path $template "00_project\scripts\copy_template.ps1"

if (-not (Test-Path -LiteralPath $copyScript -PathType Leaf)) {
    throw "Template copy script not found: $copyScript"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $copyScript `
    -Destination $Destination `
    -ProjectName $ProjectName
if ($LASTEXITCODE -ne 0) {
    throw "Project creation failed."
}
