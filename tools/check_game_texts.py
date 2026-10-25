"""Audit authored game text, locale coverage, printf arguments and export dependencies."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'features/localization'
REFERENCE = re.compile(r'⟦([a-zA-Z_0-9.]+)⟧')
LITERAL = re.compile(r'\#.*?$|"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.M)
PRINTF = re.compile(r'%%|%[-+0 #]*[0-9]*(?:\.[0-9]+)?([sdf])')
HAN = re.compile(r'[\u3400-\u9fff]')


def read_json(path):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError(f'Duplicate key {key} in {path}')
            value[key] = item
        return value
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique)


def signature(value):
    return [match.group(1) for match in PRINTF.finditer(value) if match.group() != '%%']


def audit(write_sources=False):
    errors = []
    locales = read_json(DIRECTORY / 'locales.json')
    catalogs = {code: read_json(DIRECTORY / definition['file']) for code, definition in locales.items()}
    base = catalogs['zh_CN']
    sources = {key: [] for key in base}
    for code, catalog in catalogs.items():
        for key in base.keys() - catalog.keys():
            errors.append(f'{code}: missing {key}')
        for key, value in catalog.items():
            if not isinstance(value, str) or not value:
                errors.append(f'{code}: empty/non-string {key}')
            elif key not in base or signature(value) != signature(base[key]):
                errors.append(f'{code}: unknown key or printf mismatch: {key}')
            if REFERENCE.search(value):
                errors.append(f'{code}: catalog must contain copy, not nested references: {key}')
    for folder in ('app', 'features', 'ui', 'worlds'):
        for path in sorted((ROOT / folder).rglob('*')):
            if path.suffix not in ('.gd', '.tscn', '.tres'):
                continue
            source = path.read_text(encoding='utf-8-sig')
            for literal in LITERAL.finditer(source):
                raw = literal.group()
                if raw.startswith(('#', '"""', "'''")):
                    continue
                line = source.count('\n', 0, literal.start()) + 1
                location = f'{path.relative_to(ROOT).as_posix()}:{line}'
                if HAN.search(raw):
                    errors.append(f'{location}: inline authored CJK text {raw}')
                for key in REFERENCE.findall(raw):
                    if key not in sources:
                        errors.append(f'{location}: unknown text reference {key}')
                    elif location not in sources[key]:
                        sources[key].append(location)
            # Human-readable ASCII words in display calls must also be catalogued.
            for match in re.finditer(r'(?:_floor_label|_sign|G\.text)\([^\n]*', source):
                for literal in LITERAL.finditer(match.group()):
                    raw = literal.group()
                    if '⟦' not in raw and re.search(r'[A-Za-z]{2,}', raw) and not re.fullmatch(r'"[a-fA-F0-9]{6,8}"', raw):
                        errors.append(f'{path.relative_to(ROOT)}: inline sign text {raw}')
    for key, locations in sources.items():
        if not locations:
            errors.append(f'Unused catalog key: {key}')
    manifest = read_json(ROOT / 'docs/dependencies/2026-10-19-bunker_sources.json')
    required = [DIRECTORY / 'game_text.gd', DIRECTORY / 'game_text.gd.uid', DIRECTORY / 'locales.json']
    required += [DIRECTORY / definition['file'] for definition in locales.values()]
    for path in required:
        if path.relative_to(ROOT).as_posix() not in manifest['runtime_files']:
            errors.append(f'Missing runtime dependency: {path.name}')
        if not path.is_file():
            errors.append(f'Missing runtime file: {path.name}')
    preset = (ROOT / 'export_presets.cfg').read_text(encoding='utf-8')
    if 'features/localization/*.json' not in preset:
        errors.append('Export preset must include localization JSON catalogs')
    if write_sources:
        (DIRECTORY / 'sources.json').write_text(json.dumps(sources, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    else:
        saved = read_json(DIRECTORY / 'sources.json')
        if saved != sources:
            errors.append('Text source index stale; run with --write-sources after editing sources')
    for error in errors:
        print('FAIL:', error)
    print(f'GAME_TEXT_AUDIT: {len(base)} keys, {len(locales)} locales, {len(errors)} errors')
    return bool(errors)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write-sources', action='store_true')
    raise SystemExit(audit(parser.parse_args().write_sources))
