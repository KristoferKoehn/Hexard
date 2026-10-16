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
& $godot --headless --path $root --script res://tests/run_tests.gd
exit $LASTEXITCODE
