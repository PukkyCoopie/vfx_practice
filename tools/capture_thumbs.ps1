param(
    [string]$Effect = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\find-godot.ps1"
$godotBin = Find-Godot

$root = Split-Path $PSScriptRoot -Parent
$project = Join-Path $root "godot"
$outDir = Join-Path $root "godot\ui\thumbs"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root "tmp\capture") | Out-Null

Write-Host "Importing Godot project..."
& $godotBin --headless --path $project --import --quit
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Godot import failed with exit code $LASTEXITCODE"
}

Write-Host "Capturing gallery GIF frames..."
$godotArgs = @("--path", $project, "--rendering-driver", "opengl3", "--", "--capture")
if ($Effect) {
    $godotArgs += $Effect
    Write-Host "Filter: $Effect"
}
& $godotBin @godotArgs
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Godot thumbnail capture failed with exit code $LASTEXITCODE"
}

Write-Host "Encoding GIFs and gallery sheets..."
$encodeArgs = @(Join-Path $PSScriptRoot "encode_thumbs.py")
if ($Effect) {
    $encodeArgs += @("--id", $Effect)
}
python @encodeArgs
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "GIF encode failed with exit code $LASTEXITCODE"
}

Write-Host "Reimporting gallery sheets..."
& $godotBin --headless --path $project --import --quit
if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Godot reimport failed with exit code $LASTEXITCODE"
}

Write-Host "Gallery GIFs written to $(Join-Path $root 'docs\gifs')"
Write-Host "Gallery sheets written to $outDir"
