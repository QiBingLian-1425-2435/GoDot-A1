from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = Path(r"G:\.Installed\Godot_v4.5.2-stable_win64.exe\Godot_v4.5.2-stable_win64_console.exe")


def main() -> int:
    parser = argparse.ArgumentParser(description="Render the Ground Zero overview used by the in-game global map.")
    parser.add_argument("--godot", type=Path, default=DEFAULT_ENGINE)
    args = parser.parse_args()
    output = ROOT / "assets" / "worlds" / "ground_zero" / "map_overview.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(args.godot), "--path", str(ROOT), "--resolution", "1600x900",
        "res://worlds/ground_zero/map_preview.tscn", "--", "--zone=surface",
        "--overview", "--topdown", f"--capture={output}",
    ]
    subprocess.run(command, check=True, cwd=ROOT)
    if not output.is_file() or output.stat().st_size == 0:
        raise RuntimeError(f"Map render was not created: {output}")
    manifest_path = output.parent / "asset_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["files"][output.name] = {
        "bytes": output.stat().st_size,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # Register the new external asset so ResourceLoader can use it immediately.
    subprocess.run(
        [str(args.godot), "--path", str(ROOT), "--editor", "--import"],
        check=True,
        cwd=ROOT,
    )
    print(f"Generated {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
