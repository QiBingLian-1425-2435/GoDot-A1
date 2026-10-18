"""Restore pinned official Windows x64 GodotSteam dependencies outside Git."""
import hashlib
import json
from pathlib import Path
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'docs/dependencies/2026-10-18-steam_runtime.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def setup():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    target = ROOT / 'addons/godotsteam'
    if all((target / name).is_file() and digest(target / name) == info['sha256']
           for name, info in manifest['files'].items()):
        print('STEAM_DEPENDENCIES_VERIFIED: GodotSteam ' + manifest['version'])
        return manifest
    archive = ROOT / 'artifacts/dependencies/godotsteam-4.23.1.tar.xz'
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.is_file():
        with urllib.request.urlopen(manifest['url'], timeout=90) as response:
            archive.write_bytes(response.read())
    if digest(archive) != manifest['archive_sha256']:
        raise RuntimeError('GodotSteam archive hash mismatch; do not load this dependency')
    with tarfile.open(archive) as package:
        for relative in manifest['files']:
            member = package.getmember('addons/godotsteam/' + relative)
            destination = (target / relative).resolve()
            if not destination.is_relative_to(target.resolve()) or not member.isfile():
                raise RuntimeError('Unsafe dependency archive entry')
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(package.extractfile(member).read())
    for name, info in manifest['files'].items():
        if digest(target / name) != info['sha256']:
            raise RuntimeError('GodotSteam native dependency mismatch: ' + name)
    print('STEAM_DEPENDENCIES_RESTORED: GodotSteam ' + manifest['version'])
    return manifest


if __name__ == '__main__':
    setup()
