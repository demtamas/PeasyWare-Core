# ============================================================
# 004_seed_inbounds.ps1
# Reads 003_inbounds.json and seeds inbound deliveries via API.
#
# Per inbound:
#   1. POST /api/inbound                   (header)
#   2. POST /api/inbound/{ref}/lines       (one per line)
#   3. POST /api/inbound/{ref}/units       (if expected units present)
#
# Usage:
#   .\004_seed_inbounds.ps1
#   .\004_seed_inbounds.ps1 -BaseUrl "http://localhost:5001"
#   .\004_seed_inbounds.ps1 -ApiKey "your-key"
#
# API key is read from PEASYWARE_API_KEY env var by default.
# ============================================================

param(
    [string]$BaseUrl = "http://localhost:5000",
    [string]$ApiKey  = $env:PEASYWARE_API_KEY
)

$dataFile = Join-Path $PSScriptRoot "003_inbounds.json"

if (-not $ApiKey) {
    Write-Error "No API key. Set PEASYWARE_API_KEY env var or pass -ApiKey <key>."
    exit 1
}

if (-not (Test-Path $dataFile)) {
    Write-Error "Data file not found: $dataFile"
    exit 1
}

$headers  = @{ "X-Api-Key" = $ApiKey }
$inbounds = Get-Content $dataFile -Raw | ConvertFrom-Json
$ok       = 0
$failed   = 0

function Invoke-Api {
    param([string]$Uri, [object]$Body)

    $response = $null
    $errMsg   = $null
    $status   = $null

    try {
        $response = Invoke-RestMethod `
            -Uri         $Uri `
            -Method      POST `
            -Headers     $headers `
            -Body        ($Body | ConvertTo-Json -Depth 10 -Compress) `
            -ContentType "application/json"
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        $errMsg = $_.Exception.Message

        $stream = $_.Exception.Response.GetResponseStream()
        if ($stream) {
            $reader = [System.IO.StreamReader]::new($stream)
            $raw    = $reader.ReadToEnd()
            try { $errMsg = ($raw | ConvertFrom-Json).message } catch { }
        }
    }

    return [PSCustomObject]@{
        Response = $response
        Status   = $status
        Error    = $errMsg
    }
}

foreach ($inbound in $inbounds) {
    $ref = $inbound.InboundRef
    Write-Host ""
    Write-Host "Inbound: $ref" -ForegroundColor Cyan

    # 1. Header
    $headerBody = @{
        InboundRef        = $inbound.InboundRef
        SupplierPartyCode = $inbound.SupplierPartyCode
        HaulierPartyCode  = $inbound.HaulierPartyCode
        ExpectedArrivalAt = $inbound.ExpectedArrivalAt
    }

    $r = Invoke-Api -Uri "$BaseUrl/api/inbound" -Body $headerBody

    if ($r.Response) {
        Write-Host "  OK  Header - $($r.Response.message)" -ForegroundColor Green
    }
    elseif ($r.Status -eq 409) {
        Write-Host "  --  Header - already exists, skipped." -ForegroundColor Yellow
    }
    else {
        Write-Host "  !!  Header - FAILED ($($r.Status)): $($r.Error)" -ForegroundColor Red
        $failed++
        continue
    }

    # 2. Lines
    foreach ($line in $inbound.Lines) {
        $lineBody = @{
            SkuCode            = $line.SkuCode
            ExpectedQty        = $line.ExpectedQty
            BatchNumber        = $line.BatchNumber
            BestBeforeDate     = $line.BestBeforeDate
            ArrivalStockStatus = $line.ArrivalStockStatus
        }

        $r = Invoke-Api -Uri "$BaseUrl/api/inbound/$ref/lines" -Body $lineBody

        if ($r.Response) {
            Write-Host "  OK  Line $($line.SkuCode) x$($line.ExpectedQty) - $($r.Response.message)" -ForegroundColor Green
        }
        else {
            Write-Host "  !!  Line $($line.SkuCode) - FAILED ($($r.Status)): $($r.Error)" -ForegroundColor Red
            $failed++
            continue
        }

        # 3. Expected units (only if present)
        if ($line.ExpectedUnits -and $line.ExpectedUnits.Count -gt 0) {
            $unitsBody = @{
                Units = $line.ExpectedUnits
            }

            $r = Invoke-Api -Uri "$BaseUrl/api/inbound/$ref/units" -Body $unitsBody

            if ($r.Response) {
                Write-Host "  OK  Units - $($r.Response.message)" -ForegroundColor Green
            }
            else {
                Write-Host "  !!  Units - FAILED ($($r.Status)): $($r.Error)" -ForegroundColor Red
                $failed++
            }
        }
    }

    $ok++
}

Write-Host ""
Write-Host "Done. $ok inbound(s) OK, $failed failure(s)."
if ($failed -gt 0) { exit 1 }
