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
    manifest = json.loads((ROOT / 'docs/dependencies/2026-10-19-bunker_sources.json').read_text(encoding='utf-8'))
    tracked_runtime = [ROOT / 'project.godot'] + [ROOT / name for name in manifest['runtime_files']]
    runtime = tracked_runtime.copy()
    for name in manifest.get('external_asset_manifests', []):
        index_path = ROOT / name
        if not index_path.resolve().is_relative_to(ROOT) or not index_path.is_file():
            raise RuntimeError('Restore the Ground Zero map assets first: ' + str(index_path))
        index = json.loads(index_path.read_text(encoding='utf-8'))
        runtime.append(index_path)
        for relative, record in index['files'].items():
            path = index_path.parent / relative
            if not path.resolve().is_relative_to(index_path.parent.resolve()) or not path.is_file():
                raise RuntimeError('Missing/unsafe external map asset: ' + str(path))
            if path.stat().st_size != record['bytes'] or hashlib.sha256(path.read_bytes()).hexdigest() != record['sha256']:
                raise RuntimeError('External map asset differs from its extraction manifest: ' + str(path))
            runtime.append(path)
    for path in runtime:
        if not path.resolve().is_relative_to(ROOT) or not path.is_file():
            raise RuntimeError('Missing/unsafe runtime dependency: ' + str(path))
    # A source hash supplements the revision so rebuilding uncommitted work never reuses an old lobby build ID.
    hasher = hashlib.sha256()
    for path in sorted(runtime):
        hasher.update(path.relative_to(ROOT).as_posix().encode())
        hasher.update(path.read_bytes())
    hasher.update(json.dumps(native, sort_keys=True).encode())
    build_id = 'a1_' + git('rev-parse', '--short=12', 'HEAD') + '_' + hasher.hexdigest()[:12]
    output = ROOT / 'build' / ('bunker_a1_steam_' + build_id)
    if output.exists():
        # Never overwrite a package somebody might currently be testing.
        output = output.with_name(output.name + '_' + uuid.uuid4().hex[:6])
    output.mkdir(parents=True)
    stage = ROOT / 'artifacts' / ('steam_stage_' + uuid.uuid4().hex)
    stage.mkdir(parents=True)
    for path in runtime:
        destination = stage / path.relative_to(ROOT)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
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
    run_engine(engine, stage, ['--export-pack', 'Windows Steam Test', str(output / 'bunker_a1.pck')], output / 'export.log')
    windowed = engine.with_name(engine.name.replace('_console.exe', '.exe'))
    if not windowed.is_file():
        raise RuntimeError('Windowed Godot runtime missing beside the console executable')
    shutil.copy2(windowed, output / 'bunker_a1.exe')
    shutil.copy2(engine, output / 'bunker_a1_console.exe')
    # Preserve the extension's exact res:// paths even with export-pack's shared-library layout.
    for name in native['files']:
        if name.endswith('.dll'):
            destination = output / 'addons/godotsteam' / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / 'addons/godotsteam' / name, destination)
    (output / 'steam_appid.txt').write_text('480\n', encoding='ascii')
    (output / 'start_steam.cmd').write_text(
        '@echo off\ncd /d "%~dp0"\nif not exist logs mkdir logs\nstart "" "bunker_a1.exe" --log-file "%~dp0logs/game.log"\n',
        encoding='ascii', newline='\r\n')
    (output / 'README.txt').write_text(f'''A1 地下基地 · Steam 开发测试包
构建：{build_id}
环境：Windows x64 / Godot 4.5.2 / GodotSteam 4.23.1 / Steam App ID 480

1. 完整解压，保留 EXE、PCK、addons、DLL 与 steam_appid.txt；不要只转发 EXE。
2. 每人打开 Steam 并登录不同账号，建议先互加 Steam 好友。
3. 双击 start_steam.cmd（或 bunker_a1.exe）。房主选 Steam 联机并创建好友房间，成功后进入基地。
4. 房主按 Esc 打开基地菜单，邀请 Steam 好友或复制房间号；队友在 Steam 页面粘贴加入。
5. WASD 移动，鼠标瞄准/左键射击，R 装填（空弹匣继续左键自动换弹），Shift 冲刺，空格朝移动方向翻滚（消耗20耐力），C 蹲行，Tab/I 背包，E 设施/拾取；按住 Q 进行附近20米队伍语音。
6. 基地北侧出口按 E 全队进入零号区，地图内可进入神秘山洞；基地入口或撤离点按 E 全队返回。
   房主退出会结束房间，不支持房主迁移、掉线续局；基地安全区无玩家互伤。
7. 所有人必须使用同一测试包，含房主最多五人；只有基地允许加入，探索期间锁房。
   房主保存房间内各成员的背包、装备与仓库；队友重进同一房主房间可恢复。
8. 物品按白/绿/蓝/紫/金/红分级，Tab内可筛选类型并整理。右键或双击使用物品，靠近商人可出售整组。
   商人按E打开商品列表，工作台按E选择制作配方；探索箱子按E打开，逐格搜索后双击拿取，或选择拿取已发现物品；上锁箱消耗一个开锁器。
   Esc关闭暂停搜索，再次打开继续；箱内剩余物品保留，满背包不丢物。
   零号区厕所也可按E搜索，无需开锁器，只产出罐头、压缩饼干和营养棒。
   照明棒/信标持续60秒，烟雾直径6米持续8秒；道具放置失败不消耗。

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
                'source_dirty': bool(git('status', '--porcelain', '--', *[p.relative_to(ROOT).as_posix() for p in tracked_runtime])),
                'workspace_has_other_changes': bool(git('status', '--porcelain')), 'engine': version,
                'godotsteam': native['version'], 'steam_app_id': 480,
                'remote_two_account_test': 'not_run', 'max_players': 5, 'external_art_required': bool(manifest.get('external_art_required')), 'files': {}}
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
