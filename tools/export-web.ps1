$ErrorActionPreference = "Stop"

. "$PSScriptRoot\find-godot.ps1"
$godotBin = Find-Godot

$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $root "godot"
$outDir = Join-Path $root "web\public\godot"
$outFile = Join-Path $outDir "index.html"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "Importing Godot project..."
& $godotBin --headless --path $project --import --quit
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Godot import failed with exit code $LASTEXITCODE"
}

Write-Host "Exporting Web build with: $godotBin"
& $godotBin --headless --path $project --export-release "Web" $outFile
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Godot export failed with exit code $LASTEXITCODE"
}

& "$PSScriptRoot\compress-godot-web.ps1"
Write-Host "Exported to $outDir"
