from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = Path(r"G:\.Installed\Godot_v4.5.2-stable_win64.exe\Godot_v4.5.2-stable_win64_console.exe")
MAP_CENTER = (390.0, -250.0)
MAP_WORLD_SIZE = (525.0 * 16.0 / 9.0, 525.0)
TILE_COLUMNS = 2
TILE_ROWS = 2
OVERVIEW_RESOLUTION = (1600, 900)
TILE_RESOLUTION = (2048, 1152)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render the Ground Zero overview used by the in-game global map.")
    parser.add_argument("--godot", type=Path, default=DEFAULT_ENGINE)
    args = parser.parse_args()
    output_dir = ROOT / "assets" / "worlds" / "ground_zero"
    output_dir.mkdir(parents=True, exist_ok=True)
    tile_width = MAP_WORLD_SIZE[0] / TILE_COLUMNS
    tile_height = MAP_WORLD_SIZE[1] / TILE_ROWS
    overview_output = output_dir / "map_overview.png"
    overview_command = [
        str(args.godot), "--path", str(ROOT),
        "--resolution", f"{OVERVIEW_RESOLUTION[0]}x{OVERVIEW_RESOLUTION[1]}",
        "res://worlds/ground_zero/map_preview.tscn", "--", "--zone=surface",
        "--overview", "--topdown", f"--overview-size={MAP_WORLD_SIZE[1]}",
        f"--overview-center={MAP_CENTER[0]},{MAP_CENTER[1]}", f"--capture={overview_output}",
    ]
    subprocess.run(overview_command, check=True, cwd=ROOT)
    if not overview_output.is_file() or overview_output.stat().st_size == 0:
        raise RuntimeError(f"Map overview was not created: {overview_output}")
    outputs: list[Path] = [overview_output]
    for row in range(TILE_ROWS):
        for column in range(TILE_COLUMNS):
            center_x = MAP_CENTER[0] + (column + 0.5 - TILE_COLUMNS / 2.0) * tile_width
            center_z = MAP_CENTER[1] + (row + 0.5 - TILE_ROWS / 2.0) * tile_height
            output = output_dir / f"map_overview_{column}_{row}.png"
            command = [
                str(args.godot), "--path", str(ROOT),
                "--resolution", f"{TILE_RESOLUTION[0]}x{TILE_RESOLUTION[1]}",
                "res://worlds/ground_zero/map_preview.tscn", "--", "--zone=surface",
                "--overview", "--topdown", f"--overview-size={tile_height}",
                f"--overview-center={center_x},{center_z}", f"--capture={output}",
            ]
            subprocess.run(command, check=True, cwd=ROOT)
            if not output.is_file() or output.stat().st_size == 0:
                raise RuntimeError(f"Map tile was not created: {output}")
            outputs.append(output)
    manifest_path = output_dir / "asset_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for output in outputs:
        manifest["files"][output.name] = {
            "bytes": output.stat().st_size,
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # Register the new external asset so ResourceLoader can use it immediately.
    subprocess.run(
        [str(args.godot), "--headless", "--path", str(ROOT), "--editor", "--import", "--quit-after", "10"],
        check=True,
        cwd=ROOT,
    )
    print(f"Generated one map overview and {len(outputs) - 1} high-resolution tiles in {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
