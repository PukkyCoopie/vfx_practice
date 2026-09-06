$ErrorActionPreference = "Stop"

function Find-Godot {
    if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) {
        return $env:GODOT_BIN
    }

    $candidates = @(
        "C:\Users\2020\Documents\GodotProjects\Godot_v4.7.1-stable_win64_console.exe",
        "C:\Users\2020\Documents\GodotProjects\Godot_v4.7.1-stable_win64.exe",
        "C:\Users\2020\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe",
        "C:\Users\2020\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe"
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            return $path
        }
    }

    foreach ($name in @("godot", "godot4")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }

    throw "Godot 4.7.1 not found. Set GODOT_BIN to the Godot executable."
}
