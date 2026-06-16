[CmdletBinding()]
param(
    [string]$ProjectDir = "",
    [string]$StartDir = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
function Test-Project([string]$Path) {
    return (
        (Test-Path -LiteralPath (Join-Path $Path "00_project\workflow.json") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path "00_project\status.json") -PathType Leaf)
    )
}

if ($ProjectDir) {
    $resolved = (Resolve-Path -LiteralPath $ProjectDir).Path
    if (-not (Test-Project $resolved)) {
        throw "Not a V3 project: $resolved"
    }
}
else {
    $cursor = [System.IO.DirectoryInfo]::new([System.IO.Path]::GetFullPath($StartDir))
    $resolved = $null
    while ($cursor) {
        if (Test-Project $cursor.FullName) {
            $resolved = $cursor.FullName
            break
        }
        $cursor = $cursor.Parent
    }
    if (-not $resolved) {
        throw "No Creative Pipeline V3 project was found."
    }
}

$workflow = Get-Content -LiteralPath (Join-Path $resolved "00_project\workflow.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$status = Get-Content -LiteralPath (Join-Path $resolved "00_project\status.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$projectConfigPath = Join-Path $resolved "00_project\project.config.json"
$workflowStatePath = Join-Path $resolved "00_project\workflow.state.json"
$projectConfig = if (Test-Path -LiteralPath $projectConfigPath -PathType Leaf) {
    Get-Content -LiteralPath $projectConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $null
}
$workflowState = if (Test-Path -LiteralPath $workflowStatePath -PathType Leaf) {
    Get-Content -LiteralPath $workflowStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $null
}
$phase = $workflow.phases | Where-Object { $_.id -eq $status.phase } | Select-Object -First 1
if (-not $phase) {
    throw "Unknown current phase: $($status.phase)"
}

[pscustomobject]@{
    project = $resolved
    phase = $phase.id
    phase_name = $phase.name
    instruction = (Join-Path $resolved $phase.instruction)
    gate = $phase.gate
    state = $status.state
    next_action = $status.next_action
    project_name = if ($projectConfig) { $projectConfig.project_name } else { $null }
    workflow_state = if ($workflowState) { $workflowState.current_stage } else { $null }
} | ConvertTo-Json
