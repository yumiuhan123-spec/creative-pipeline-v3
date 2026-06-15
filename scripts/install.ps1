[CmdletBinding()]
param(
    [string]$CodexHome = "",
    [switch]$SkipNpmInstall
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not $CodexHome) {
    $CodexHome = if ($env:CODEX_HOME) {
        $env:CODEX_HOME
    }
    else {
        Join-Path $HOME ".codex"
    }
}

$skillSource = Join-Path $repoRoot "skill\creative-pipeline-v3"
$skillDestination = Join-Path $CodexHome "skills\creative-pipeline-v3"
$runtimeRoot = Join-Path $env:LOCALAPPDATA "CreativePipelineV3\runtime"
$configRoot = Join-Path $env:LOCALAPPDATA "CreativePipelineV3"
$codexNodeRoot = Join-Path $HOME ".cache\codex-runtimes\codex-primary-runtime\dependencies\node"
$codexModules = Join-Path $codexNodeRoot "node_modules"

if (-not (Test-Path -LiteralPath $skillSource -PathType Container)) {
    throw "Skill source not found: $skillSource"
}

New-Item -ItemType Directory -Path (Split-Path $skillDestination -Parent) -Force | Out-Null
if (Test-Path -LiteralPath $skillDestination) {
    Remove-Item -LiteralPath $skillDestination -Recurse -Force
}
Copy-Item -LiteralPath $skillSource -Destination $skillDestination -Recurse -Force

if (-not $SkipNpmInstall) {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot "package.json") -Destination $runtimeRoot -Force
        & $npm.Source install --prefix $runtimeRoot --omit=dev
        if ($LASTEXITCODE -ne 0) {
            throw "npm install failed."
        }
    }
    elseif (
        (Test-Path -LiteralPath (Join-Path $codexModules "playwright")) -or
        (Test-Path -LiteralPath (Join-Path $codexModules ".pnpm"))
    ) {
        $runtimeRoot = $codexNodeRoot
    }
    else {
        throw "Neither npm nor the Codex bundled Playwright runtime was found. Install Node.js 20 or newer, then rerun this script."
    }
}

New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
$config = [ordered]@{
    installed_at = (Get-Date).ToString("o")
    repository_root = $repoRoot
    template_root = (Join-Path $repoRoot "template\main-image-project")
    skill_path = $skillDestination
    runtime_root = $runtimeRoot
}
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $configRoot "install.json") -Encoding UTF8

[pscustomobject]@{
    status = "installed"
    skill = $skillDestination
    template = $config.template_root
    runtime = $runtimeRoot
} | ConvertTo-Json
