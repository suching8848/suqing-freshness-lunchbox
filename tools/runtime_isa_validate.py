"""Actual ISA Utilities/Patches startup queue versus lunchbox event lifecycle.

Read-only source dependencies. Never starts a game, creates a world cell or loads a save.
"""
from pathlib import Path
import hashlib,json,os,re,subprocess
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[1];GAME=ROOT.parents[1]
LUA=ROOT/'mods/SuQingFreshnessLunchbox/42/media/lua'
ISA=GAME.parents[1]/'workshop/content/108600/3781944805/mods/ImmersiveSolarArrays/42/media/lua'
OUT=ROOT/'tests/runtime_isa_validation';REPORT=ROOT/'tests/runtime_isa_validation.json'
JAVAC=Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(label,command):
    env=os.environ.copy();home=OUT/'native_home';home.mkdir(parents=True,exist_ok=True)
    env['USERPROFILE']=str(home);env['APPDATA']=str(home/'AppData/Roaming');env['LOCALAPPDATA']=str(home/'AppData/Local')
    r=subprocess.run([str(v)for v in command],cwd=GAME,env=env,text=True,encoding='utf-8',errors='replace',capture_output=True,timeout=120)
    out=r.stdout+r.stderr;(OUT/(label+'.log')).write_text(out,encoding='utf-8')
    if r.returncode:raise RuntimeError(label+' failed:\n'+out[-10000:])
    return out
def main():
    OUT.mkdir(exist_ok=True,parents=True)
    utilities=ISA/'shared/ImmersiveSolarArrays/Utilities.lua';patches=ISA/'client/ImmersiveSolarArrays/Patches.lua'
    original={str(p):sha(p)for p in[utilities,patches]}
    util_wrapper=OUT/'actual_ISA_utilities.lua';util_wrapper.write_text('ISAUnderTest=(function()\n'+utilities.read_text(encoding='utf-8-sig')+'\nend)()\n',encoding='utf-8')
    patch_wrapper=OUT/'actual_ISA_patches.lua';patch_wrapper.write_bytes(patches.read_bytes())
    delayed=OUT/'actual_ISA_patches_on_game_start.lua';delayed.write_text('local function firstStart()\nEvents.OnGameStart.Remove(firstStart)\n'+patches.read_text(encoding='utf-8-sig')+'\nend\nEvents.OnGameStart.Add(firstStart)\n',encoding='utf-8')
    classes=OUT/'classes';classes.mkdir(exist_ok=True)
    run('javac',[JAVAC,'-encoding','UTF-8','-d',classes,*[ROOT/'tools'/n for n in ['runtime_KahluaAudit.java','runtime_NativeProbe.java','runtime_ISAEventProbe.java']]])
    base=[GAME/'jre64/bin/java.exe','--enable-native-access=ALL-UNNAMED',f'-Duser.home={OUT / "native_home"}','-cp',os.pathsep.join(str(p)for p in[classes,GAME,GAME/'projectzomboid.jar',GAME/'*'])]
    results=[]
    for native in[False,True]:
        for order in['rc3_repro','queue_before_runtime','queue_after_runtime','queue_added_at_game_start']:
            label=('native_'if native else'kahlua_')+order
            broken=order=='rc3_repro';config=OUT/(label+'_config.lua');config.write_text('ISAExpectBroken='+('true'if broken else'false')+'\n',encoding='utf-8')
            bootstrap=ROOT/'tests'/('runtime_native_event_bootstrap.lua'if native else'runtime_mock_bootstrap.lua')
            files=[bootstrap,ROOT/'tests/runtime_isa_bootstrap.lua',util_wrapper,LUA/'shared/SuQingFreshnessLunchbox/Core.lua']
            runtime=OUT/'rc3_Runtime.lua'if broken else LUA/'client/SuQingFreshnessLunchbox_Runtime.lua'
            files += [patch_wrapper,runtime]if order in['rc3_repro','queue_before_runtime']else[runtime,delayed if order=='queue_added_at_game_start'else patch_wrapper]
            files += [config,ROOT/'tests/runtime_isa_cases.lua']
            output=run(label,base+[('runtime_ISAEventProbe'if native else'runtime_KahluaAudit'),*files])
            pattern=r'ISA_RC3_REPRO native=(?:true|false) assertions=(\d+) PASS'if broken else r'ISA_LIFECYCLE native=(?:true|false) cases=(\d+) assertions=(\d+) PASS'
            match=re.search(pattern,output)
            if not match:raise RuntimeError('missing summary '+label)
            result={'name':label,'result':'PASS','cases':0 if broken else int(match[1]),'assertions':int(match[1]if broken else match[2])}
            results.append(result);print('PASS '+label+' '+str(result),flush=True)
    if original!={str(p):sha(p)for p in[utilities,patches]}:raise RuntimeError('ISA reference files changed during validation')
    report={'result':'PASS','timestamp':datetime.now(timezone.utc).isoformat(),'game_started':False,'world_cell_created':False,'world_loaded':False,
        'results':results,'isa_original_sha256':original,'rc3_runtime_sha256':sha(OUT/'rc3_Runtime.lua'),
        'candidate_runtime_sha256':sha(LUA/'client/SuQingFreshnessLunchbox_Runtime.lua'),
        'scope':'Full unchanged installed ISA Utilities.lua and Patches.lua, actual queueFunction Add/Remove, pre-world and normal event order, battery forwarding, menu/reentry and unknown outer hook.',
        'limits':['Native modes use actual Event Add/Remove/trigger and native item/ModData APIs, without an IsoWorld cell or player; mocks cover loaded ownership and aging separately.',
            'Native Event.trigger is called directly to make each ordered event dispatch deterministic rather than claiming wall-clock optimizer scheduling or full game-loop validation.',
            'ISA UI, power-bank server and author world objects are dependency shells; original battery command routing is observed. User gameplay acceptance remains required.']}
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('PASS report '+str(REPORT))
if __name__=='__main__':
    try:main()
    except Exception as e:REPORT.write_text(json.dumps({'result':'FAIL','game_started':False,'world_cell_created':False,'error':str(e)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');raise
