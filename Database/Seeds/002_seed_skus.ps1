# ============================================================
# 002_seed_skus.ps1
# Reads 001_skus.json and POSTs each SKU to the PeasyWare API.
#
# Usage:
#   .\002_seed_skus.ps1
#   .\002_seed_skus.ps1 -BaseUrl "http://localhost:5001"
#   .\002_seed_skus.ps1 -ApiKey "your-key"
#
# API key is read from PEASYWARE_API_KEY env var by default.
# ============================================================

param(
    [string]$BaseUrl = "http://localhost:5000",
    [string]$ApiKey  = $env:PEASYWARE_API_KEY
)

$endpoint = "$BaseUrl/api/skus"
$dataFile = Join-Path $PSScriptRoot "001_skus.json"

if (-not $ApiKey) {
    Write-Error "No API key. Set PEASYWARE_API_KEY env var or pass -ApiKey <key>."
    exit 1
}

if (-not (Test-Path $dataFile)) {
    Write-Error "Data file not found: $dataFile"
    exit 1
}

$headers = @{ "X-Api-Key" = $ApiKey }
$skus    = Get-Content $dataFile -Raw | ConvertFrom-Json
$ok      = 0
$failed  = 0

foreach ($sku in $skus) {
    $body     = $sku | ConvertTo-Json -Compress
    $response = $null
    $errMsg   = $null
    $status   = $null

    try {
        $response = Invoke-RestMethod `
            -Uri         $endpoint `
            -Method      POST `
            -Headers     $headers `
            -Body        $body `
            -ContentType "application/json"
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        $errMsg = $_.Exception.Message

        $stream = $_.Exception.Response.GetResponseStream()
        if ($stream) {
            $reader = [System.IO.StreamReader]::new($stream)
            $raw    = $reader.ReadToEnd()
            try {
                $parsed = $raw | ConvertFrom-Json
                $errMsg = $parsed.message
            }
            catch { }
        }
    }

    if ($response) {
        Write-Host "  OK  $($sku.SkuCode) - $($response.message)" -ForegroundColor Green
        $ok++
    }
    elseif ($status -eq 409) {
        Write-Host "  --  $($sku.SkuCode) - already exists, skipped." -ForegroundColor Yellow
        $ok++
    }
    else {
        Write-Host "  !!  $($sku.SkuCode) - FAILED ($status): $errMsg" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Done. $ok OK, $failed failed."
if ($failed -gt 0) { exit 1 }
