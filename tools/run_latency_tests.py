"""Real two-process ENet input tests behind an opaque UDP impairment proxy.

Only an ignored, isolated project copy is imported or configured. This is not
Steam/two-machine acceptance. --measure-only records the same strict assertions
without failing on responsiveness, so the pre-fix version can be quantified.
"""
import argparse
import hashlib
import heapq
import json
from pathlib import Path
import random
import re
import selectors
import shutil
import socket
import subprocess
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {'stable': (0.200, 0.0, 0.0), 'jitter': (0.120, 0.040, 0.03)}


class UDPProxy:
    """Forward original ENet datagrams, including ACKs/retransmissions/handshake."""
    def __init__(self, host_port, profile, seed):
        self.target = ('127.0.0.1', host_port)
        self.delay, self.jitter, self.loss = PROFILES[profile]
        self.rng = random.Random(seed)
        self.front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.front.bind(('127.0.0.1', 0))
        self.port = self.front.getsockname()[1]
        self.back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.back.bind(('127.0.0.1', 0))
        self.selector = selectors.DefaultSelector()
        for sock, direction in [(self.front, 'up'), (self.back, 'down')]:
            sock.setblocking(False)
            self.selector.register(sock, selectors.EVENT_READ, direction)
        self.client = None
        self.pending = []
        self.serial = 0
        self.stop = threading.Event()
        self.stats = {direction: {'received': 0, 'sent': 0, 'dropped': 0,
                      'bytes_sent': 0, 'delay_sum_ms': 0.0, 'max_delay_ms': 0.0}
                      for direction in ['up', 'down']}
        self.thread = threading.Thread(target=self.run, daemon=True)

    def run(self):
        while not self.stop.is_set():
            now = time.monotonic()
            timeout = min(0.01, max(0.0, self.pending[0][0] - now)) if self.pending else 0.01
            for key, _ in self.selector.select(timeout):
                try:
                    data, sender = key.fileobj.recvfrom(65535)
                except (BlockingIOError, ConnectionResetError):
                    continue
                direction = key.data
                if direction == 'up':
                    self.client = sender
                    destination, sock = self.target, self.back
                else:
                    if self.client is None:
                        continue
                    destination, sock = self.client, self.front
                stat = self.stats[direction]
                stat['received'] += 1
                if self.rng.random() < self.loss:
                    stat['dropped'] += 1
                    continue
                received = time.monotonic()
                due = received + self.delay + self.rng.uniform(-self.jitter, self.jitter)
                self.serial += 1
                heapq.heappush(self.pending, (due, self.serial, received, sock, destination, data, direction))
            now = time.monotonic()
            while self.pending and self.pending[0][0] <= now:
                _, _, received, sock, destination, data, direction = heapq.heappop(self.pending)
                try:
                    sock.sendto(data, destination)
                except OSError:
                    continue
                stat = self.stats[direction]
                observed = (time.monotonic() - received) * 1000.0
                stat['sent'] += 1
                stat['bytes_sent'] += len(data)
                stat['delay_sum_ms'] += observed
                stat['max_delay_ms'] = max(stat['max_delay_ms'], observed)

    def close(self):
        self.stop.set()
        self.thread.join(timeout=2)
        self.selector.close()
        self.front.close()
        self.back.close()
        for stat in self.stats.values():
            stat['mean_delay_ms'] = stat.pop('delay_sum_ms') / max(1, stat['sent'])
        return self.stats


def prepare(project, native_source, output):
    stage = output / 'project'
    stage.mkdir()
    # Include uncommitted runtime files while excluding caches and external media.
    allowed = {'.gd', '.uid', '.tscn', '.tres', '.cfg', '.gdshader', '.gdshaderinc', '.godot', '.json'}
    for top in ['app', 'features', 'worlds', 'ui', 'tests']:
        for source in (project / top).rglob('*'):
            if source.is_file() and source.suffix in allowed:
                target = stage / source.relative_to(project)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
    # Player visuals are now external Blender assets, required by real Main.
    human_source = project / 'assets/characters/humans'
    if human_source.is_dir():
        human_target = stage / 'assets/characters/humans'
        human_target.mkdir(parents=True, exist_ok=True)
        for source in human_source.glob('*.glb'):
            shutil.copy2(source, human_target / source.name)
    # This runner can measure an older checkout using the current test harness.
    test = ROOT / 'tests/base/client_latency_network_test.gd'
    shutil.copy2(test, stage / 'tests/base' / test.name)
    if test.with_suffix('.gd.uid').exists():
        shutil.copy2(test.with_suffix('.gd.uid'), stage / 'tests/base' / (test.name + '.uid'))
    config = (project / 'project.godot').read_text(encoding='utf-8-sig')
    config = re.sub(r'^_mcp_game_helper=.*\n?', '', config, flags=re.M)
    config = re.sub(r'^enabled=PackedStringArray\("res://addons/godot_ai/plugin.cfg"\)\n?', '', config, flags=re.M)
    (stage / 'project.godot').write_text(config, encoding='utf-8')
    native = native_source / 'addons/godotsteam'
    if native.is_dir():
        shutil.copytree(native, stage / 'addons/godotsteam')
    return stage


