"""Read-only checks of the installed EX/compat code with the lunchbox candidate.

No game client, world cell, save, configuration, installed mod or enabled list is changed.
"""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parents[1]
GAME=ROOT.parents[1]
MAIN=ROOT/'mods/SuQingFreshnessLunchbox/42/media/lua'
PERSONAL=Path(os.environ['USERPROFILE'])/'Zomboid/mods'
EX=PERSONAL/'ExSuQingBackpackSuperUpgrade_4221/42'
BRIDGE=PERSONAL/'Codex_SuQingWearableCompat_4221/42/media/lua/client/Codex_SuQingHavenFallEX.lua'
ORDINARY=Path(r'E:\code\suqing-container-upgrade\SuQingContainerUpgrade\42\media\lua')
OUTPUT=ROOT/'tests/ex_guard_validation'
REPORT=ROOT/'tests/integration_ex_guard_validation.json'
JAVAC=Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def execute(label,command):
    env=os.environ.copy();home=OUTPUT/'native_home';home.mkdir(parents=True,exist_ok=True)
    env['USERPROFILE']=str(home);env['APPDATA']=str(home/'AppData/Roaming');env['LOCALAPPDATA']=str(home/'AppData/Local')
    r=subprocess.run([str(v) for v in command],cwd=GAME,env=env,text=True,encoding='utf-8',errors='replace',capture_output=True,timeout=120)
    output=r.stdout+r.stderr;(OUTPUT/(label+'.log')).write_text(output,encoding='utf-8')
    if r.returncode: raise RuntimeError(label+' failed:\n'+output[-10000:])
    return output
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--reproduce-only',action='store_true');args=parser.parse_args()
    OUTPUT.mkdir(parents=True,exist_ok=True)
    client=MAIN/'client/SuQingFreshnessLunchbox_Crafting.lua'
    rc2=OUTPUT/'rc2_Crafting.lua'
    if not rc2.exists():
        if 'F.Install()\nEvents.OnGameStart' in client.read_text(encoding='utf-8'): raise RuntimeError('Preserved original rc2 fixture required')
        rc2.write_bytes(client.read_bytes())
    shared_ex=[EX/'media/lua/shared/ExSuQingBackpackSuperUpgrade'/name for name in ['Core.lua','Capacity.lua','Refund.lua']]
    ex_client=EX/'media/lua/client/ExSuQingBackpackSuperUpgrade_Crafting.lua'
    ordinary=[ORDINARY/'shared/SuQingContainerUpgrade'/name for name in ['Compatibility.lua','Core.lua','Refund.lua']]
    ordinary+=[ORDINARY/'client'/name for name in ['SuQingContainerUpgrade_Crafting.lua','SuQingContainerUpgrade_Variant.lua']]
    original_files=[*shared_ex,ex_client,BRIDGE,*ordinary,EX/'media/scripts/ExSuQingBackpackSuperUpgrade.txt']
    before={str(p):sha(p) for p in original_files}
    classes=OUTPUT/'classes';classes.mkdir(exist_ok=True)
    execute('javac',[JAVAC,'-encoding','UTF-8','-d',classes,*[ROOT/'tools'/name for name in ['runtime_NativeProbe.java','integration_NativeAudit.java','integration_NativeUpgrade.java','integration_KahluaRunner.java']]])
    home=OUTPUT/'native_home';base=[GAME/'jre64/bin/java.exe','--enable-native-access=ALL-UNNAMED',f'-Duser.home={home}',f'-Dintegration.exRecipes={EX / "media/scripts/ExSuQingBackpackSuperUpgrade.txt"}','-cp',os.pathsep.join(str(p) for p in [classes,GAME,GAME/'projectzomboid.jar',GAME/'*'])]
    results=[]
    for native in [False,True]:
        scenarios=[('rc2_repro',rc2,True)]
        if not args.reproduce_only: scenarios += [('lunchbox_file_first',client,False),('havenfall_file_first',client,False)]
        for name,selected,broken in scenarios:
            label=('native_' if native else 'kahlua_')+name
            config=OUTPUT/(label+'_config.lua');config.write_text('GuardExpectBroken='+('true' if broken else 'false')+'\n',encoding='utf-8')
            bootstrap=ROOT/'tests'/('integration_native_upgrade_bootstrap.lua' if native else 'integration_bootstrap.lua')
            files=[bootstrap,ROOT/'tests/integration_ex_guard_setup.lua',GAME/'media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua',MAIN/'shared/SuQingFreshnessLunchbox/Core.lua',MAIN/'shared/SuQingFreshnessLunchbox/Crafting.lua',*ordinary,*shared_ex,ex_client]
            files += [selected,BRIDGE] if name=='lunchbox_file_first' else [BRIDGE,selected]
            files += [config,ROOT/'tests/integration_ex_guard_cases.lua']
            output=execute(label,base+[('integration_NativeUpgrade' if native else 'integration_KahluaRunner'),*files])
            pattern=r'EX_GUARD_RC2_REPRO native=(?:true|false) assertions=(\d+) failures=0' if broken else r'EX_GUARD_CHAIN native=(?:true|false) cases=(\d+) assertions=(\d+) failures=0'
            m=re.search(pattern,output)
            if not m: raise RuntimeError('Missing '+label+' summary')
            summary={'name':label,'passed':True,'cases':0 if broken else int(m[1]),'assertions':int(m[1] if broken else m[2])}
            results.append(summary);print('PASS '+label+' '+str(summary),flush=True)
    after={str(p):sha(p) for p in original_files}
    if after!=before: raise RuntimeError('Reference EX/ordinary/compat code changed during test')
    report={'timestamp':datetime.now(timezone.utc).isoformat(),'result':'PASS','game_started':False,'world_cell_created':False,'world_loaded':False,
        'native_singleton_initialized':True,'installed':False,'enabled':False,'results':results,'source_reference_hashes':after,
        'candidate_crafting_sha256':sha(client),'rc2_original_crafting_sha256':sha(rc2),
        'limitations':['Real installed EX Core/Capacity/Refund/Crafting and HavenFall bridge are unchanged; ordinary guard/variant and vanilla completion Lua execute unchanged.',
        'Native mode uses actual native InventoryContainer, ItemContainer, Item, CraftRecipe and material objects. Actor, loaded script manager, author capacity baseline and native HandcraftLogic selection/transaction remain deterministic fixtures.',
        'Guard identity, denial on an unknown outer wrapper, original EX action routing, native conversion protection, both lunchbox routes and repeated startup are tested; no game UI/world/save is opened.']}
    REPORT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('PASS report '+str(REPORT))
if __name__=='__main__':
    try: main()
    except Exception as exc:
        REPORT.write_text(json.dumps({'result':'FAIL','game_started':False,'world_cell_created':False,'error':str(exc)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');raise
