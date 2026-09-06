# VFX Practice

Interactive Godot 4.7.1 (GL Compatibility) lab for VFX studies, wrapped in a React gallery and published to GitHub Pages.

Live site after Pages is enabled: https://pukkycoopie.github.io/vfx_practice/

## Layout

- `godot/` — studio scene, effect catalog, player assets
- `web/` — Vite + React thumbnail gallery that embeds the Godot Web export
- `tools/` — local Web export and thumbnail capture

`waw` in notes and chat means the game project at `C:\Users\2020\Documents\GodotProjects\words_and_wizards`. This repo is not that game.

## Requirements

- Godot 4.7.1 (this machine: `C:\Users\2020\Documents\GodotProjects\Godot_v4.7.1-stable_win64.exe`)
- Node 20+
- Optional: `GODOT_BIN` if Godot is not in the default location

## Open the studio

Open `godot/project.godot` in Godot 4.7.1. The main scene is a gray checkerboard stage with a 45-degree orbit camera.

- Left drag: orbit
- Right / middle drag: pan
- Scroll: zoom
- Space: pause / resume
- R: restart current effect
- Home: reset camera

## Add an effect

Each effect is its own scene. The studio never morphs one shared scene — clicking a thumbnail instances that effect under `VfxAnchor`.

1. Create a new `.tscn` under `godot/scenes/effects/` (no camera, lights, or environment; the studio already has those).
2. Append an entry to `godot/data/effects.json`:

```json
{
  "id": "fireball",
  "title": "Fireball",
  "scene": "res://scenes/effects/fireball.tscn",
  "thumb": "fireball.webp"
}
```

3. Capture thumbnails:

```powershell
powershell -File tools/capture_thumbs.ps1
```

## Local web preview

```powershell
powershell -File tools/export-web.ps1
cd web
npm install
npm run dev
```

## Deploy

Pushing `main` exports Godot to Web, builds the React app, and deploys GitHub Pages.

Enable once: repository **Settings → Pages → Source = GitHub Actions**.
