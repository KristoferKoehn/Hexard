#!/usr/bin/env pwsh
# Installs the pinned Godot toolchain into tools/godot (git-ignored).
#
#   ./install-godot.ps1
#
# The engine is pinned so the whole team builds and tests against the same
# version. Bump the version and hash together, deliberately.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$version = '4.7.2'
$tag = "$version-stable"
$archive = "Godot_v${tag}_win64.exe.zip"
$url = "https://github.com/godotengine/godot/releases/download/$tag/$archive"
# sha256 of the archive, recorded when this pin was created.
$sha256 = '731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953'

$downloadDir = Join-Path $root 'tools/_download'
$installDir = Join-Path $root 'tools/godot'
$archivePath = Join-Path $downloadDir $archive

New-Item -ItemType Directory -Force -Path $downloadDir, $installDir | Out-Null
# Keep Godot from scanning the 180 MB toolchain as project assets.
Set-Content -Path (Join-Path $root 'tools/.gdignore') -Value '' -NoNewline

if (-not (Test-Path $archivePath)) {
    Write-Host "downloading $archive ..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing
    } catch {
        Write-Host "Invoke-WebRequest failed ($($_.Exception.Message)); retrying with curl.exe"
        & curl.exe -sSL --fail -o $archivePath $url
        if ($LASTEXITCODE -ne 0) { throw "download failed" }
    }
} else {
    Write-Host "archive already present: $archivePath"
}

$actual = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash.ToLowerInvariant()
if ($actual -ne $sha256) {
    throw "sha256 mismatch for $archive`n  expected $sha256`n  actual   $actual"
}
Write-Host "sha256 verified"

Expand-Archive -Path $archivePath -DestinationPath $installDir -Force
$exe = Join-Path $installDir "Godot_v${tag}_win64_console.exe"
Write-Host "installed: $exe"
& $exe --version
Write-Host "done — run ./run_tests.ps1"
