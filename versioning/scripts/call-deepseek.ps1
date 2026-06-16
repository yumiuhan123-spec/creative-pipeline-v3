[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputJsonPath,

    [string]$PromptPath = "",
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA "CreativePipelineV3\versioning\config.json"),
    [string]$BaseUrl = "https://api.deepseek.com",
    [string]$Model = "deepseek-chat"
)

$ErrorActionPreference = "Stop"

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

if (-not $apiKey) {
    throw "DeepSeek API key not found. Set DEEPSEEK_API_KEY or create %LOCALAPPDATA%\CreativePipelineV3\versioning\config.json."
}

$prompt = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
$inputJson = Get-Content -LiteralPath $InputJsonPath -Raw -Encoding UTF8
$body = @{
    model = $Model
    temperature = 0.2
    response_format = @{ type = "json_object" }
    messages = @(
        @{
            role = "system"
            content = $prompt
        },
        @{
            role = "user"
            content = "Analyze this release candidate JSON:`n$inputJson"
        }
    )
} | ConvertTo-Json -Depth 10

$headers = @{
    Authorization = "Bearer $apiKey"
    "Content-Type" = "application/json"
}

$uri = $BaseUrl.TrimEnd("/") + "/chat/completions"
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body
$content = $response.choices[0].message.content
if (-not $content) {
    throw "DeepSeek returned an empty response."
}

$parsed = $content | ConvertFrom-Json
$parsed | ConvertTo-Json -Depth 10
