"""Reproduce rc.6's indexed-Set failure, then audit the current runtime fix.

Uses current LuaManager.Exposer, native Java HashSet/Iterator/ArrayList and the
actual Runtime.lua. Vehicle/Cell/item methods are controlled Lua shells, never
native vehicle constructors or gameplay. Only vehicle_collection_* diagnostics
are written inside this source repository.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib,json,os,re,subprocess

ROOT=Path(__file__).resolve().parents[1]
GAME=ROOT.parents[1]
OUTPUT=ROOT/'tests/vehicle_collection_validation'
REPORT=ROOT/'tests/vehicle_collection_validation.json'
JAVAC=Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')
RUNTIME=ROOT/'mods/SuQingFreshnessLunchbox/42/media/lua/client/SuQingFreshnessLunchbox_Runtime.lua'
LEGACY=GAME/'CodexAssets/SuQingFreshnessLunchbox_Attachments_20261107/candidate-0.1.0-rc.6/mods/SuQingFreshnessLunchbox/42/media/lua/client/SuQingFreshnessLunchbox_Runtime.lua'
BOOTSTRAP=ROOT/'tests/vehicle_collection_bootstrap.lua'
CASES=ROOT/'tests/vehicle_collection_cases.lua'
RUNNER=ROOT/'tools/vehicle_collection_NativeRunner.java'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def execute(label,cmd):
    home=OUTPUT/'native_home';home.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy();env.update(USERPROFILE=str(home),APPDATA=str(home/'AppData/Roaming'),LOCALAPPDATA=str(home/'AppData/Local'))
    result=subprocess.run([str(x) for x in cmd],cwd=GAME,env=env,text=True,encoding='utf-8',errors='replace',capture_output=True,timeout=120)
    out=result.stdout+result.stderr;(OUTPUT/(label+'.log')).write_text(out,encoding='utf-8')
    if result.returncode:raise RuntimeError(label+' failed:\n'+out[-9000:])
    return out
def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    if 'local vehicle=vehicles:get(i)' not in LEGACY.read_text(encoding='utf-8-sig'):
        raise RuntimeError('rc.6 frozen reproduction fixture no longer has the indexed-Set bug')
    before={str(p):sha(p) for p in [RUNTIME,LEGACY,BOOTSTRAP,CASES,RUNNER]}
    classes=OUTPUT/'classes';classes.mkdir(exist_ok=True)
    execute('javac',[JAVAC,'-encoding','UTF-8','-d',classes,RUNNER])
    cp=os.pathsep.join(str(x) for x in [classes,GAME,GAME/'projectzomboid.jar',GAME/'*'])
    base=[GAME/'jre64/bin/java.exe','--enable-native-access=ALL-UNNAMED',f'-Duser.home={OUTPUT / "native_home"}','-cp',cp,'vehicle_collection_NativeRunner']
    results=[]
    for label,runtime,legacy in [('legacy_rc6',LEGACY,True),('fixed_current',RUNTIME,False)]:
        output=execute(label,base+[BOOTSTRAP,runtime,CASES,str(legacy).lower()])
        marker='LEGACY_REPRO' if legacy else 'FIXED'
        match=re.search(r'VEHICLE_COLLECTION_'+marker+r' cases=(\d+) assertions=(\d+) failures=0',output)
        if not match:raise RuntimeError('Missing expected '+label+' summary')
        if 'world_cell_created=false vehicle_constructed=false actor_constructed=false game_started=false' not in output:
            raise RuntimeError('Missing isolated environment assertion')
        results.append({'label':label,'cases':int(match[1]),'assertions':int(match[2]),'failures':0})
        print('PASS '+match[0])
    after={str(p):sha(p) for p in [RUNTIME,LEGACY,BOOTSTRAP,CASES,RUNNER]}
    if after!=before:raise RuntimeError('Inputs changed during regression')
    report={'result':'PASS','timestamp_utc':datetime.now(timezone.utc).isoformat(),'results':results,
        'collection':'java.util.HashSet exposed by current LuaManager.Exposer',
        'native_methods':['HashSet.size','HashSet.iterator','Iterator.hasNext','Iterator.next','HashSet.contains','ArrayList.get','ArrayList.contains'],
        'actual_lua_methods':['Runtime.ScanVehicles','Runtime.ScanInventory','Runtime.Register pending-discovery branch','Runtime.Location vehicle membership branch'],
        'game_started':False,'world_cell_created':False,'native_vehicle_constructed':False,'native_actor_constructed':False,'installed':False,
        'source_input_sha256':after,'source_inputs_unchanged':True,
        'limitations':['Cell, square, vehicle, part, inventory and box are controlled Lua method shells; no claim of native BaseVehicle or in-game validation.',
            'R.ready=false deliberately covers discovery/pending registration without invoking food settlement, clocks or world systems.',
            'Real HashSet/Iterator and ArrayList methods are resolved through the current game LuaManager.Exposer; collections have different native APIs.',
            'No game, world, UI, save, installed mods or enablement configuration was opened or changed.']}
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('Report '+str(REPORT))
if __name__=='__main__':
    try:main()
    except Exception as exc:
        OUTPUT.mkdir(parents=True,exist_ok=True)
        REPORT.write_text(json.dumps({'result':'FAIL','game_started':False,'error':str(exc)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        raise
