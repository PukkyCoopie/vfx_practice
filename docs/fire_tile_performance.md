# Fire tile performance

Measured on 2026-09-23, Godot 4.7.1, GL Compatibility/OpenGL 3.3,
NVIDIA RTX 3080 Ti, 750 × 1000 render window, 109.5 px tiles, VSync off.
These are desktop measurements, **not mobile FPS predictions**.

## Cost and mobile assessment

Each tile uses two procedural shader draws, three GPU particle emitters with
13 particle slots total, and a roughly 110 × 110 letter mask rendered on demand.
Twenty tiles have 100 steady-state draw calls, 60 emitters and 260 particle slots.
The main shader evaluates 40 flame sheets per fragment; wind adds six curve
segments per sheet. Rear ribbons evaluate up to ten candidate births and eight
curve segments under wind. Fragment work is the primary concern, rather than
the visible particle count alone. Emitter and draw-call overhead still matters.

Twenty stationary tiles or a board with one flying tile are substantially cheaper
after optimization. Twenty wind-deformed tiles remain an expensive case for a
phone. A 60 FPS game has 16.67 ms for the entire frame; 30 FPS has 33.33 ms.
No phone was available, so stable mobile FPS or absence of thermal throttling
has not been established. Higher actual rendering resolution increases fragment
cost; doubling both dimensions of the rendered tiles roughly quadruples coverage.

## Changes

- Skip the main shader outside its mathematically zero-alpha boundary, before
  evaluating flame sheets. Bounds expand with wind.
- Skip rear ribbons where the opaque tile hides them, and outside conservative
  resting bounds. Wind keeps the full outer canvas available.
- Keep the letter mask on-demand after studio initialization, resume and capture
  restart. Previously the studio forced it to redraw every frame.
- Move constant particle turbulence uniforms and visibility bounds from the
  per-frame loop into layout updates.

Flame count, curve segment count, particles, sizes, motion and lifetime are unchanged.

## Measurements

The benchmark warms up 90 frames, then samples 360 frames covering six seconds
of shader animation phases. Instances use distinct time offsets. Wind scenarios
feed a fixed velocity into stationary instances to isolate deformation cost;
these do not measure tiles entering/leaving the viewport or gameplay CPU cost.
The root viewport GPU timer measures its render work, not total application CPU
time or a complete accounting of particle simulation and child viewports.

First matched-phase comparison, GPU milliseconds per frame (median):

| Scenario | Before | After |
| --- | ---: | ---: |
| 1 stationary | 0.192 | 0.094 |
| 20 stationary | 3.634 | 1.499 |
| 20, one wind-deformed | 3.705 | 1.596 |
| 20, all wind-deformed | 5.594 | 5.257 |

Stationary and one-moving cases improved by approximately 59% and 57% in this
comparison. Repeated runs showed substantial timing variability, especially for
wind: optimized all-wind medians ranged 3.63–5.26 ms, and unoptimized all-wind
medians 5.59–12.64 ms. Do not derive a precise wind speedup or phone FPS from
these measurements. No GPU clocks were locked and this was a shared desktop.
Draw calls remain unchanged. No per-tile memory estimate is claimed from the
process-wide memory monitor, which includes retained renderer allocations.

## Validation and reproduction

Nine before/after rendered image pairs (three times × no/light/strong wind)
matched pixel-for-pixel with particles hidden to isolate the shaders. Static
and strong-wind images were visually inspected. Letter W/A/empty, resize,
pause/resume, drag, click flight, retargeting and studio input tests passed.
Headless import passed. The previously invalid Frost Jet thumbnail import was
subsequently regenerated along with its GIF and sheet; studio validation now
loads the gallery without that resource error.

Run from repository root:

```powershell
. ./tools/find-godot.ps1
$godotBin = Find-Godot
& $godotBin --path ./godot --rendering-driver opengl3 --resolution 750x1000 --disable-vsync --script ../tools/tests/fire_tile_benchmark.gd
```

Results default to `user://fire_tile_perf.json`. Pass `-- --out=<absolute path>`
to choose the JSON destination. Optional `--baseline-dir=<absolute directory>`
loads saved pre-change flame and ribbon shaders for comparison.

Before shipping in Waw, profile a release build on the lowest supported phone
at its actual render resolution, with the rest of the board and UI active.
Test twenty stationary, one flying, and twenty flying tiles, including sustained
play for thermal behavior. If that misses the frame budget, the next larger
optimization is sharing pre-rendered animation for stationary tiles while
keeping the live deformable shader on flying tiles. That would introduce visual
and integration tradeoffs and is not part of this appearance-preserving change.
