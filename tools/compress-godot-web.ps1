$ErrorActionPreference = "Stop"

$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) "web"
$targets = @("index.wasm", "index.pck")

foreach ($name in $targets) {
    $src = Join-Path $outDir $name
    if (-not (Test-Path $src)) {
        continue
    }
    $dest = "$src.gz"
    $srcBytes = [System.IO.File]::ReadAllBytes($src)
    $outStream = [System.IO.File]::Create($dest)
    $gzip = New-Object System.IO.Compression.GZipStream($outStream, [System.IO.Compression.CompressionLevel]::Optimal)
    $gzip.Write($srcBytes, 0, $srcBytes.Length)
    $gzip.Dispose()
    $outStream.Dispose()
    Write-Host "Compressed $name -> $name.gz"
}
