# MS-C fast quality gate (laptop-safe)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "==> ruff"
python -m ruff check sim models analysis tests demo

Write-Host "==> pytest"
python -m pytest tests/ -q

Write-Host "==> reproduce validate-only"
python -m sim.reproduce --validate-only

Write-Host "OK - MS-C check passed"
