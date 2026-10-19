"""Run the migrated base tests with Godot 4.5.2 (Python standard library only)."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = Path('G:/.Installed/Godot_v4.5.2-stable_win64.exe/Godot_v4.5.2-stable_win64_console.exe')
SUITES = {
    'fast': [('duckov_model_test', True, []), ('duckov_animation_model_test', True, []),
             ('duckov_actor_animation_test', True, []), ('migration_contract_test', True, []),
             ('steam_service_test', True, []), ('steam_main_integration_test', True, [])],
    'network': [('duckov_network_test', True, []), ('duckov_network_test', True, ['--host-loss']),
                ('base_five_peer_test', True, []), ('duckov_animation_network_test', True, [])],
    'ui': [('duckov_integration_test', False, []), ('duckov_animation_integration_test', False, []),
           ('steam_ui_test', False, [])],
}

def run(engine, suite, steam_live):
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if not version.startswith('4.5.2.'):
        raise RuntimeError('Use the tested Godot 4.5.2 runtime: ' + version)
    selected = list(SUITES) if suite == 'all' else [suite]
    tests = [case for group in selected for case in SUITES[group]]
    if steam_live:
        tests.append(('steam_live_main', False, ['--steam-live-test']))
    logs = ROOT / 'artifacts/base_tests'
    logs.mkdir(parents=True, exist_ok=True)
    failures = []
    for name, headless, arguments in tests:
        command = [str(engine), '--path', str(ROOT), '--script', 'res://tests/base/' + name + '.gd']
        if headless:
            command.insert(1, '--headless')
        if arguments:
            command.extend(['--', *arguments])
        suffix = '_host_loss' if arguments == ['--host-loss'] else ''
        output = logs / (name + suffix + '.log')
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, encoding='utf-8', errors='replace', timeout=90)
            text = result.stdout + result.stderr
            ok = result.returncode == 0 and not any(token in text for token in ['SCRIPT ERROR:', 'ERROR:', 'FAIL:', 'failures=1'])
        except subprocess.TimeoutExpired as error:
            text = 'TIMEOUT: ' + str(error)
            ok = False
        output.write_text(text, encoding='utf-8')
        print(('PASS ' if ok else 'FAIL ') + name + suffix + ' -> ' + str(output), flush=True)
        if not ok:
            failures.append(name + suffix)
    print(f'BASE_SUITE {len(tests)} runs, {len(failures)} failed')
    return 1 if failures else 0

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=DEFAULT_ENGINE)
    parser.add_argument('--suite', choices=['fast', 'network', 'ui', 'all'], default='fast')
    parser.add_argument('--steam-live', action='store_true', help='Requires Steam login; creates a private test room, sends no invitations')
    args = parser.parse_args()
    sys.exit(run(args.godot.resolve(), args.suite, args.steam_live))
