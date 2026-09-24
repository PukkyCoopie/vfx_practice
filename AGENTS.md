# Project instructions

These instructions apply throughout this repository. They consolidate the existing
Cursor rules in `.cursor/rules/waw.mdc` and `.cursor/rules/readme-gallery.mdc`.
Keep the shared constraints in those files and this file aligned when changing them.
The README gallery section below applies only when editing the gallery or tooling
that could affect it.

## Project identity and boundaries

- **waw** means the separate **Words & Wizards** game at
  `C:\Users\2020\Documents\GodotProjects\words_and_wizards`.
- This repository (`waw_vfx` / `vfx_practice`) is a standalone VFX learning lab,
  practice archive, and web portfolio. Do not treat it as the game repository.
- Copy player/VFX assets from waw when asked. Do not copy combat scripts unless
  the user requests them.
- All on-screen UI copy in this repository must remain English.
- Preserve existing uncommitted work and keep edits scoped to the requested task.

## Project map

- `godot/project.godot`: Godot project root; `res://` paths are relative to `godot/`.
  It declares Godot 4.7 features and the GL Compatibility renderer. The local
  discovery script and CI currently target Godot 4.7.1.
- `godot/scenes/studio/studio.tscn`: main scene; neighboring scripts implement
  the preview studio, UI, and orbit camera.
- `godot/scenes/effects/`: effect scenes and scripts.
- `godot/shaders/`: VFX and rendering shaders.
- `godot/scripts/vfx_bridge.gd`: the `VfxBridge` autoload.
- `godot/data/effects.json`: gallery catalog, scene paths, and capture/thumbnail
  metadata. Read it for the current effect list rather than assuming a fixed list.
- `godot/ui/`: gallery UI, theme, icons, fonts, and thumbnail sheets.
- `godot/assets/models/`: 3D models with separate usage restrictions (see below).
- `docs/gifs/`: README gallery animations.
- `tools/`: engine discovery, Web export/compression, and capture/encoding helpers.
- `web/`: generated Web build; `.github/workflows/pages.yml` exports and deploys
  GitHub Pages on pushes to `main` or manual workflow dispatch.
- `tmp/` and `godot/.godot/`: ignored scratch files and engine cache; do not commit
  these or generated Web build output (see `.gitignore`).

## Local commands and validation

Run these PowerShell commands from the repository root. `Find-Godot` checks
`GODOT_BIN`, known local installation paths, then `godot`/`godot4` on PATH.

```powershell
. ./tools/find-godot.ps1
$godotBin = Find-Godot
# Open the project in the editor.
& $godotBin --path ./godot --editor
# Import and check for engine-reported errors without opening a window.
& $godotBin --headless --path ./godot --import --quit
# Run the preview studio for visual checks.
& $godotBin --path ./godot
```

- For scene, script, or shader edits, inspect import errors and visually check
  the affected effect and relevant studio controls. Headless import alone does
  not establish visual correctness.
- For documentation-only edits, inspect the diff (including whitespace), links,
  gallery markup, and locked dates; exporting or regenerating assets is unnecessary.
- Web export: `./tools/export-web.ps1`. It imports the project, exports the `Web`
  preset into `web/`, installs the gzip loader, and compresses the build. Matching
  Godot export templates are required. Exporting locally does not deploy the site.
- Capture one effect: `./tools/capture_thumbs.ps1 -Effect flame_jet` (use an ID
  from `godot/data/effects.json`). Omitting `-Effect` captures all effects.
  Capture requires a graphical renderer, Python with Pillow, and `ffmpeg` on PATH.
  It writes frames to `tmp/capture/`, GIFs to `docs/gifs/`, thumbnail sheets to
  `godot/ui/thumbs/`, and updates effect metadata. Run it only when those generated
  assets need updating; it must not rewrite the README gallery.
- Report what was checked and any checks that could not be performed.

## Asset usage

Preserve the README license distinction: code, shaders, and VFX are freely usable
in personal and commercial projects without attribution. The paid AI-generated
3D models under `godot/assets/models/` remain the owner's property and must not be
copied, redistributed, or used in others' work without permission.

## README gallery

Keep the Gallery as a **pure HTML** `<table>`. Never convert it to a Markdown table (Markdown cannot do `colspan`, and the layout collapses).

- **Two effects per row.** Each effect uses two header cells (name, right-aligned date) and one GIF cell with `colspan="2"`.
- **Odd items start two new rows.** A third effect gets a new title row + GIF row; leave the right pair of cells empty until a fourth effect exists.
- Do not put Markdown `![]()` or blank lines inside `<td>`. Use `<img src="...">`.
- Capture/export scripts must not rewrite this table. Dates are hand-authored.

### Locked completion dates

Do **not** change these unless the user explicitly asks:

| Effect | Date |
|---|---|
| Fire Flame | `2026/09/07` |
| Water Jet | `2026/09/09` |
| Lightning Jet | `2026/09/11` |
| Frost Jet | `2026/09/12` |

When editing the gallery (adding rows, swapping GIFs, etc.), preserve every existing date cell exactly. Fire Flame in particular must stay `2026/09/07` — never restore `2026/09/08`.

```html
<tr>
<td><strong>Lightning Jet</strong></td>
<td align="right">2026/09/11</td>
<td></td>
<td></td>
</tr>
<tr>
<td colspan="2" align="center"><img src="docs/gifs/lightning_jet.gif" alt="Lightning Jet"></td>
<td colspan="2"></td>
</tr>
```
