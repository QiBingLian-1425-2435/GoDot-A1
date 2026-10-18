"""Reject staged files >= 10 MiB and ignored files added with --force."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 10 * 1024 * 1024


def git(*args, data=None, allowed=(0,)):
    result = subprocess.run(['git', *args], cwd=ROOT, input=data, capture_output=True)
    if result.returncode not in allowed:
        sys.exit(result.stderr.decode('utf-8', errors='replace'))
    return result.stdout


def main():
    entries = []
    for record in git('ls-files', '--stage', '-z').split(b'\0'):
        if not record:
            continue
        metadata, path = record.split(b'\t', 1)
        mode, oid, stage = metadata.split()
        if stage != b'0' or mode == b'160000':
            sys.exit('FAIL: resolve merge conflicts/submodule policy before committing')
        entries.append((oid, path))
    if not entries:
        print('GIT_FILES_PASS: no staged files')
        return
    hashes = sorted({oid for oid, _ in entries})
    output = git('cat-file', '--batch-check=%(objectname) %(objecttype) %(objectsize)',
                 data=b'\n'.join(hashes) + b'\n')
    sizes = {}
    for line in output.splitlines():
        oid, kind, size = line.split()
        if kind != b'blob':
            sys.exit('FAIL: unexpected staged object type')
        sizes[oid] = int(size)
    ignored = git('check-ignore', '--no-index', '-z', '--stdin',
                  data=b'\0'.join(path for _, path in entries) + b'\0', allowed=(0, 1))
    errors = []
    for path in ignored.split(b'\0'):
        if path:
            errors.append('ignored file staged: ' + path.decode('utf-8', errors='replace'))
    for oid, path in entries:
        if sizes[oid] >= LIMIT:
            errors.append('file >= 10 MiB: ' + path.decode('utf-8', errors='replace'))
    if errors:
        sys.exit('FAIL:\n' + '\n'.join(errors))
    total = sum(sizes[oid] for oid, _ in entries)
    largest = max(sizes[oid] for oid, _ in entries)
    print(f'GIT_FILES_PASS: {len(entries)} files, {total} bytes total, largest {largest} bytes; no ignored or >=10 MiB files')


if __name__ == '__main__':
    main()
