"""Compile/run attachment bridge with the shipped Kahlua compiler, without a game.

Only rebuildable attachments_* diagnostics are written. Installed mods, settings,
enabled lists, saves, Steam and Workshop contents are never changed.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, re, subprocess

ROOT=Path(__file__).resolve().parents[1]
GAME=ROOT.parents[1]
OUTPUT=ROOT/'tests/attachments_validation'
REPORT=ROOT/'tests/attachments_validation.json'
BRIDGE=ROOT/'mods/SuQingFreshnessLunchbox/42/media/lua/client/SuQingFreshnessLunchbox_Attachments.lua'
VANILLA=GAME/'media/lua/client/Hotbar/ISHotbarAttachDefinition.lua'
CASES=ROOT/'tests/attachments_cases.lua'
JAVAC=Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def execute(label,command):
    home=OUTPUT/'native_home'
    home.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy()
    env.update(USERPROFILE=str(home),APPDATA=str(home/'AppData/Roaming'),LOCALAPPDATA=str(home/'AppData/Local'))
    result=subprocess.run([str(p) for p in command],cwd=GAME,env=env,text=True,encoding='utf-8',errors='replace',capture_output=True,timeout=90)
    output=result.stdout+result.stderr
    (OUTPUT/(label+'.log')).write_text(output,encoding='utf-8')
    if result.returncode: raise RuntimeError(label+' failed:\n'+output[-8000:])
    return output

def main():
    OUTPUT.mkdir(parents=True,exist_ok=True)
    runner=ROOT/'tools/attachments_KahluaRunner.java'
    inputs=[BRIDGE,VANILLA,CASES,runner]
    before={str(p):sha(p) for p in inputs}
    classes=OUTPUT/'classes';classes.mkdir(exist_ok=True)
    execute('javac',[JAVAC,'-encoding','UTF-8','-d',classes,runner])
    cp=os.pathsep.join(str(p) for p in [classes,GAME,GAME/'projectzomboid.jar',GAME/'*'])
    output=execute('kahlua',[GAME/'jre64/bin/java.exe','--enable-native-access=ALL-UNNAMED',f'-Duser.home={OUTPUT / "native_home"}','-cp',cp,'attachments_KahluaRunner',BRIDGE,VANILLA,CASES])
    match=re.search(r'ATTACHMENTS_KAHLUA cases=(\d+) assertions=(\d+) failures=0',output)
    if not match: raise RuntimeError('Missing attachment regression summary: '+output[-2000:])
    after={str(p):sha(p) for p in inputs}
    if before!=after: raise RuntimeError('Test inputs changed while running the regression')
    report={
        'timestamp_utc':datetime.now(timezone.utc).isoformat(),'result':'PASS',
        'cases':int(match[1]),'assertions':int(match[2]),'failures':0,
        'game_started':False,'game_ui_opened':False,'world_loaded':False,
        'installed':False,'enabled_lists_changed':False,'source_inputs_unchanged':True,
        'test_environment':'Shipped Project Zomboid Kahlua compiler/VM; real vanilla attachment definitions; deterministic definition/location/event shells.',
        'coverage':['Cold initialization and lifecycle retry','Existing three backpack-bottom types only','Preserved tent/sleeping-bag and unrelated mappings','No new slot or tick handler','Repeated startup and file reload','Missing definitions, events and locations','Duplicate or changed upstream definitions','Conflicting lunchbox mapping','Late upstream changes withdraw owned additions only','Missing translation bilingual fallback','Unexpected API errors remain visible'],
        'source_sha256':after,
        'limitations':['No game, UI, character, world or save was started.','Native equip/detach actions and visual model alignment still require user in-game acceptance.','No installed copy or Workshop content was changed.']}
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS '+match[0]);print('Report '+str(REPORT))

if __name__=='__main__':
    try: main()
    except Exception as exc:
        REPORT.write_text(json.dumps({'result':'FAIL','game_started':False,'error':str(exc)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        raise
