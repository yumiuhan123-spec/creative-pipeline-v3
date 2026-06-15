[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runtime = Join-Path $env:LOCALAPPDATA "CreativePipelineV3\runtime"
$codexNodeRoot = Join-Path $HOME ".cache\codex-runtimes\codex-primary-runtime\dependencies\node"
$codexNode = Join-Path $codexNodeRoot "bin\node.exe"
$codexModules = Join-Path $codexNodeRoot "node_modules"
$skill = if ($env:CODEX_HOME) {
    Join-Path $env:CODEX_HOME "skills\creative-pipeline-v3"
}
else {
    Join-Path $HOME ".codex\skills\creative-pipeline-v3"
}

$node = Get-Command node -ErrorAction SilentlyContinue
$npm = Get-Command npm -ErrorAction SilentlyContinue
$edgeCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
)
$edge = $edgeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

[pscustomobject]@{
    repository = $repoRoot
    node = if ($node) { $node.Source } elseif (Test-Path -LiteralPath $codexNode) { $codexNode } else { $null }
    npm = if ($npm) { $npm.Source } else { $null }
    edge = $edge
    skill_installed = (Test-Path -LiteralPath (Join-Path $skill "SKILL.md"))
    playwright_installed = (
        (Test-Path -LiteralPath (Join-Path $runtime "node_modules\playwright")) -or
        (Test-Path -LiteralPath (Join-Path $codexModules "playwright")) -or
        (Test-Path -LiteralPath (Join-Path $codexModules ".pnpm"))
    )
    template_available = (Test-Path -LiteralPath (Join-Path $repoRoot "template\main-image-project\00_project\workflow.json"))
} | ConvertTo-Json
