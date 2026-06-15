[CmdletBinding()]
param(
    [string]$ProjectDir,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
if (-not $ProjectDir) {
    $ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
else {
    $ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
}

$nodeCandidates = @(
    $env:CODEX_NODE,
    (Join-Path $HOME ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"),
    (Get-Command node -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$node = $nodeCandidates | Select-Object -First 1
if (-not $node) {
    throw "Node.js was not found."
}

$script = Join-Path $PSScriptRoot "distribute_prompts.mjs"
if ($DryRun) {
    & $node $script "run" "--project-dir" $ProjectDir "--dry-run" "true"
    if ($LASTEXITCODE -ne 0) {
        throw "Browser distribution dry run failed."
    }
    exit 0
}

& $node $script "preflight" "--project-dir" $ProjectDir
if ($LASTEXITCODE -ne 0) {
    throw "Browser distribution preflight failed."
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "ensure_edge.ps1") | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Could not start or connect to the dedicated Edge session."
}

$arguments = @(
    $script,
    "run",
    "--project-dir",
    $ProjectDir
)
if ($DryRun) {
    $arguments += @("--dry-run", "true")
}

& $node @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Browser distribution failed."
}
