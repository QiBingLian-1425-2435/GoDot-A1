param([string]$SourceDirectory)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$assetRoot = Join-Path $projectRoot 'assets'
# No argument validates the independent local assets; reference code is disposable.
if (-not $SourceDirectory) { $SourceDirectory = $assetRoot }
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'docs/assets/2026-10-18-assets_manifest.json') -Raw | ConvertFrom-Json
# Verify every source before copying so a wrong bundle cannot partially replace assets.
foreach ($asset in $manifest.files) {
    $source = Join-Path $SourceDirectory $asset.path
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing external asset: $source" }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $asset.sha256) { throw "Asset hash mismatch: $source" }
}
$resolvedSource = (Resolve-Path -LiteralPath $SourceDirectory).Path.TrimEnd([char[]]'\/')
$resolvedDestination = [IO.Path]::GetFullPath($assetRoot).TrimEnd([char[]]'\/')
if ($resolvedSource -eq $resolvedDestination) {
    Write-Output "Verified $($manifest.files.Count) local assets in $assetRoot. Reference code is not required."
    return
}
foreach ($asset in $manifest.files) {
    $source = Join-Path $SourceDirectory $asset.path
    $destination = Join-Path $projectRoot (Join-Path 'assets' $asset.path)
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
    # Texture import parameters (including mipmaps) travel with the external bundle.
    if (Test-Path -LiteralPath ($source + '.import')) { Copy-Item -LiteralPath ($source + '.import') -Destination ($destination + '.import') -Force }
}
Write-Output "Restored $($manifest.files.Count) verified external assets. Open the root project in Godot to reimport."
