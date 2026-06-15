[CmdletBinding()]
param(
    [string]$CodexHome = "",
    [switch]$KeepBrowserProfile
)

$ErrorActionPreference = "Stop"
if (-not $CodexHome) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
}

$skill = Join-Path $CodexHome "skills\creative-pipeline-v3"
$runtime = Join-Path $env:LOCALAPPDATA "CreativePipelineV3\runtime"
$config = Join-Path $env:LOCALAPPDATA "CreativePipelineV3\install.json"
$profile = Join-Path $env:LOCALAPPDATA "CreativePipelineV3\EdgeProfile"

foreach ($path in @($skill, $runtime, $config)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}
if (-not $KeepBrowserProfile -and (Test-Path -LiteralPath $profile)) {
    Remove-Item -LiteralPath $profile -Recurse -Force
}

Write-Output '{"status":"uninstalled"}'
