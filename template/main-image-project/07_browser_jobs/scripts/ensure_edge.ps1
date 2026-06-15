[CmdletBinding()]
param(
    [string]$CdpEndpoint = "http://127.0.0.1:9222",
    [string]$TargetUrl = "https://chatgpt.com/",
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = "Stop"

function Get-CdpVersion {
    try {
        return Invoke-RestMethod -Uri "$CdpEndpoint/json/version" -TimeoutSec 2
    }
    catch {
        return $null
    }
}

$version = Get-CdpVersion
if ($version) {
    [pscustomobject]@{
        status = "already_running"
        endpoint = $CdpEndpoint
        browser = $version.Browser
        profile = "$env:LOCALAPPDATA\CreativePipelineV3\EdgeProfile"
    } | ConvertTo-Json
    exit 0
}

$edgeCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
)
$edge = $edgeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $edge) {
    throw "Microsoft Edge executable was not found."
}

$profile = "$env:LOCALAPPDATA\CreativePipelineV3\EdgeProfile"
New-Item -ItemType Directory -Path $profile -Force | Out-Null

$arguments = @(
    "--remote-debugging-port=9222",
    "--user-data-dir=$profile",
    "--no-first-run",
    "--new-window",
    $TargetUrl
)

Start-Process -FilePath $edge -ArgumentList $arguments

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    Start-Sleep -Milliseconds 500
    $version = Get-CdpVersion
} until ($version -or (Get-Date) -ge $deadline)

if (-not $version) {
    throw "Edge started, but CDP did not become available at $CdpEndpoint within $TimeoutSeconds seconds."
}

[pscustomobject]@{
    status = "started"
    endpoint = $CdpEndpoint
    browser = $version.Browser
    profile = $profile
    target_url = $TargetUrl
} | ConvertTo-Json
