$ErrorActionPreference = "Stop"

. "$PSScriptRoot\find-godot.ps1"
$godotBin = Find-Godot

$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $root "godot"
$outDir = Join-Path $root "web\public\thumbs"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "Importing Godot project..."
& $godotBin --headless --path $project --import --quit
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Godot import failed with exit code $LASTEXITCODE"
}

Write-Host "Capturing effect thumbnails..."
& $godotBin --path $project --rendering-driver opengl3 -- --capture
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Godot thumbnail capture failed with exit code $LASTEXITCODE"
}

Write-Host "Thumbnails written to $outDir"
