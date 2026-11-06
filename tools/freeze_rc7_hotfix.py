"""Freeze verified rc.7 locally. No deployment, game startup, Git or upload."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib, json, re, shutil, zipfile

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MOD = ROOT / 'mods/SuQingFreshnessLunchbox'
OUT = GAME / 'CodexAssets/SuQingFreshnessLunchbox_20261107_rc7_Hotfix'
OLD = GAME / 'CodexAssets/SuQingFreshnessLunchbox_Attachments_20261107'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(root):
    return {p.relative_to(root).as_posix(): {'sha256': sha(p), 'bytes': p.stat().st_size}
            for p in sorted(root.rglob('*')) if p.is_file()}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    checks = []
    def check(value, label):
        if not value:
            raise AssertionError(label)
        checks.append(label)
    previous = read(OLD / 'candidate-receipt.json')
    check(sha(Path(previous['archive'])) == previous['archive_sha256'], 'rc.6 baseline ZIP unchanged')
    with zipfile.ZipFile(previous['archive']) as archive:
        prefix = 'mods/SuQingFreshnessLunchbox/'
        old = {name[len(prefix):]: archive.read(name) for name in archive.namelist() if name.startswith(prefix)}
    current = manifest(MOD)
    check(set(old) == set(current), 'same 43 runtime files; no item or save migration')
    allowed = {'42/mod.info', 'common/README.txt', '42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua',
               '42/media/lua/client/SuQingFreshnessLunchbox_Runtime.lua',
               '42/media/scripts/models_FreshnessLunchbox_Attached.txt'}
    allowed.update(f'42/media/lua/shared/Translate/{lang}/{name}.json'
                   for lang in ['CN', 'EN', 'CH'] for name in ['IG_UI', 'Mod', 'Tooltip'])
    check(all((MOD / name).read_bytes() == content for name, content in old.items() if name not in allowed),
          'all other runtime, hooks, recipes, sandbox, geometry and art byte-identical to rc.6')
    core = '42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua'
    normalize = lambda text: re.sub(r'C.version="[^"]+"', 'C.version="VERSION"', text.replace('\r\n', '\n'))
    check(normalize(old[core].decode('utf-8-sig')) == normalize((MOD / core).read_text(encoding='utf-8-sig')),
          'freshness Core changes only version')
    runtime = '42/media/lua/client/SuQingFreshnessLunchbox_Runtime.lua'
    original = old[runtime].decode('utf-8-sig').replace('\r\n', '\n')
    expected = original.replace('    for i=0,vehicles:size()-1 do\n        local vehicle=vehicles:get(i)',
        '    -- B42.21 returns HashSet<BaseVehicle>; Set has no indexed get(int).\n'
        '    local iterator=vehicles:iterator()\n    while iterator:hasNext() do\n        local vehicle=iterator:next()')
    check(expected != original and expected == (MOD / runtime).read_text(encoding='utf-8-sig'),
          'Runtime changes only vehicle Set traversal; ownership and error handling retained')
    model = '42/media/scripts/models_FreshnessLunchbox_Attached.txt'
    original = old[model].decode('utf-8-sig').replace('\r\n', '\n')
    expected = original.replace('// Dedicated attached view; hand/ground definitions and geometry are unchanged.',
                                '/* Dedicated attached view; hand/ground definitions and geometry are unchanged. */')
    check(expected != original and expected == (MOD / model).read_text(encoding='utf-8-sig'),
          'model fix changes only unsupported line comment; anchors retained')
    info = (MOD / '42/mod.info').read_text(encoding='utf-8-sig')
    check('modversion=0.1.0-rc.7' in info and 'id=SuQingFreshnessLunchbox' in info, 'rc.7, same Mod ID')
    locales = MOD / '42/media/lua/shared/Translate'
    lengths = {}
    for category in sorted((locales / 'EN').glob('*.json')):
        data = {lang: read(locales / lang / category.name) for lang in ['CN', 'EN', 'CH']}
        check(set(data['CN']) == set(data['EN']) == set(data['CH']), 'locale keys ' + category.name)
        for key in data['EN']:
            check(all(sorted(re.findall(r'%\d+', data[lang][key])) == sorted(re.findall(r'%\d+', data['EN'][key]))
                      for lang in ['CN', 'CH']), 'placeholders ' + category.name + '/' + key)
    for lang in ['CN', 'EN', 'CH']:
        name = f'42/media/lua/shared/Translate/{lang}/Tooltip.json'
        before = json.loads(old[name].decode('utf-8-sig'))['Tooltip_SFL_Item']
        after = read(MOD / name)['Tooltip_SFL_Item']
        check(len(after) < len(before) * 0.5, 'compact item tooltip ' + lang)
        lengths[lang] = {'before_characters': len(before), 'after_characters': len(after)}
    reports = {name: read(ROOT / 'tests' / (name + '_validation.json'))
               for name in ['vehicle_collection', 'model_registration', 'runtime']}
    for name, report in reports.items():
        check(report['result'] == 'PASS', 'passed component ' + name)
    for path, digest in reports['vehicle_collection']['source_input_sha256'].items():
        check(sha(Path(path)) == digest, 'vehicle regression input current: ' + Path(path).name)
    for case in reports['model_registration']['cases']:
        check(sha(Path(case['input'])) == case['sha256'], 'full model registration input current: ' + case['name'])
    for path, digest in reports['runtime']['source_sha256'].items():
        check(sha(ROOT / path) == digest, 'runtime regression input current: ' + Path(path).name)
    check(reports['runtime']['lua_compiled'] == 7, 'all seven shipped Lua files compiled')
    candidate = OUT / 'candidate-0.1.0-rc.7'
    if candidate.exists():
        raise FileExistsError('Keep prior freeze; choose a new output: ' + str(candidate))
    shutil.copytree(MOD, candidate / 'mods/SuQingFreshnessLunchbox')
    check(manifest(candidate / 'mods/SuQingFreshnessLunchbox') == current, 'frozen runtime equals verified source')
    shutil.copy2(ROOT / 'docs/rc7-vehicle-model-tooltip-hotfix-20261107.txt', candidate / '修复与验收_CN_EN.txt')
    summary = {'result': 'PASS', 'version': '0.1.0-rc.7', 'checked_at_bjt': datetime.now(timezone(timedelta(hours=8))).isoformat(),
               'checks': checks, 'source_manifest': current, 'tooltip_lengths': lengths, 'components': reports,
               'game_started': False, 'installed': False, 'uploaded': False, 'gameplay_acceptance': 'pending user'}
    save(OUT / 'validation/validation.json', summary)
    save(candidate / 'candidate-manifest.json', {'version': '0.1.0-rc.7', 'runtime': current, 'installed': False, 'uploaded': False})
    archive_path = OUT / 'SuQingFreshnessLunchbox-0.1.0-rc.7-hotfix.zip'
    if archive_path.exists():
        raise FileExistsError(archive_path)
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(candidate.rglob('*')):
            if path.is_file(): archive.write(path, path.relative_to(candidate).as_posix())
    with zipfile.ZipFile(archive_path) as archive:
        files = {p.relative_to(candidate).as_posix(): p for p in candidate.rglob('*') if p.is_file()}
        check(archive.testzip() is None and set(archive.namelist()) == set(files), 'ZIP CRC and member list')
        check(all(hashlib.sha256(archive.read(name)).hexdigest() == sha(path) for name, path in files.items()), 'every ZIP member SHA-256')
    receipt = {'result': 'PASS', 'version': '0.1.0-rc.7', 'candidate': str(candidate), 'archive': str(archive_path),
               'archive_sha256': sha(archive_path), 'runtime_files': len(current), 'validation': str(OUT / 'validation/validation.json'),
               'installed': False, 'uploaded': False, 'game_started': False}
    save(OUT / 'candidate-receipt.json', receipt)
    print(json.dumps(receipt, ensure_ascii=False))


if __name__ == '__main__':
    main()
