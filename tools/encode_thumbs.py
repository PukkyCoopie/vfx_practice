from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

FPS = 12
SHEET_COLUMNS = 6
GALLERY_START = "<!-- gallery:start -->"
GALLERY_END = "<!-- gallery:end -->"
STALE_THUMBS = ("flame_breath.webp", "flame_breath.webp.import")


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def load_effects(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit("effects.json must be a JSON array")
    return data


def frame_paths(frame_dir: Path) -> list[Path]:
    return sorted(p for p in frame_dir.glob("*.png") if p.is_file())


def build_sheet(frames: list[Image.Image], columns: int) -> Image.Image:
    count = len(frames)
    cols = max(1, min(columns, count))
    rows = (count + cols - 1) // cols
    width, height = frames[0].size
    sheet = Image.new("RGB", (cols * width, rows * height), (17, 17, 17))
    for index, frame in enumerate(frames):
        rgb = frame.convert("RGB")
        x = (index % cols) * width
        y = (index // cols) * height
        sheet.paste(rgb, (x, y))
    return sheet


def encode_gif(frame_dir: Path, dest: Path, fps: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    pattern = str(frame_dir / "%04d.png")
    cmd = [
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-framerate",
        str(fps),
        "-i",
        pattern,
        "-filter_complex",
        "split[s0][s1];[s0]palettegen=max_colors=192:stats_mode=full[p];[s1][p]paletteuse=dither=sierra2_4a",
        str(dest),
    ]
    subprocess.run(cmd, check=True)


def update_effect_meta(effect: dict, frame_count: int, columns: int, fps: int) -> None:
    effect_id = str(effect.get("id", ""))
    effect["thumb"] = f"{effect_id}.webp"
    effect["thumb_frames"] = frame_count
    effect["thumb_columns"] = max(1, min(columns, frame_count))
    effect["thumb_fps"] = fps


def render_gallery(effects: list[dict], gif_dir: Path, root: Path) -> str:
    lines = [GALLERY_START, "## Gallery", ""]
    for effect in effects:
        effect_id = str(effect.get("id", ""))
        title = str(effect.get("title", effect_id))
        gif = gif_dir / f"{effect_id}.gif"
        if not effect_id or not gif.is_file():
            continue
        rel = gif.resolve().relative_to(root).as_posix()
        lines.append(f"### {title}")
        lines.append("")
        lines.append(f"![{title}]({rel})")
        lines.append("")
    lines.append(GALLERY_END)
    return "\n".join(lines)


def patch_readme(readme: Path, gallery: str) -> None:
    text = readme.read_text(encoding="utf-8")
    if GALLERY_START in text and GALLERY_END in text:
        start = text.index(GALLERY_START)
        end = text.index(GALLERY_END) + len(GALLERY_END)
        text = text[:start] + gallery + text[end:]
    else:
        text = text.rstrip() + "\n\n" + gallery + "\n"
    if not text.endswith("\n"):
        text += "\n"
    readme.write_text(text, encoding="utf-8", newline="\n")


def encode_all(root: Path, fps: int) -> None:
    capture_root = root / "tmp" / "capture"
    thumbs_dir = root / "godot" / "ui" / "thumbs"
    gif_dir = root / "docs" / "gifs"
    effects_path = root / "godot" / "data" / "effects.json"
    thumbs_dir.mkdir(parents=True, exist_ok=True)
    gif_dir.mkdir(parents=True, exist_ok=True)

    effects = load_effects(effects_path)
    encoded = 0
    for effect in effects:
        effect_id = str(effect.get("id", ""))
        if not effect_id:
            continue
        frames = frame_paths(capture_root / effect_id)
        if not frames:
            print(f"skip {effect_id}: no captured frames")
            continue
        images = [Image.open(path) for path in frames]
        try:
            columns = min(SHEET_COLUMNS, len(images))
            sheet = build_sheet(images, columns)
            sheet_path = thumbs_dir / f"{effect_id}.webp"
            sheet.save(sheet_path, "WEBP", lossless=True, quality=100, method=6)
            encode_gif(capture_root / effect_id, gif_dir / f"{effect_id}.gif", fps)
            update_effect_meta(effect, len(images), columns, fps)
            encoded += 1
            print(f"encoded {effect_id}: {len(images)} frames")
        finally:
            for image in images:
                image.close()

    effects_path.write_text(
        json.dumps(effects, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    for name in STALE_THUMBS:
        stale = thumbs_dir / name
        if stale.exists():
            stale.unlink()
            print(f"removed {stale.name}")
    if encoded == 0:
        print("no new GIFs encoded")


def main() -> int:
    parser = argparse.ArgumentParser(description="Encode gallery GIFs and update README.")
    parser.add_argument("--readme-only", action="store_true")
    parser.add_argument("--fps", type=int, default=FPS)
    args = parser.parse_args()

    root = repo_root()
    effects_path = root / "godot" / "data" / "effects.json"
    gif_dir = root / "docs" / "gifs"
    gif_dir.mkdir(parents=True, exist_ok=True)

    if not args.readme_only:
        encode_all(root, args.fps)

    effects = load_effects(effects_path)
    gallery = render_gallery(effects, gif_dir, root)
    patch_readme(root / "README.md", gallery)
    print("updated README gallery")
    return 0


if __name__ == "__main__":
    sys.exit(main())
