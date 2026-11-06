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
    global GAME
    parser=argparse.ArgumentParser()
    parser.add_argument('--game',type=Path,default=GAME)
    parser.add_argument('--javac',type=Path)
    parser.add_argument('--mock-only',action='store_true')
    parser.add_argument('--cooling-root',type=Path,default=Path(os.environ.get('USERPROFILE','~'))/'Zomboid'/'mods'/'SuQingRefrigerationUpgrade_4221'/'42')
    parser.add_argument('--fridge-root',type=Path,default=Path(os.environ.get('USERPROFILE','~'))/'Zomboid'/'mods'/'SuQingFreshnessFridge'/'42')
    args=parser.parse_args()
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
    classes=TESTS/'runtime_classes';classes.mkdir(exist_ok=True)
    sources=sorted((ROOT/'tools').glob('runtime_*.java'))
    execute('javac',[javac,'-encoding','UTF-8','-d',classes,*sources],TESTS/'runtime_compile_home')
    cp=os.pathsep.join(str(v) for v in (classes,game,jar,game/'*'))
    def jcmd(name,home,*files): return [java,f'-Duser.home={home}', '-cp',cp,name,*files]
    lua=sorted((ROOT/'mods').rglob('*.lua'))
    compile_log=execute('compile',jcmd('runtime_LuaCompile',TESTS/'runtime_compile_home',*lua),TESTS/'runtime_compile_home')
    core=ROOT/'mods'/'SuQingFreshnessLunchbox'/'42'/'media'/'lua'/'shared'/'SuQingFreshnessLunchbox'/'Core.lua'
    runtime=ROOT/'mods'/'SuQingFreshnessLunchbox'/'42'/'media'/'lua'/'client'/'SuQingFreshnessLunchbox_Runtime.lua'
    mock_log=execute('mock',jcmd('runtime_KahluaAudit',TESTS/'runtime_mock_home',TESTS/'runtime_mock_bootstrap.lua',core,runtime,TESTS/'runtime_mock_cases.lua'),TESTS/'runtime_mock_home')
    m=re.search(r'RUNTIME_MOCK cases=(\d+) assertions=(\d+) PASS',mock_log)
    if not m: raise RuntimeError('Missing mock summary')
    n=None
    combination={}
    combination_mock=None
    if not args.mock_only:
        native_files=[TESTS/'runtime_native_bootstrap.lua',core,TESTS/'runtime_native_cases.lua']
        cold_files=[args.cooling_root/'media'/'lua'/'shared'/'SuQingRefrigeration'/'Core.lua',args.cooling_root/'media'/'lua'/'client'/'SuQingRefrigeration_Runtime.lua']
        fridge_file=args.fridge_root/'media'/'lua'/'shared'/'SuQingFreshnessFridge'/'Core.lua'
        fridge_runtime=args.fridge_root/'media'/'lua'/'client'/'SuQingFreshnessFridge_Runtime.lua'
        if all(p.is_file() for p in cold_files):
            native_files.extend(cold_files)
            combination['cooling']={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in cold_files}
            if fridge_file.is_file():
                native_files.append(fridge_file)
                combination['fridge']={str(fridge_file):hashlib.sha256(fridge_file.read_bytes()).hexdigest()}
            if fridge_file.is_file() and fridge_runtime.is_file():
                combination['fridge'][str(fridge_runtime)]=hashlib.sha256(fridge_runtime.read_bytes()).hexdigest()
                combination_log=execute('combination_mock',jcmd('runtime_KahluaAudit',TESTS/'runtime_combination_home',TESTS/'runtime_mock_bootstrap.lua',core,runtime,*cold_files,fridge_file,fridge_runtime,TESTS/'runtime_mock_combination.lua'),TESTS/'runtime_combination_home')
                combination_mock=re.search(r'RUNTIME_COMBINATION_MOCK cases=(\d+) assertions=(\d+) PASS',combination_log)
                if not combination_mock: raise RuntimeError('Missing combination runtime mock summary')
            native_files.append(TESTS/'runtime_native_combination.lua')
        native_log=execute('native',jcmd('runtime_NativeProbe',TESTS/'runtime_native_home',*native_files),TESTS/'runtime_native_home')
        n=re.search(r'RUNTIME_NATIVE(?:_BASE)? cases=(\d+) assertions=(\d+) PASS',native_log)
        all_native=list(re.finditer(r'RUNTIME_NATIVE(?:_BASE)? cases=(\d+) assertions=(\d+) PASS',native_log))
        if all_native: n=all_native[-1]
        if not n: raise RuntimeError('Missing native summary')
    report={'result':'PASS','checked_utc':datetime.now(timezone.utc).isoformat(),'game_started':False,'world_created':False,'in_game_tested':False,
        'world_cell_created':False,'world_loaded':False,'native_singleton_initialized':bool(n),
        'game_jar':str(jar),'game_jar_sha256':hashlib.sha256(jar.read_bytes()).hexdigest(),'lua_compiled':len(lua),
        'mock_cases':int(m[1]),'mock_assertions':int(m[2]),'native_cases':int(n[1]) if n else 0,'native_assertions':int(n[2]) if n else 0,'combination_sources':combination,
        'combination_mock_cases':int(combination_mock[1]) if combination_mock else 0,'combination_mock_assertions':int(combination_mock[2]) if combination_mock else 0,
        'limits':['Only single-player method-level and simulated ownership tests; user must perform in-game acceptance.',
          'Current negative native rotten-removal policy uses true Age; enabled/unknown removal refuses unsafe rotten restoration.',
          'Uncovered/disabled/truncated gameplay history reanchors conservatively, without retroactive restoration.',
          'Unrecognized Java code changing both Age and lastAged cannot be reliably distinguished from native aging.'],
        'logs':str(LOGS),'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [core,runtime]}}
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
    return 0

if __name__=='__main__':
    try: sys.exit(main())
    except Exception as exc:
        LOGS.mkdir(parents=True,exist_ok=True)
        REPORT.write_text(json.dumps({'result':'FAIL','game_started':False,'world_created':False,'error':str(exc)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(str(exc),file=sys.stderr);sys.exit(1)
