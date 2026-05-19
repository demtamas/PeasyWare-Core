# ============================================================
# run_seeds.ps1
# Runs PeasyWare seed scripts in order.
#
# Usage:
#   .\run_seeds.ps1              <- runs all seeds
#   .\run_seeds.ps1 -Only 1,2   <- runs seeds 1 and 2 only
#   .\run_seeds.ps1 -Only 2     <- runs seed 2 only
#
# API key is read from PEASYWARE_API_KEY env var by default.
# ============================================================

param(
    [string]$BaseUrl = "http://localhost:5000",
    [string]$ApiKey  = $env:PEASYWARE_API_KEY,
    [int[]] $Only    = @()
)

if (-not $ApiKey) {
    Write-Error "No API key. Set PEASYWARE_API_KEY env var or pass -ApiKey <key>."
    exit 1
}

$seeds = @(
    [PSCustomObject]@{ Number = 1; Script = "002_seed_skus.ps1";      Label = "SKUs" }
    [PSCustomObject]@{ Number = 2; Script = "004_seed_inbounds.ps1";  Label = "Inbounds" }
    [PSCustomObject]@{ Number = 3; Script = "006_seed_outbound.ps1";  Label = "Outbound orders + shipments" }
)

$toRun = if ($Only.Count -gt 0) {
    $seeds | Where-Object { $Only -contains $_.Number }
} else {
    $seeds
}

if (-not $toRun) {
    Write-Host "No matching seeds found for: $($Only -join ', ')"
    exit 1
}

$failed = 0

foreach ($seed in $toRun) {
    $script = Join-Path $PSScriptRoot $seed.Script

    if (-not (Test-Path $script)) {
        Write-Host "[$($seed.Number)] $($seed.Label) - MISSING: $($seed.Script)" -ForegroundColor Red
        $failed++
        continue
    }

    Write-Host ""
    Write-Host "[$($seed.Number)] $($seed.Label)" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------"

    & $script -BaseUrl $BaseUrl -ApiKey $ApiKey

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { $failed++ }
}

Write-Host ""
Write-Host "============================================================"
if ($failed -gt 0) {
    Write-Host "Completed with $failed failure(s)." -ForegroundColor Red
    exit 1
}
else {
    Write-Host "All seeds completed successfully." -ForegroundColor Green
}
