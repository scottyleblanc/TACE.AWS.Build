#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Module configuration ──────────────────────────────────────────────────────

$configPath = Join-Path $PSScriptRoot 'config' 'tace.aws.build.config.json'
if (-not (Test-Path $configPath)) {
    throw "TACE.AWS.Build module configuration not found: $configPath"
}
$script:Config = Get-Content $configPath -Raw | ConvertFrom-Json

$script:DefaultRegion  = $script:Config.DefaultRegion
$script:DefaultProfile = $script:Config.DefaultProfile

# ── Load private functions ────────────────────────────────────────────────────

$privateFunctions = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)
foreach ($function in $privateFunctions) {
    try {
        . $function.FullName
    }
    catch {
        throw "Failed to load private function $($function.FullName): $($_.Exception.Message)"
    }
}

# ── Load public functions ─────────────────────────────────────────────────────

$publicFunctions = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
foreach ($function in $publicFunctions) {
    try {
        . $function.FullName
    }
    catch {
        throw "Failed to load public function $($function.FullName): $($_.Exception.Message)"
    }
}
