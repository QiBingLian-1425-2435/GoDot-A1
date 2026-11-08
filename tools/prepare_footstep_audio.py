"""Restore Kenney CC0 footsteps and soften their transients for the game.

Requires FFmpeg (--ffmpeg); only the Python standard library is used otherwise.
The downloaded archive and all audio remain external to Git.
"""
import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PAGE = "https://kenney.nl/assets/impact-sounds"
ARCHIVE_SHA = "029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8"


def restore(ffmpeg):
    cache = ROOT / "artifacts/dependencies/kenney_impact_sounds.zip"
    cache.parent.mkdir(parents=True, exist_ok=True)
    if not cache.exists() or hashlib.sha256(cache.read_bytes()).hexdigest() != ARCHIVE_SHA:
        headers = {"User-Agent": "Mozilla/5.0", "Referer": PAGE}
        endpoint = "https://kenney.nl/download-link/" + b"assets/impact-sounds".hex()
        request = urllib.request.Request(endpoint, headers=headers)
        with urllib.request.urlopen(request, timeout=30) as response:
            url = json.load(response)["url"]
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != ARCHIVE_SHA:
            raise RuntimeError("Unexpected archive version; review source before replacing audio")
        cache.write_bytes(data)
    output = ROOT / "assets/audio/footsteps"
    output.mkdir(parents=True, exist_ok=True)
    files = {}
    with zipfile.ZipFile(cache) as archive:
        (output / "license.txt").write_bytes(archive.read("License.txt"))
        for index in range(5):
            source = f"Audio/footstep_concrete_{index:03}.ogg"
            # Gentle filtering removes the sharp high-frequency click, retaining
            # the recorded sole/body texture. No synthetic layer is added.
            result = subprocess.run([
                ffmpeg, "-v", "error", "-i", "pipe:0", "-ac", "1", "-ar", "44100",
                "-af", "highpass=f=70,lowpass=f=2400", "-f", "s16le", "pipe:1",
            ], input=archive.read(source), capture_output=True, check=True)
            samples = array.array("h", result.stdout)
            if sys.byteorder != "little":
                samples.byteswap()
            rms = math.sqrt(sum(float(v) ** 2 for v in samples) / len(samples))
            gain = min(0.065 * 32767 / max(rms, 1), 0.55 * 32767 / max(map(abs, samples)))
            for i, value in enumerate(samples):
                envelope = min(1.0, i / 132, (len(samples) - 1 - i) / 265)
                samples[i] = round(value * gain * envelope)
            if sys.byteorder != "little":
                samples.byteswap()
            name = f"concrete_{index:02}.wav"
            with wave.open(str(output / name), "wb") as wav:
                wav.setparams((1, 2, 44100, 0, "NONE", "not compressed"))
                wav.writeframes(samples.tobytes())
            data = (output / name).read_bytes()
            files[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "source": source}
    data = (output / "license.txt").read_bytes()
    files["license.txt"] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    manifest = {"source": PAGE, "creator": "Kenney", "license": "CC0-1.0",
                "archive_sha256": ARCHIVE_SHA,
                "processing": "mono 44100 Hz PCM16, HP70/LP2400, RMS <=0.065, peak <=0.55, 3/6 ms fades",
                "files": files}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Restored {len(files) - 1} footsteps to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg"))
    args = parser.parse_args()
    if not args.ffmpeg:
        parser.error("FFmpeg not found: pass --ffmpeg with its executable path")
    restore(args.ffmpeg)
