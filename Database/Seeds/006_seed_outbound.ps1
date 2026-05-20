# ============================================================
# 006_seed_outbound.ps1
# Reads 005_outbound.json and seeds orders and shipments via API.
#
# Per order:
#   1. POST /api/outbound/orders              (order + lines in one call)
#
# Per shipment:
#   1. POST /api/outbound/shipments           (shipment header)
#   2. POST /api/outbound/shipments/{ref}/orders  (one per linked order)
#
# Usage:
#   .\006_seed_outbound.ps1
#   .\006_seed_outbound.ps1 -BaseUrl "http://localhost:5001"
#   .\006_seed_outbound.ps1 -ApiKey "your-key"
#
# API key is read from PEASYWARE_API_KEY env var by default.
# ============================================================

param(
    [string]$BaseUrl = "http://localhost:5000",
    [string]$ApiKey  = $env:PEASYWARE_API_KEY
)

$dataFile = Join-Path $PSScriptRoot "005_outbound.json"

if (-not $ApiKey) {
    Write-Error "No API key. Set PEASYWARE_API_KEY env var or pass -ApiKey <key>."
    exit 1
}

if (-not (Test-Path $dataFile)) {
    Write-Error "Data file not found: $dataFile"
    exit 1
}

$headers = @{ "X-Api-Key" = $ApiKey }
$data    = Get-Content $dataFile -Raw | ConvertFrom-Json
$failed  = 0

function Invoke-Api {
    param([string]$Uri, [object]$Body)

    $response = $null
    $errMsg   = $null
    $status   = $null

    # Strip null values before sending — avoids deserialisation errors on nullable fields
    $cleanBody = @{}
    if ($Body -is [hashtable]) {
        foreach ($key in $Body.Keys) {
            if ($null -ne $Body[$key]) { $cleanBody[$key] = $Body[$key] }
        }
    } else {
        foreach ($key in $Body.PSObject.Properties.Name) {
            $val = $Body.$key
            if ($null -ne $val) { $cleanBody[$key] = $val }
        }
    }

    try {
        $response = Invoke-RestMethod `
            -Uri         $Uri `
            -Method      POST `
            -Headers     $headers `
            -Body        ($cleanBody | ConvertTo-Json -Depth 10 -Compress) `
            -ContentType "application/json"

        # Treat HTTP 200 with success:false as a failure
        if ($response -and $response.success -eq $false) {
            $errMsg   = $response.message
            $status   = 200
            $response = $null
        }
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
                # Show full validation errors if present
                if ($parsed.errors) {
                    $errMsg = ($parsed.errors | ConvertTo-Json -Compress)
                } elseif ($parsed.message) {
                    $errMsg = $parsed.message
                } else {
                    $errMsg = $raw
                }
            } catch { $errMsg = $raw }
        }
    }

    return [PSCustomObject]@{
        Response = $response
        Status   = $status
        Error    = $errMsg
    }
}

# ── Orders ────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Orders" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

foreach ($order in $data.Orders) {
    $r = Invoke-Api -Uri "$BaseUrl/api/outbound/orders" -Body $order

    if ($r.Response) {
        Write-Host "  OK  $($order.OrderRef) - $($r.Response.message)" -ForegroundColor Green
    }
    elseif ($r.Status -eq 409) {
        Write-Host "  --  $($order.OrderRef) - already exists, skipped." -ForegroundColor Yellow
    }
    else {
        Write-Host "  !!  $($order.OrderRef) - FAILED ($($r.Status)): $($r.Error)" -ForegroundColor Red
        $failed++
    }
}

# ── Shipments ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Shipments" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

foreach ($shipment in $data.Shipments) {
    $ref = $shipment.ShipmentRef

    $headerBody = @{
        ShipmentRef      = $shipment.ShipmentRef
        HaulierPartyCode = $shipment.HaulierPartyCode
        VehicleRef       = $shipment.VehicleRef
        Notes            = $shipment.Notes
    }

    $r = Invoke-Api -Uri "$BaseUrl/api/outbound/shipments" -Body $headerBody

    if ($r.Response) {
        Write-Host "  OK  $ref header - $($r.Response.message)" -ForegroundColor Green
    }
    elseif ($r.Status -eq 409) {
        Write-Host "  --  $ref header - already exists, skipped." -ForegroundColor Yellow
    }
    else {
        Write-Host "  !!  $ref header - FAILED ($($r.Status)): $($r.Error)" -ForegroundColor Red
        $failed++
        continue
    }

    foreach ($orderRef in $shipment.OrderRefs) {
        $r = Invoke-Api -Uri "$BaseUrl/api/outbound/shipments/$ref/orders" -Body @{ OrderRef = $orderRef }

        if ($r.Response) {
            Write-Host "  OK  $ref <- $orderRef - $($r.Response.message)" -ForegroundColor Green
        }
        elseif ($r.Status -eq 409) {
            Write-Host "  --  $ref <- $orderRef - already linked, skipped." -ForegroundColor Yellow
        }
        else {
            Write-Host "  !!  $ref <- $orderRef - FAILED ($($r.Status)): $($r.Error)" -ForegroundColor Red
            $failed++
        }
    }
}

Write-Host ""
Write-Host "============================================================"
if ($failed -gt 0) {
    Write-Host "Completed with $failed failure(s)." -ForegroundColor Red
    exit 1
}
else {
    Write-Host "Done." -ForegroundColor Green
}
