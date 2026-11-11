"""Offline methods only: no game client, world cell, world load or user save."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parents[1]
GAME=ROOT.parents[1]
TESTS=ROOT/'tests'
LOGS=TESTS/'runtime_validation'
REPORT=TESTS/'runtime_validation.json'

def execute(label,command,home):
    home.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy()
    env['USERPROFILE']=str(home)
    env['APPDATA']=str(home/'AppData'/'Roaming')
    env['LOCALAPPDATA']=str(home/'AppData'/'Local')
    run=subprocess.run([str(v) for v in command],cwd=GAME,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
    output=run.stdout+run.stderr
    (LOGS/(label+'.log')).write_text(output,encoding='utf-8')
    if run.returncode:
        raise RuntimeError(f'{label} failed ({run.returncode}); see {LOGS/(label+".log")}\n{output[-7000:]}')
    return output

def main():
    global GAME, LOGS, REPORT
    parser=argparse.ArgumentParser()
    parser.add_argument('--game',type=Path,default=GAME)
    parser.add_argument('--javac',type=Path)
    parser.add_argument('--mock-only',action='store_true')
    parser.add_argument('--output',type=Path,default=TESTS,
                        help='Directory for reports, logs, helper classes and isolated profiles')
    parser.add_argument('--legacy-core',action='store_true',
                        help='Also exercise the retained pre-batch Core API with native Food objects')
    args=parser.parse_args()
    if args.mock_only and args.legacy_core:
        parser.error('--legacy-core requires native testing')
    output=args.output.resolve()
    LOGS=output/'runtime_validation'
    REPORT=output/'runtime_validation.json'
    game=args.game.resolve()
    GAME=game
    jar=game/'projectzomboid.jar'
    java=game/'jre64'/'bin'/'java.exe'
    javac=args.javac or (Path(shutil.which('javac')) if shutil.which('javac') else None)
    if not javac:
        candidates=list(Path('E:/code').glob('java*/bin/javac.exe'))
        javac=candidates[0] if candidates else None
    if not jar.is_file() or not java.is_file() or not javac or not javac.is_file():
        raise RuntimeError('Current game JAR/runtime and a local javac are required')
    LOGS.mkdir(parents=True,exist_ok=True)
    classes=output/'runtime_classes';classes.mkdir(exist_ok=True)
    sources=sorted((ROOT/'tools').glob('runtime_*.java'))
    execute('javac',[javac,'-encoding','UTF-8','-d',classes,*sources],output/'runtime_compile_home')
    cp=os.pathsep.join(str(v) for v in (classes,game,jar,game/'*'))

    def run(label, runner, *files):
        home=output/f'runtime_{label}_home'
        return execute(label,[java,'-XX:-UsePerfData','--enable-native-access=ALL-UNNAMED',
                              f'-Duser.home={home}','-cp',cp,runner,*files],home)

    lua=sorted((ROOT/'mods').rglob('*.lua'))
    run('compile','runtime_LuaCompile',*lua)
    mod_lua=ROOT/'mods'/'SuQingFreshnessLunchbox'/'42'/'media'/'lua'
    shared=mod_lua/'shared'/'SuQingFreshnessLunchbox'
    core=shared/'Core.lua'
    batch=shared/'Batch.lua'
    craft=shared/'Crafting.lua'
    runtime=mod_lua/'client'/'SuQingFreshnessLunchbox_Runtime.lua'
    lock=mod_lua/'client'/'SuQingFreshnessLunchbox_Lock.lua'
    mock_bootstrap=TESTS/'runtime_mock_bootstrap.lua'
    mock_log=run('mock','runtime_KahluaAudit',mock_bootstrap,core,batch,craft,runtime,
                 TESTS/'runtime_batch_cases.lua')
    mock=re.search(r'RUNTIME_BATCH cases=(\d+) assertions=(\d+) failures=0',mock_log)
    if not mock:
        raise RuntimeError('Missing batch mock summary')
    lock_log=run('lock','runtime_KahluaAudit',mock_bootstrap,core,batch,craft,lock,
                 TESTS/'runtime_batch_lock_cases.lua')
    lock_result=re.search(r'RUNTIME_BATCH_LOCK assertions=(\d+) PASS',lock_log)
    if not lock_result:
        raise RuntimeError('Missing batch lock summary')
    native=None
    legacy=None
    if not args.mock_only:
        native_bootstrap=TESTS/'runtime_native_bootstrap.lua'
        native_log=run('native','runtime_NativeProbe',native_bootstrap,core,batch,TESTS/'runtime_batch_native_cases.lua')
        native=re.search(r'RUNTIME_BATCH_NATIVE cases=(\d+) assertions=(\d+) PASS',native_log)
        if not native:
            raise RuntimeError('Missing native batch summary')
        if args.legacy_core:
            legacy_log=run('legacy_native','runtime_NativeProbe',native_bootstrap,core,TESTS/'runtime_native_cases.lua')
            legacy=re.search(r'RUNTIME_NATIVE_BASE cases=(\d+) assertions=(\d+) PASS',legacy_log)
            if not legacy:
                raise RuntimeError('Missing retained native Core summary')
    report={'result':'PASS','checked_utc':datetime.now(timezone.utc).isoformat(),'game_started':False,'world_created':False,'in_game_tested':False,
        'world_cell_created':False,'world_loaded':False,'native_singleton_initialized':bool(native),
        'game_jar':str(jar),'game_jar_sha256':hashlib.sha256(jar.read_bytes()).hexdigest(),'lua_compiled':len(lua),
        'mock_cases':int(mock[1]),'mock_assertions':int(mock[2]),'lock_assertions':int(lock_result[1]),
        'native_cases':int(native[1]) if native else 0,'native_assertions':int(native[2]) if native else 0,
        'legacy_native_cases':int(legacy[1]) if legacy else 0,'legacy_native_assertions':int(legacy[2]) if legacy else 0,
        'limits':['Single-player method-level and simulated ownership tests only.',
                  'Inventory UI, full save reload and frame-time acceptance require the game.'],
        'logs':str(LOGS),'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [core,batch,craft,runtime,lock]}}
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
    return 0

if __name__=='__main__':
    try: sys.exit(main())
    except Exception as exc:
        LOGS.mkdir(parents=True,exist_ok=True)
        REPORT.write_text(json.dumps({'result':'FAIL','game_started':False,'world_created':False,'error':str(exc)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(str(exc),file=sys.stderr);sys.exit(1)
