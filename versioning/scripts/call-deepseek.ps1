[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputJsonPath,

    [string]$PromptPath = "",
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA "CreativePipelineV3\versioning\config.json"),
    [string]$BaseUrl = "https://api.deepseek.com",
    [string]$Model = "deepseek-chat",
    [int]$TimeoutSec = 60,
    [int]$MaxTokens = 0
)

$ErrorActionPreference = "Stop"

function Write-Trace {
    param([string]$Message)

    if ($env:CPV3_DEEPSEEK_TRACE) {
        Add-Content -LiteralPath $env:CPV3_DEEPSEEK_TRACE -Encoding UTF8 -Value ((Get-Date -Format "HH:mm:ss") + " " + $Message)
    }
}

function ConvertTo-JsonString {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "null" }
    $escaped = $Value.Replace("\", "\\")
    $escaped = $escaped.Replace('"', '\"')
    $escaped = $escaped.Replace("`r", "\r")
    $escaped = $escaped.Replace("`n", "\n")
    $escaped = $escaped.Replace("`t", "\t")
    return '"' + $escaped + '"'
}

Write-Trace "script started"

if (-not $PromptPath) {
    $PromptPath = Join-Path $PSScriptRoot "..\prompts\analyze-release.md"
}

function Read-LocalConfig {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    return $null
}

$config = Read-LocalConfig -Path $ConfigPath
$apiKey = $env:DEEPSEEK_API_KEY
if (-not $apiKey -and $config -and $config.deepseek_api_key) {
    $apiKey = $config.deepseek_api_key
}
if ($config -and $config.deepseek_base_url) {
    $BaseUrl = $config.deepseek_base_url
}
if ($config -and $config.deepseek_model) {
    $Model = $config.deepseek_model
}
if ($config -and $config.deepseek_timeout_sec) {
    $TimeoutSec = [int]$config.deepseek_timeout_sec
}
if ($config -and $config.deepseek_max_tokens) {
    $MaxTokens = [int]$config.deepseek_max_tokens
}

if (-not $apiKey) {
    throw "DeepSeek API key not found. Set DEEPSEEK_API_KEY or create %LOCALAPPDATA%\CreativePipelineV3\versioning\config.json."
}

$prompt = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
$inputJson = Get-Content -LiteralPath $InputJsonPath -Raw -Encoding UTF8
Write-Trace "loaded files"
Write-Verbose "Loaded prompt and input JSON."
$userContent = "Analyze this release candidate JSON:`n$inputJson"
$bodyParts = New-Object System.Collections.Generic.List[string]
$bodyParts.Add('"model":' + (ConvertTo-JsonString $Model))
$bodyParts.Add('"temperature":0.2')
$bodyParts.Add('"response_format":{"type":"json_object"}')
$bodyParts.Add(
    '"messages":[' +
    '{"role":"system","content":' + (ConvertTo-JsonString $prompt) + '},' +
    '{"role":"user","content":' + (ConvertTo-JsonString $userContent) + '}' +
    ']'
)
if ($MaxTokens -gt 0) {
    $bodyParts.Add('"max_tokens":' + $MaxTokens)
}
$body = "{" + ($bodyParts -join ",") + "}"
Write-Trace "built body"
Write-Trace "built body"
Write-Verbose "Built DeepSeek request body."

$uri = $BaseUrl.TrimEnd("/") + "/chat/completions"
$bodyPath = Join-Path ([System.IO.Path]::GetTempPath()) ("creative_pipeline_deepseek_" + ([guid]::NewGuid().ToString("N")) + ".json")
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($bodyPath, $body, $utf8NoBom)
    Write-Trace "wrote body file"
    Write-Verbose "Sending DeepSeek request to $uri with curl timeout $TimeoutSec seconds."
    $responseText = & curl.exe -sS --max-time $TimeoutSec `
        -X POST $uri `
        -H "Authorization: Bearer $apiKey" `
        -H "Content-Type: application/json" `
        --data-binary "@$bodyPath" 2>&1
    Write-Trace "curl returned exit $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) {
        throw "DeepSeek curl request failed with exit code $LASTEXITCODE`: $responseText"
    }
    $response = $responseText | ConvertFrom-Json
    Write-Trace "parsed response envelope"
}
finally {
    if (Test-Path -LiteralPath $bodyPath) {
        Remove-Item -LiteralPath $bodyPath -Force
    }
}

$content = $response.choices[0].message.content
if (-not $content) {
    throw "DeepSeek returned an empty response."
}

Write-Trace "parsing content"
Write-Verbose "Parsing DeepSeek JSON content."
$parsed = $content | ConvertFrom-Json
Write-Trace "script completed"
$parsed | ConvertTo-Json -Depth 10
