#!/usr/bin/env pwsh
# ==========================================================
# PeasyWare SQL Test Runner
# Runs all *.sql files in Database/Tests/ against the DB
# defined in PEASYWARE_DB.
#
# Each script uses BEGIN TRAN / ROLLBACK -- tests are non-
# destructive. RAISERROR inside a script causes sqlcmd -b
# to return non-zero, which is treated as a failure.
#
# Usage:
#   .\run_db_tests.ps1
#   .\run_db_tests.ps1 -Filter "fefo"   # run matching tests only
# ==========================================================

param(
    [string] $Filter = ""
)

$connStr = $env:PEASYWARE_DB
if (-not $connStr) {
    Write-Host "ERROR: PEASYWARE_DB environment variable is not set." -ForegroundColor Red
    exit 1
}

# Parse connection string into sqlcmd args
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($connStr)
$server    = $builder["Data Source"]
$db        = $builder["Initial Catalog"]
$trusted   = $builder["Integrated Security"] -eq $true
$trustCert = $builder["TrustServerCertificate"] -eq $true

$authArg = if ($trusted) { "-E" } else {
    $user = $builder["User ID"]
    $pass = $builder["Password"]
    "-U `"$user`" -P `"$pass`""
}
$certArg = if ($trustCert) { "-C" } else { "" }

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: sqlcmd not found on PATH." -ForegroundColor Red
    exit 1
}

$testDir = Join-Path $PSScriptRoot "Database\Tests"
$scripts  = Get-ChildItem -Path $testDir -Filter "*.sql" | Sort-Object Name

if ($Filter) {
    $scripts = $scripts | Where-Object { $_.Name -like "*$Filter*" }
}

if ($scripts.Count -eq 0) {
    Write-Host "No test scripts found$(if ($Filter) { " matching '$Filter'" })." -ForegroundColor Yellow
    exit 0
}

$divider = "-" * 60

Write-Host ""
Write-Host "PeasyWare SQL Tests" -ForegroundColor Cyan
Write-Host "Server: $server  DB: $db" -ForegroundColor DarkGray
Write-Host $divider

$passed = 0
$failed = 0
$errors = @()

foreach ($script in $scripts) {
    $name = $script.BaseName
    Write-Host "  $name ... " -NoNewline

    $output   = & sqlcmd -S "$server" -d "$db" $authArg.Split(" ") $certArg -I -i "$($script.FullName)" -b 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "PASS" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "FAIL" -ForegroundColor Red
        $failed++
        $errors += [PSCustomObject]@{ Test = $name; Output = ($output -join "`n") }
    }
}

Write-Host $divider
Write-Host "Results: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Failures:" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host "  [$($e.Test)]" -ForegroundColor Yellow
        Write-Host "  $($e.Output)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

exit $failed
