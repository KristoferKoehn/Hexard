#!/usr/bin/env pwsh
# Runs Hexard's headless core test suite. See docs/design.md §10.3.
#
#   ./run_tests.ps1
#
# Engine resolution order:
#   1. $env:HEXARD_GODOT  — explicit path to a Godot editor executable
#   2. tools/godot/...     — the pinned toolchain installed by install-godot.ps1
#   3. godot / godot4      — whatever is on PATH
#
# Exits 0 when every test passes, non-zero otherwise.
#
#   ./run_tests.ps1          unit suite + view smoke test
#   ./run_tests.ps1 -Soak    ... plus a 10,000-move randomised soak

param(
    [switch]$Soak
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$candidates = @()
if ($env:HEXARD_GODOT) { $candidates += $env:HEXARD_GODOT }
$candidates += (Join-Path $root 'tools/godot/Godot_v4.7.2-stable_win64_console.exe')
$candidates += (Join-Path $root 'tools/godot/Godot_v4.7.2-stable_win64.exe')
foreach ($name in @('godot', 'godot4')) {
    $found = Get-Command $name -ErrorAction SilentlyContinue
    if ($found) { $candidates += $found.Source }
}

$godot = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $godot) {
    Write-Host "Godot not found. Set HEXARD_GODOT, run ./install-godot.ps1, or add godot to PATH." -ForegroundColor Red
    exit 127
}

Write-Host "engine : $godot"

# Godot writes non-fatal diagnostics to stderr (under a restricted sandbox it
# cannot read the Windows certificate store, for example). PowerShell 5.1 turns
# native stderr into a *terminating* error while ErrorActionPreference is Stop,
# so relax it around the engine calls and check exit codes explicitly instead.
$ErrorActionPreference = 'Continue'

# Always import first: global class_name types (Ruleset, ScoringRules, ...) only
# resolve after the project has been scanned, and a stale cache produces
# confusing "Identifier not found" parse errors. Godot's import is incremental.
Write-Host "importing project ..."
& $godot --headless --path $root --import *> (Join-Path $root 'tools/logs/import.log')
if ($LASTEXITCODE -ne 0) {
    Write-Host "warning: project import exited with $LASTEXITCODE (continuing anyway)" -ForegroundColor Yellow
}

& $godot --headless --path $root --script res://tests/run_tests.gd
$unitExit = $LASTEXITCODE

Write-Host ""
& $godot --headless --path $root --script res://tests/smoke_scene.gd
$smokeExit = $LASTEXITCODE

if ($unitExit -ne 0 -or $smokeExit -ne 0) {
    Write-Host "SUITES FAILED (unit=$unitExit smoke=$smokeExit)" -ForegroundColor Red
    exit 1
}

if ($Soak) {
    Write-Host ""
    & $godot --headless --path $root --script res://tests/soak.gd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "SOAK FAILED" -ForegroundColor Red
        exit 1
    }
}

Write-Host "ALL SUITES PASSED" -ForegroundColor Green
exit 0
