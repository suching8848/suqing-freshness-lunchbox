"""Validate and freeze rc.6 locally. Never deploy, launch a game, commit or upload."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MOD = ROOT / 'mods/SuQingFreshnessLunchbox'
MEDIA = MOD / '42/media'
OUT = GAME / 'CodexAssets/SuQingFreshnessLunchbox_Attachments_20261107'
VALIDATION = OUT / 'validation'
BASELINE = Path(r'D:\GameBackups\ProjectZomboid\返鲜餐盒挂点开发_20261107_005123\source-before.zip')
VERSION = '0.1.0-rc.6'
JAVAC = Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')
USER = Path(r'C:\Users\15792\Zomboid')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(folder):
    return {p.relative_to(folder).as_posix(): {'sha256': sha(p), 'bytes': p.stat().st_size}
            for p in sorted(folder.rglob('*')) if p.is_file()}


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def protected():
    paths = list((USER / 'mods/SuQingFreshnessLunchbox').rglob('*'))
    paths += [USER / 'mods/default.txt', USER / 'Saves/Sandbox/2026-10-09_18-19-22/mods.txt',
              GAME / 'ProjectZomboid64.json', ROOT / 'publishing/workshop-item.json',
              ROOT / 'publishing/release-config.json']
    return {str(p): sha(p) for p in sorted(paths) if p.is_file()}


def run(label, command, timeout=180):
    env = os.environ.copy()
    env['JAVA_TOOL_OPTIONS'] = '-Xms32m -Xmx256m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC'
    result = subprocess.run([str(arg) for arg in command], cwd=GAME, env=env,
                            capture_output=True, encoding='utf-8', errors='replace', timeout=timeout)
    output = result.stdout + result.stderr
    (VALIDATION / (label + '.log')).write_text(output, encoding='utf-8')
    if result.returncode:
        raise AssertionError(label + ' failed:\n' + output[-7000:])
    return output


def main():
    VALIDATION.mkdir(parents=True, exist_ok=True)
    checks = []
    def check(ok, label):
        if not ok:
            raise AssertionError(label)
        checks.append(label)
    untouched = protected()
    save(VALIDATION / 'protected-before.json', untouched)
    initial = manifest(MOD)
    info = (MOD / '42/mod.info').read_text(encoding='utf-8-sig')
    check('modversion=' + VERSION in info, 'candidate version rc.6')
    check('id=SuQingFreshnessLunchbox' in info and not re.search(r'^require=', info, re.M), 'stable ID, no mandatory dependencies')
    check('CanBeEquipped' not in (MEDIA / 'scripts/items_FreshnessLunchbox.txt').read_text(), 'no fake wearable slot')
    baseline_prefix = 'mods/SuQingFreshnessLunchbox/'
    with zipfile.ZipFile(BASELINE) as archive:
        old = {name.removeprefix(baseline_prefix): archive.read(name) for name in archive.namelist()
               if name.startswith(baseline_prefix) and not name.endswith('/')}
    allowed = {'42/mod.info', 'common/README.txt', '42/media/scripts/items_FreshnessLunchbox.txt',
               '42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua'}
    allowed.update(f'42/media/lua/shared/Translate/{lang}/{name}.json'
                   for lang in ['CN', 'EN', 'CH'] for name in ['IG_UI', 'Mod', 'Tooltip'])
    added = {'42/media/lua/client/SuQingFreshnessLunchbox_Attachments.lua',
             '42/media/lua/client/SuQingFreshnessLunchbox_AttachedContainers.lua',
             '42/media/scripts/models_FreshnessLunchbox_Attached.txt'}
    check(set(initial) - set(old) == added and not (set(old) - set(initial)), 'only two local bridges and one attached model added')
    check(all((MOD / name).read_bytes() == data for name, data in old.items() if name not in allowed),
          'all other runtime, crafting, art, model and sandbox files byte-identical to rc.5 source')
    core_name = '42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua'
    normalize = lambda raw: re.sub(rb'C.version="[^"]+"', b'C.version="VERSION"', raw).replace(b'\r\n', b'\n')
    check(normalize(old[core_name]) == normalize((MOD / core_name).read_bytes()), 'freshness Core differs only in source version')
    folder = MEDIA / 'lua/shared/Translate'
    for category in sorted((folder / 'EN').glob('*.json')):
        localized = {lang: json.loads((folder / lang / category.name).read_text(encoding='utf-8-sig')) for lang in ['CN', 'EN', 'CH']}
        check(set(localized['CN']) == set(localized['EN']) == set(localized['CH']), 'locale keys: ' + category.name)
        for key, value in localized['EN'].items():
            check(all(sorted(re.findall(r'%\d+', localized[lang][key])) == sorted(re.findall(r'%\d+', value)) for lang in ['CN', 'CH']),
                  'localized placeholders: ' + category.name + '/' + key)
    # Reports must match the final bridge sources, not a prior draft.
    reports = {}
    for label, script, report in [
        ('attachments', 'attachments_validate.py', ROOT / 'tests/attachments_validation.json'),
        ('attached_containers', 'attached_containers_validate.py', ROOT / 'tests/attached_containers_validation.json')]:
        output = run(label, [sys.executable, ROOT / 'tools' / script])
        data = json.loads(report.read_text(encoding='utf-8-sig'))
        check(data['result'] == 'PASS' and 'PASS' in output, label + ' behavior regression')
        reports[label] = data
    classes = VALIDATION / 'classes'
    classes.mkdir(exist_ok=True)
    run('javac', [JAVAC, '-encoding', 'UTF-8', '-d', classes,
                  ROOT / 'tools/AttachmentAssetProbe.java', ROOT / 'tools/ReleaseLuaCompile.java'])
    base = [GAME / 'jre64/bin/java.exe', '--enable-native-access=ALL-UNNAMED',
            '-Duser.home=' + str(VALIDATION / 'native_home'), '-cp',
            os.pathsep.join(str(p) for p in [classes, GAME, GAME / 'projectzomboid.jar', GAME / '*'])]
    native = run('native_attachment_assets', base + ['AttachmentAssetProbe', MEDIA])
    match = re.search(r'ATTACHMENT_ASSET assertions=(\d+) failures=0 PASS', native)
    check(bool(match), 'native Item.Load and three-anchor ModelScript parser')
    lua = sorted(MOD.rglob('*.lua'))
    compile_result = run('all_lua_compile', base + ['ReleaseLuaCompile', *lua])
    check(f'LUA_COMPILE files={len(lua)} PASS' in compile_result, 'all shipped Lua Kahlua compilation')
    integration_report = VALIDATION / 'integration.json'
    run('existing_integration', [sys.executable, ROOT / 'tools/integration_validate.py', '--report', integration_report])
    reports['existing_integration'] = json.loads(integration_report.read_text(encoding='utf-8'))
    check(reports['existing_integration']['result'] == 'PASS', 'existing native recipes, paid upgrades and crafting-chain integration')
    check(protected() == untouched, 'personal mod, lists, launcher and publication identity unchanged')
    check(manifest(MOD) == initial, 'runtime source stable throughout verification')
    report = {'result': 'PASS', 'version': VERSION, 'checked_at_bjt': datetime.now(timezone(timedelta(hours=8))).isoformat(),
              'checks': checks, 'check_count': len(checks), 'native_asset_assertions': int(match[1]),
              'components': reports, 'source_manifest': initial, 'protected_file_count': len(untouched),
              'game_started': False, 'world_created': False, 'installed': False, 'uploaded': False,
              'gameplay_acceptance': 'pending user; normal/Viewpoint visuals, animations, native UI and save/reload'}
    save(VALIDATION / 'validation.json', report)
    save(VALIDATION / 'protected-after.json', protected())
    candidate = OUT / 'candidate-0.1.0-rc.6'
    if candidate.exists():
        raise FileExistsError('Retain the existing freeze; use a new output directory: ' + str(candidate))
    target = candidate / 'mods/SuQingFreshnessLunchbox'
    shutil.copytree(MOD, target)
    check(manifest(target) == initial, 'frozen mod matches validated runtime')
    shutil.copy2(ROOT / 'docs/attachment-candidate-20261107.txt', candidate / '使用与验收_CN_EN.txt')
    save(candidate / 'candidate-manifest.json', {'version': VERSION, 'installed': False, 'uploaded': False,
         'mod_id': 'SuQingFreshnessLunchbox', 'runtime': initial, 'validation_report': str(VALIDATION / 'validation.json')})
    archive_path = OUT / 'SuQingFreshnessLunchbox-0.1.0-rc.6-attachments-candidate.zip'
    if archive_path.exists():
        raise FileExistsError(archive_path)
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(candidate.rglob('*')):
            if path.is_file(): archive.write(path, path.relative_to(candidate).as_posix())
    with zipfile.ZipFile(archive_path) as archive:
        check(archive.testzip() is None, 'candidate ZIP CRC readback')
        frozen_files = {p.relative_to(candidate).as_posix(): p for p in candidate.rglob('*') if p.is_file()}
        check(set(archive.namelist()) == set(frozen_files) and
              all(hashlib.sha256(archive.read(name)).hexdigest() == sha(path) for name, path in frozen_files.items()),
              'candidate ZIP member list and every SHA-256 match frozen files')
    receipt = {'result': 'PASS', 'version': VERSION, 'candidate': str(candidate), 'archive': str(archive_path),
               'archive_sha256': sha(archive_path), 'runtime_files': len(initial), 'game_started': False,
               'installed': False, 'uploaded': False, 'validation': str(VALIDATION / 'validation.json')}
    save(OUT / 'candidate-receipt.json', receipt)
    print(json.dumps(receipt, ensure_ascii=False))


if __name__ == '__main__':
    main()
