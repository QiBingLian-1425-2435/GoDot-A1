"""Build a standalone Windows x64 Steam test bundle, without modifying source settings."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request
import uuid
import zipfile

from setup_steam import ROOT, setup


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8').strip()


def run_engine(engine, stage, arguments, log):
    result = subprocess.run([str(engine), '--headless', '--path', str(stage), *arguments],
                            capture_output=True, encoding='utf-8', errors='replace', timeout=180)
    output = result.stdout + result.stderr
    log.write_text(output, encoding='utf-8')
    errors = [line for line in output.splitlines()
              if line.startswith(('ERROR:', 'SCRIPT ERROR:')) and 'Safe save failed' not in line]
    if result.returncode or errors:
        raise RuntimeError(f'Godot failed; see {log}\n' + '\n'.join(errors))


def build(engine):
    native = setup()
    if not engine.is_file():
        raise RuntimeError('Pass --godot with the actual Godot 4.5.2 console executable')
    version = subprocess.check_output([str(engine), '--version']).decode().strip()
    if not version.startswith('4.5.2.'):
        raise RuntimeError('This build is pinned to Godot 4.5.2, got ' + version)
    for item in json.loads((ROOT / 'docs/assets/2026-10-18-assets_manifest.json').read_text(encoding='utf-8'))['files']:
        path = ROOT / 'assets' / item['path']
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest().upper() != item['sha256']:
            raise RuntimeError('Missing/changed external asset: ' + item['path'])
    runtime = [ROOT / 'project.godot']
    for directory in ['app', 'features', 'worlds', 'ui']:
        runtime.extend(path for path in (ROOT / directory).rglob('*') if path.is_file())
    # A source hash supplements the revision so rebuilding uncommitted work never reuses an old lobby build ID.
    hasher = hashlib.sha256()
    for path in sorted(runtime):
        hasher.update(path.relative_to(ROOT).as_posix().encode())
        hasher.update(path.read_bytes())
    hasher.update(json.dumps(native, sort_keys=True).encode())
    build_id = 'a1_' + git('rev-parse', '--short=12', 'HEAD') + '_' + hasher.hexdigest()[:12]
    output = ROOT / 'build' / ('lantern_a1_steam_' + build_id)
    if output.exists():
        # Never overwrite a package somebody might currently be testing.
        output = output.with_name(output.name + '_' + uuid.uuid4().hex[:6])
    output.mkdir(parents=True)
    stage = ROOT / 'artifacts' / ('steam_stage_' + uuid.uuid4().hex)
    stage.mkdir(parents=True)
    for name in ['app', 'features', 'worlds', 'ui', 'assets']:
        shutil.copytree(ROOT / name, stage / name)
    for name in native['files']:
        destination = stage / 'addons/godotsteam' / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'addons/godotsteam' / name, destination)
    config = (ROOT / 'project.godot').read_text(encoding='utf-8-sig')
    config = re.sub(r'^_mcp_game_helper=.*\n?', '', config, flags=re.M)
    config = re.sub(r'^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)\n?', '', config, flags=re.M)
    (stage / 'project.godot').write_text(config, encoding='utf-8')
    (stage / 'app/network/steam_config.cfg').write_text(
        f'[steam]\napp_id=480\nbuild_id="{build_id}"\n', encoding='utf-8')
    shutil.copy2(ROOT / 'export_presets.cfg', stage / 'export_presets.cfg')
    run_engine(engine, stage, ['--editor', '--import', '--quit'], output / 'import.log')
    run_engine(engine, stage, ['--export-pack', 'Windows Steam Test', str(output / 'lantern_a1.pck')], output / 'export.log')
    windowed = engine.with_name(engine.name.replace('_console.exe', '.exe'))
    if not windowed.is_file():
        raise RuntimeError('Windowed Godot runtime missing beside the console executable')
    shutil.copy2(windowed, output / 'lantern_a1.exe')
    shutil.copy2(engine, output / 'lantern_a1_console.exe')
    # Preserve the extension's exact res:// paths even with export-pack's shared-library layout.
    for name in native['files']:
        if name.endswith('.dll'):
            destination = output / 'addons/godotsteam' / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'addons/godotsteam' / name, destination)
    (output / 'steam_appid.txt').write_text('480\n', encoding='ascii')
    (output / 'start_steam.cmd').write_text(
        '@echo off\ncd /d "%~dp0"\nif not exist logs mkdir logs\nstart "" "lantern_a1.exe" --log-file "%~dp0logs/game.log"\n',
        encoding='ascii', newline='\r\n')
    (output / 'README.txt').write_text(f'''雾灯旅店 A1 · Steam 开发测试包
构建：{build_id}
环境：Windows x64 / Godot 4.5.2 / GodotSteam 4.23.1 / Steam App ID 480

1. 完整解压，保留 EXE、PCK、addons、DLL 与 steam_appid.txt；不要只转发 EXE。
2. 每人打开 Steam 并登录不同账号，建议先互加 Steam 好友。
3. 双击 start_steam.cmd（或 lantern_a1.exe）。房主选 Steam 联机并创建好友房间。
4. 房主点击邀请 Steam 好友，或复制房间号发给队友；队友填房间号加入。
5. 人员到齐后房主点全员出发。WASD 移动，E 拾取/长按救援，Tab 切换行囊。
6. 角色撤离后保持程序运行；房主退出会结束房间。不支持房主迁移、掉线续局。
7. 所有人必须使用同一测试包。开局后禁止加入；结束后可再探一局或返回准备。

这是使用 Spacewar App ID 480 的开发测试包，不是正式 Steam 发行包。
Steam Overlay 可用时支持邀请；覆盖层不可用时可用房间号加入，无需公网 IP 或端口映射。
若 Steam 提示许可/账号/网络错误，请记录界面错误和 logs/game.log；不要把账号密码发给开发者。
本机单账号初始化/大厅/房主传输检查不能证明双账号异地可玩；请按交付验收单实测。
''', encoding='utf-8')
    shutil.copy2(ROOT / 'addons/godotsteam/license.md', output / 'GODOTSTEAM_LICENSE.txt')
    for filename in ['LICENSE.txt', 'COPYRIGHT.txt']:
        cached = ROOT / 'artifacts/dependencies' / ('godot_4.5.2_' + filename)
        if not cached.is_file():
            url = 'https://raw.githubusercontent.com/godotengine/godot/4.5.2-stable/' + filename
            with urllib.request.urlopen(url, timeout=30) as response:
                cached.write_bytes(response.read())
        shutil.copy2(cached, output / ('GODOT_' + filename))
    metadata = {'build_id': build_id, 'source_commit': git('rev-parse', 'HEAD'),
                'source_dirty': bool(git('status', '--porcelain')), 'engine': version,
                'godotsteam': native['version'], 'steam_app_id': 480,
                'remote_two_account_test': 'not_run', 'files': {}}
    for path in sorted(output.rglob('*')):
        if path.is_file():
            metadata['files'][path.relative_to(output).as_posix()] = {
                'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    (output / 'build_manifest.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    archive = output.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as package:
        for path in sorted(output.rglob('*')):
            if path.is_file():
                package.write(path, output.name + '/' + path.relative_to(output).as_posix())
    print(json.dumps({'package': str(archive), 'directory': str(output), 'stage': str(stage),
                      'build_id': build_id, 'zip_sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=Path('G:/.Installed/Godot_v4.5.2-stable_win64.exe/Godot_v4.5.2-stable_win64_console.exe'))
    build(parser.parse_args().godot.resolve())