def engine_run(engine, stage, arguments, log):
    result = subprocess.run([str(engine), '--headless', '--path', str(stage), *arguments],
                            capture_output=True, encoding='utf-8', errors='replace', timeout=120)
    text = result.stdout + result.stderr
    log.write_text(text, encoding='utf-8')
    # This pinned Windows engine can crash during first-import shutdown, after
    # completing the scan. Preserve that failure and retry the same saved import
    # once; script/import errors are never retried or filtered out.
    if (result.returncode and 'CrashHandlerException' in text
            and 'loading_editor_layout' in text
            and not any(s in text for s in ['SCRIPT ERROR:', 'ERROR:'])):
        print('First import crashed during shutdown; preserving ' + str(log), flush=True)
        retry = subprocess.run([str(engine), '--headless', '--path', str(stage), *arguments],
                               capture_output=True, encoding='utf-8', errors='replace', timeout=120)
        retry_text = retry.stdout + retry.stderr
        log.with_name(log.stem + '_retry.log').write_text(retry_text, encoding='utf-8')
        if retry.returncode == 0 and not any(s in retry_text for s in ['SCRIPT ERROR:', 'ERROR:', 'CrashHandlerException']):
            return
    if result.returncode or any(s in text for s in ['SCRIPT ERROR:', 'ERROR:']):
        raise RuntimeError(f'Engine failed; inspect {log}')


def run_profile(args, stage, output, profile):
    case = output / profile
    case.mkdir()
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.bind(('127.0.0.1', 0))
    host_port = probe.getsockname()[1]
    probe.close()
    proxy = UDPProxy(host_port, profile, args.seed)
    common = [str(args.godot), '--path', str(stage), '--script', 'res://tests/base/client_latency_network_test.gd',
              '--', '--results=' + str(case), '--profile=' + profile]
    if args.measure_only:
        common.append('--measure-only')
    processes = []
    files = []
    proxy.thread.start()
    try:
        host_args = [common[0], '--headless', *common[1:], '--host', '--port=' + str(host_port)]
        host_log = (case / 'host.log').open('w', encoding='utf-8')
        files.append(host_log)
        host = subprocess.Popen(host_args, stdout=host_log, stderr=subprocess.STDOUT)
        processes.append(host)
        deadline = time.monotonic() + 15
        while not (case / 'host_ready.json').exists():
            if host.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError(f'Host did not become ready; inspect {case}')
            time.sleep(0.05)
        client_args = common + ['--client', '--port=' + str(proxy.port)]
        if not args.visible_client:
            client_args.insert(1, '--headless')
        client_log = (case / 'client.log').open('w', encoding='utf-8')
        files.append(client_log)
        client = subprocess.Popen(client_args, stdout=client_log, stderr=subprocess.STDOUT)
        processes.append(client)
        client_code = client.wait(timeout=100)
        host_code = host.wait(timeout=10)
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        for handle in files:
            handle.close()
        (case / 'proxy.json').write_text(json.dumps(proxy.close(), indent=2), encoding='utf-8')
    report = json.loads((case / 'client_result.json').read_text(encoding='utf-8'))
    host_report = json.loads((case / 'host_result.json').read_text(encoding='utf-8'))
    report['host'] = host_report
    report['proxy'] = json.loads((case / 'proxy.json').read_text(encoding='utf-8'))
    report['exit_codes'] = [host_code, client_code]
    errors = []
    for role in ['host', 'client']:
        errors.extend(line for line in (case / (role + '.log')).read_text(encoding='utf-8').splitlines()
                      if 'SCRIPT ERROR:' in line or line.startswith('ERROR:'))
    report['engine_errors'] = errors
    report['ok'] = host_code == 0 and client_code == 0 and not errors
    (case / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'profile': profile, 'ok': report['ok'], 'metrics': report['metrics'],
                      'failures': report['failures'], 'measured_failures': report['measured_failures'],
                      'report': str(case / 'summary.json')}, ensure_ascii=False), flush=True)
    return report['ok']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--native-source', type=Path, help='Project containing the already installed native addon')
    parser.add_argument('--measure-only', action='store_true')
    parser.add_argument('--visible-client', action='store_true')
    parser.add_argument('--profile', choices=['stable', 'jitter', 'all'], default='all')
    parser.add_argument('--seed', type=int, default=19)
    args = parser.parse_args()
    args.project = args.project.resolve()
    args.godot = args.godot.resolve()
    version = subprocess.check_output([str(args.godot), '--version'], text=True).strip()
    if not version.startswith('4.5.2.'):
        raise RuntimeError('Expected Godot 4.5.2, got ' + version)
    output = args.project / 'artifacts' / ('latency_qa_' + uuid.uuid4().hex[:8])
    output.mkdir(parents=True)
    stage = prepare(args.project, args.native_source or args.project, output)
    digest = hashlib.sha256()
    for path in sorted(stage.rglob('*')):
        if path.is_file() and 'addons' not in path.relative_to(stage).parts:
            digest.update(path.relative_to(stage).as_posix().encode())
            digest.update(path.read_bytes())
    revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=args.project,
                              capture_output=True, text=True).stdout.strip()
    (output / 'run_metadata.json').write_text(json.dumps({
        'source_project': str(args.project), 'source_revision': revision,
        'prepared_source_sha256': digest.hexdigest(), 'engine': version,
        'seed': args.seed, 'measure_only': args.measure_only, 'visible_client': args.visible_client,
        'profiles': PROFILES, 'transport': 'real ENet over opaque local UDP proxy',
        'steam_cross_network': 'not_run', 'stage_configuration_changes':
            'only remove missing editor helper autoload and enabled plugin in ignored copy'
    }, indent=2), encoding='utf-8')
    engine_run(args.godot, stage, ['--editor', '--import', '--quit'], output / 'import.log')
    # Preserve an engine-generated UID in the harness's own checkout.
    generated = stage / 'tests/base/client_latency_network_test.gd.uid'
    target = ROOT / 'tests/base/client_latency_network_test.gd.uid'
    if generated.exists() and not target.exists():
        shutil.copy2(generated, target)
    profiles = list(PROFILES) if args.profile == 'all' else [args.profile]
    results = [run_profile(args, stage, output, profile) for profile in profiles]
    print('LATENCY_TESTS ' + str(output))
    return 0 if all(results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
