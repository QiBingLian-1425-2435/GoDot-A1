"""Run the migrated base tests with Godot 4.5.2 (Python standard library only)."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ENGINE = Path('G:/.Installed/Godot_v4.5.2-stable_win64.exe/Godot_v4.5.2-stable_win64_console.exe')
SUITES = {
    "zombie": [("zombie_test", True, []), ("zombie_network_test", True, []), ("zombie_test", False, [])],
    "soul": [("soul_test", True, []), ("soul_network_test", True, []), ("soul_test", False, [])],
    "camp": [("camp_upgrade_test", True, []), ("camp_upgrade_network_test", True, []), ("camp_upgrade_test", False, [])],
    "steps": [("step_up_test", True, []), ("step_map_test", True, [])],
    "roll": [("roll_test", True, []), ("roll_test", False, []), ("roll_network_test", True, [])],
    "auto_reload": [("auto_reload_test", True, []), ("auto_reload_test", False, []), ("ammo_supply_network_test", True, [])],
    "toilet": [("toilet_search_test", True, []), ("toilet_search_test", False, []), ("item_network_test", True, [])],
    "loot": [("container_search_test", True, []), ("item_network_test", True, []), ("item_world_test", True, []), ("item_world_test", False, [])],
    "items": [("item_features_test", True, []), ("item_network_test", True, []), ("item_world_test", True, []), ("item_features_test", False, []), ("item_world_test", False, [])],
    'voice': [('voice_test', True, []), ('voice_network_test', True, []), ('voice_test', False, [])],
    'persistence': [('room_save_test', True, []), ('room_save_network_test', True, []), ('room_save_test', False, [])],
    'doors': [('door_interaction_test', True, []), ('door_interaction_test', False, [])],
    'recovery': [('exploration_recovery_test', True, []), ('recovery_network_test', True, []), ('exploration_recovery_test', False, [])],
    'vision': [('vision_presentation_test', True, []), ('vision_presentation_test', False, []), ('vision_rules_test', True, []), ('vision_integration_test', True, []), ('ground_zero_network_test', True, ['--vision']), ('vision_integration_test', False, [])],
    'fast': [('spatial_movement_test', True, []), ('local_movement_test', True, []), ('tracer_view_test', True, []), ('ammo_supply_test', True, []), ('movement_smoothing_test', True, []), ('duckov_model_test', True, []), ('duckov_animation_model_test', True, []), ('infinite_stamina_test', True, []),
             ('duckov_actor_animation_test', True, []), ('migration_contract_test', True, []),
             ('steam_service_test', True, []), ('steam_main_integration_test', True, [])],
    'network': [('ammo_supply_network_test', True, []), ('movement_scene_network_test', True, []), ('duckov_network_test', True, []), ('duckov_network_test', True, ['--host-loss']),
                ('base_five_peer_test', True, []), ('duckov_animation_network_test', True, [])],
    'ui': [('tracer_view_test', False, ['--capture']), ('duckov_integration_test', False, []), ('duckov_animation_integration_test', False, []),
           ('steam_ui_test', False, [])],
    'exploration': [('ground_zero_integration_test', True, []), ('ground_zero_network_test', True, []), ('ground_zero_integration_test', False, ['--capture'])],
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
        if name == 'ground_zero_integration_test' and not headless:
            suffix = '_visible'
        if name in ('zombie_test', 'soul_test', 'camp_upgrade_test', 'roll_test', 'auto_reload_test', 'toilet_search_test', 'item_features_test', 'item_world_test', 'vision_presentation_test', 'voice_test', 'vision_integration_test', 'exploration_recovery_test', 'door_interaction_test', 'room_save_test') and not headless:
            suffix = '_visible'
        if arguments == ['--vision']:
            suffix = '_vision'
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
    parser.add_argument('--suite', choices=['zombie', 'soul', 'camp', 'steps', 'roll', 'auto_reload', 'toilet', 'loot', 'items', 'voice', 'persistence', 'doors', 'recovery', 'fast', 'network', 'ui', 'exploration', 'vision', 'all'], default='fast')
    parser.add_argument('--steam-live', action='store_true', help='Requires Steam login; creates a private test room, sends no invitations')
    args = parser.parse_args()
    sys.exit(run(args.godot.resolve(), args.suite, args.steam_live))
