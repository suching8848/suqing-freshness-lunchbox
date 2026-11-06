"""Verify/freeze rc.8 position refinement only. No deployment, game or upload."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib, json, re, shutil, subprocess, zipfile, os

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MOD = ROOT / 'mods/SuQingFreshnessLunchbox'
OUT = GAME / 'CodexAssets/SuQingFreshnessLunchbox_20261107_rc8_Position'
OLD = GAME / 'CodexAssets/SuQingFreshnessLunchbox_20261107_rc7_Hotfix'
STUDY = GAME / 'CodexAssets/SuQingFreshnessLunchbox_Attachments_20261107/model-study/position-rc8'

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def manifest(root):
    return {p.relative_to(root).as_posix(): {'sha256': sha(p), 'bytes': p.stat().st_size}
            for p in sorted(root.rglob('*')) if p.is_file()}

def main():
    validation = OUT/'validation'
    validation.mkdir(parents=True, exist_ok=True)
    checks = []
    def check(ok, label):
        if not ok: raise AssertionError(label)
        checks.append(label)
    previous = read(OLD/'candidate-receipt.json')
    check(sha(Path(previous['archive'])) == previous['archive_sha256'], 'rc.7 frozen ZIP unchanged')
    with zipfile.ZipFile(previous['archive']) as archive:
        prefix='mods/SuQingFreshnessLunchbox/'
        old={name[len(prefix):]: archive.read(name) for name in archive.namelist() if name.startswith(prefix)}
    current=manifest(MOD)
    check(set(old)==set(current), 'same43 runtime files')
    allowed={'42/mod.info','common/README.txt','42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua',
             '42/media/scripts/models_FreshnessLunchbox_Attached.txt'}
    allowed.update(f'42/media/lua/shared/Translate/{lang}/Mod.json' for lang in ['CN','EN','CH'])
    check(all((MOD/name).read_bytes()==content for name,content in old.items() if name not in allowed),
          'runtime behavior, hooks, item, compact tooltips, recipes, sandbox, meshes and textures byte-identical to rc.7')
    core='42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua'
    normalize=lambda text: re.sub(r'C.version="[^"]+"','C.version="VERSION"',text.replace('\r\n','\n'))
    check(normalize(old[core].decode('utf-8-sig'))==normalize((MOD/core).read_text(encoding='utf-8-sig')), 'Core version only')
    model='42/media/scripts/models_FreshnessLunchbox_Attached.txt'
    original=old[model].decode('utf-8-sig').replace('\r\n','\n')
    expected=original.replace('offset = 0.0 -0.035 -0.12605,','offset = 0.0 -0.035 -0.04605,',1)
    check(expected!=original and expected==(MOD/model).read_text(encoding='utf-8-sig'),
          'only ordinary bottom Z +0.08; depth/rotation/scale/Big/ALICE unchanged')
    check('modversion=0.1.0-rc.8' in (MOD/'42/mod.info').read_text(), 'rc.8 metadata')
    locales=MOD/'42/media/lua/shared/Translate'
    for category in sorted((locales/'EN').glob('*.json')):
        data={lang:read(locales/lang/category.name) for lang in ['CN','EN','CH']}
        check(set(data['CN'])==set(data['EN'])==set(data['CH']), 'locale keys '+category.name)
        for key in data['EN']:
            check(all(sorted(re.findall(r'%\d+',data[lang][key]))==sorted(re.findall(r'%\d+',data['EN'][key])) for lang in ['CN','CH']),
                  'placeholder '+category.name+'/'+key)
    env=os.environ.copy()
    env['JAVA_TOOL_OPTIONS']='-Xms32m -Xmx256m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC'
    def run(label, command):
        result=subprocess.run([str(v) for v in command],cwd=GAME,env=env,capture_output=True,encoding='utf-8',errors='replace',timeout=120)
        (validation/(label+'.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode: raise RuntimeError(label+' failed:\n'+result.stdout+result.stderr)
        return result.stdout
    import sys
    run('full_model_registration',[sys.executable,ROOT/'tools/model_registration_validate.py',
        '--output-dir',validation/'model_registration','--report',validation/'model-registration.json'])
    registration=read(validation/'model-registration.json')
    check(registration['result']=='PASS','full native file registration/item model lookup')
    position=read(STUDY/'native-position-readback.json')
    check(position['result']=='PASS','native position transform readback')
    check(sha(MOD/model)==position['rc8']['sha256'],'position evidence matches final source')
    classes=validation/'classes';classes.mkdir(exist_ok=True)
    run('javac',[Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe'),
        '-encoding','UTF-8','-d',classes,ROOT/'tools/ReleaseLuaCompile.java'])
    lua=sorted(MOD.rglob('*.lua'))
    output=run('all_lua_compile',[GAME/'jre64/bin/java.exe',f'-Duser.home={validation / "compile_home"}',
        '-cp',os.pathsep.join([str(classes),str(GAME/'projectzomboid.jar')]),'ReleaseLuaCompile',*lua])
    check(f'LUA_COMPILE files={len(lua)} PASS' in output,'all seven Lua compiled')
    check(manifest(MOD)==current,'runtime stable during validation')
    candidate=OUT/'candidate-0.1.0-rc.8'
    if candidate.exists(): raise FileExistsError('Retain existing freeze: '+str(candidate))
    shutil.copytree(MOD,candidate/'mods/SuQingFreshnessLunchbox')
    check(manifest(candidate/'mods/SuQingFreshnessLunchbox')==current,'frozen mod equals verified source')
    shutil.copy2(ROOT/'docs/rc8-position-calibration-20261107.txt',candidate/'位置调整与验收_CN_EN.txt')
    save(candidate/'candidate-manifest.json',{'version':'0.1.0-rc.8','runtime':current,'installed':False,'uploaded':False})
    report={'result':'PASS','version':'0.1.0-rc.8','checked_at_bjt':datetime.now(timezone(timedelta(hours=8))).isoformat(),
        'checks':checks,'source_manifest':current,'model_registration':registration,'position':position,
        'installed':False,'uploaded':False,'game_started':False,'gameplay_visual_acceptance':'pending user screenshot after restart'}
    save(validation/'validation.json',report)
    archive_path=OUT/'SuQingFreshnessLunchbox-0.1.0-rc.8-position.zip'
    if archive_path.exists(): raise FileExistsError(archive_path)
    with zipfile.ZipFile(archive_path,'w',zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(candidate.rglob('*')):
            if path.is_file(): archive.write(path,path.relative_to(candidate).as_posix())
    with zipfile.ZipFile(archive_path) as archive:
        files={p.relative_to(candidate).as_posix():p for p in candidate.rglob('*') if p.is_file()}
        check(archive.testzip() is None and set(archive.namelist())==set(files),'ZIP member list and CRC')
        check(all(hashlib.sha256(archive.read(name)).hexdigest()==sha(path) for name,path in files.items()),'all ZIP member SHA-256')
    receipt={'result':'PASS','version':'0.1.0-rc.8','candidate':str(candidate),'archive':str(archive_path),
        'archive_sha256':sha(archive_path),'runtime_files':len(current),'validation':str(validation/'validation.json'),
        'installed':False,'uploaded':False,'game_started':False}
    save(OUT/'candidate-receipt.json',receipt)
    print(json.dumps(receipt,ensure_ascii=False))

if __name__=='__main__':main()
