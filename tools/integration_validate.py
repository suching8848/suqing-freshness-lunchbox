"""Offline native-parser, Kahlua integration and existing-upgrade-core checks.

Uses the game's parser classes and native ISHandcraftAction Lua completion code.
Inventory/player/recipe execution objects are deterministic shells, not a world.
Never launches Project Zomboid or reads/writes user saves or enabled lists.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MAIN = ROOT / 'mods/SuQingFreshnessLunchbox/42'
ORDINARY = Path(r'E:\code\suqing-container-upgrade\SuQingContainerUpgrade\42')
DEFAULT_JAVAC = Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')
PERSONAL_CORE = Path(r'C:\Users\15792\Zomboid\mods\SuQingContainerUpgrade_4221_Local\42\media\lua\shared\SuQingContainerUpgrade')
SOURCE_CORE = Path(r'E:\code\suqing-container-upgrade\SuQingContainerUpgrade\42\media\lua\shared\SuQingContainerUpgrade')
DEFAULT_DEPLOYMENT_TASK = GAME/'CodexAssets/SuQingFreshnessLunchbox_20261106_rc3_CU103/deployment-task.json'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def core_version(folder):
    matches=re.findall(r'^\s*C\.version\s*=\s*[\'\"]([^\'\"]+)[\'\"]',
        (folder/'Core.lua').read_text(encoding='utf-8-sig'),re.MULTILINE)
    if len(matches)!=1: raise RuntimeError('Expected one explicit Core.version: '+str(folder/'Core.lua'))
    return matches[0]

def select_references(deployment_task):
    current_version=core_version(PERSONAL_CORE)
    legacy_core=PERSONAL_CORE
    legacy_kind='current_personal_installation'
    receipt=None
    if current_version!='1.0.0':
        receipt=deployment_task.resolve()
        deployment=json.loads(receipt.read_text(encoding='utf-8-sig')).get('deployment',{})
        if deployment.get('result')!='PASS': raise RuntimeError('Deployment receipt is not successful: '+str(receipt))
        installed=deployment.get('ordinary_container',{})
        if Path(installed.get('path','')).resolve()!=PERSONAL_CORE.parents[4].resolve():
            raise RuntimeError('Deployment receipt points to a different personal container mod')
        raw=deployment.get('previous_container_recovery')
        if not isinstance(raw,str) or not raw or not Path(raw).is_absolute():
            raise RuntimeError('Deployment receipt has no absolute previous_container_recovery')
        legacy_core=Path(raw).resolve()/'42/media/lua/shared/SuQingContainerUpgrade'
        legacy_kind='deployment_recovery_copy'
    if core_version(legacy_core)!='1.0.0': raise RuntimeError('Legacy comparison must be verified version 1.0.0: '+str(legacy_core))
    for name in ['Core.lua','Compatibility.lua','Refund.lua']:
        if not (legacy_core/name).is_file(): raise FileNotFoundError(legacy_core/name)
    source_version=core_version(SOURCE_CORE)
    if source_version!='1.0.3': raise RuntimeError('Source comparison must be version 1.0.3: '+str(SOURCE_CORE))
    references={'current_personal_installation':{'core':str(PERSONAL_CORE),'version':current_version},
        'legacy_unsupported_control':{'core':str(legacy_core),'version':'1.0.0','kind':legacy_kind,
            'is_current_personal_installation':legacy_kind=='current_personal_installation',
            'deployment_receipt':str(receipt) if receipt else None,'core_sha256':sha(legacy_core/'Core.lua')},
        'source_builtin_control':{'core':str(SOURCE_CORE),'version':source_version}}
    return legacy_core,references

def run(command):
    result = subprocess.run([str(v) for v in command],cwd=GAME,encoding='utf-8',errors='replace',capture_output=True,timeout=90)
    output = result.stdout + result.stderr
    if result.returncode:
        raise RuntimeError(f'Exit {result.returncode}: {command[0]}\n{output}')
    return output.strip()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--javac',type=Path,default=DEFAULT_JAVAC)
    parser.add_argument('--report',type=Path,default=ROOT/'tests/integration_validation.json')
    parser.add_argument('--deployment-task',type=Path,default=DEFAULT_DEPLOYMENT_TASK,
        help='Successful deployment receipt identifying the preserved legacy 1.0.0 comparison')
    parser.add_argument('--inspect-references',action='store_true',
        help='Read and print version/path references only; do not compile, run tests or write reports')
    args=parser.parse_args()
    legacy_core,references=select_references(args.deployment_task)
    if args.inspect_references:
        print(json.dumps({'result':'PASS','references':references},ensure_ascii=False,indent=2))
        return 0
    java=GAME/'jre64/bin/java.exe'
    jar=GAME/'projectzomboid.jar'
    for needed in [args.javac,java,jar,legacy_core/'Core.lua',PERSONAL_CORE/'Core.lua',SOURCE_CORE/'Core.lua']:
        if not needed.is_file(): raise FileNotFoundError(needed)
    protected_files=list(dict.fromkeys(p for folder in [PERSONAL_CORE,legacy_core,SOURCE_CORE] for p in sorted(folder.glob('*.lua'))))
    protected_files.append(ORDINARY/'media/scripts/SuQingContainerUpgrade.txt')
    protected_before={str(p):sha(p) for p in protected_files}
    records=[]
    def result(name,detail):
        records.append({'name':name,'passed':True,'detail':detail})
        print(f'PASS {name}: {detail}',flush=True)
    run([args.javac,'-encoding','UTF-8',ROOT/'tools/integration_NativeAudit.java',ROOT/'tools/integration_KahluaRunner.java',ROOT/'tools/runtime_NativeProbe.java',ROOT/'tools/integration_NativeUpgrade.java'])
    # All cache/log files, if the parsers create any, stay inside the project.
    home=ROOT/'tests/integration_native_home';home.mkdir(exist_ok=True)
    base=[java,'--enable-native-access=ALL-UNNAMED',f'-Duser.home={home}','-cp',f'{ROOT / "tools"};{GAME};{jar};{GAME / "*"}']
    result('native_parsers',run(base+['integration_NativeAudit',MAIN,ORDINARY]))
    sources=sorted(MAIN.rglob('*.lua'))
    result('production_lua_compile',run(base+['integration_KahluaRunner','--compile']+sources))
    result('crafting_ui',run(base+['integration_KahluaRunner',
        ROOT/'tests/integration_bootstrap.lua',MAIN/'media/lua/shared/SuQingFreshnessLunchbox/Core.lua',
        GAME/'media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua',
        MAIN/'media/lua/shared/SuQingFreshnessLunchbox/Crafting.lua',
        MAIN/'media/lua/client/SuQingFreshnessLunchbox_Crafting.lua',MAIN/'media/lua/client/SuQingFreshnessLunchbox_UI.lua',
        ROOT/'tests/integration_crafting_cases.lua']))
    for label,core in [('legacy_1_0_0_unsupported',legacy_core),('source_1_0_3_builtin',SOURCE_CORE)]:
        result('container_upgrade_'+label,run(base+['integration_KahluaRunner',
            ROOT/'tests/integration_bootstrap.lua',MAIN/'media/lua/shared/SuQingFreshnessLunchbox/Core.lua',
            ROOT/'tests/integration_upgrade_setup.lua',core/'Compatibility.lua',core/'Core.lua',core/'Refund.lua',
            ROOT/'tests/integration_upgrade_cases.lua']))
    result('container_upgrade_source_native_items',run(base+['integration_NativeUpgrade',
        ROOT/'tests/integration_native_upgrade_bootstrap.lua',MAIN/'media/lua/shared/SuQingFreshnessLunchbox/Core.lua',
        SOURCE_CORE/'Compatibility.lua',SOURCE_CORE/'Core.lua',SOURCE_CORE/'Refund.lua',ROOT/'tests/integration_native_upgrade_cases.lua']))
    for mod in [MAIN]:
        translate=mod/'media/lua/shared/Translate'
        categories=sorted(p.name for p in (translate/'EN').glob('*.json'))
        for category in categories:
            locales={l:json.loads((translate/l/category).read_text(encoding='utf-8')) for l in ['CN','CH','EN']}
            assert set(locales['CN'])==set(locales['CH'])==set(locales['EN']),(mod,category,'translation keys')
            for key,english in locales['EN'].items():
                assert english and locales['CN'][key] and locales['CH'][key],key
                for lang in ['CN','CH']:
                    assert sorted(re.findall(r'%\d+',english))==sorted(re.findall(r'%\d+',locales[lang][key])),(key,lang,'placeholders')
        result('translation_coverage_'+mod.parent.name,f'{len(categories)} JSON categories; CN/CH/EN exact key and placeholder parity')
    recipes=(MAIN/'media/scripts/recipes_FreshnessLunchbox.txt').read_text(encoding='utf-8')
    assert 'Battery' not in recipes and 'ElectronicsScrap' not in recipes,'retired ingredients'
    input_ids=set(re.findall(r'Base\.[A-Za-z0-9_]+',recipes))
    vanilla='\n'.join(p.read_text(encoding='utf-8-sig',errors='strict') for p in (GAME/'media/scripts/generated/items').glob('*.txt'))
    for item_id in sorted(input_ids):
        assert re.search(r'\bitem\s+'+re.escape(item_id.split('.')[1])+r'\s*\{',vanilla),item_id
    result('vanilla_material_ids',f'{len(input_ids)} current native item definitions verified; no batteries or electronics scrap')
    protected={}
    for label,folder in [('current_personal',PERSONAL_CORE),('legacy_control',legacy_core),('source',SOURCE_CORE)]:
        protected[label]={str(p):sha(p) for p in sorted(folder.glob('*.lua'))}
    protected_after={str(p):sha(p) for p in protected_files}
    assert protected_after==protected_before,'reference source changed during validation'
    result('reference_source_preservation',f'{len(protected_before)} referenced ordinary-upgrade Lua/recipe files unchanged')
    def summary(name,pattern):
        detail=next(record['detail'] for record in records if record['name']==name)
        matched=re.search(pattern,detail)
        if not matched: raise RuntimeError('Missing regression summary: '+name)
        return tuple(int(value) for value in matched.groups())
    native_parser=summary('native_parsers',r'INTEGRATION_NATIVE assertions=(\d+) failures=0')[0]
    crafting_cases,crafting_assertions=summary('crafting_ui',r'INTEGRATION_CRAFT_UI cases=(\d+) assertions=(\d+) failures=0')
    legacy_cases,legacy_assertions=summary('container_upgrade_legacy_1_0_0_unsupported',r'INTEGRATION_UPGRADE core=1\.0\.0 cases=(\d+) assertions=(\d+) failures=0')
    upgrade_cases,upgrade_assertions=summary('container_upgrade_source_1_0_3_builtin',r'INTEGRATION_UPGRADE core=1\.0\.3 cases=(\d+) assertions=(\d+) failures=0')
    native_cases,native_assertions=summary('container_upgrade_source_native_items',r'INTEGRATION_NATIVE_UPGRADE core=1\.0\.3 cases=(\d+) assertions=(\d+) failures=0')
    report={'timestamp':datetime.now(timezone.utc).isoformat(),'result':'PASS','passed':True,'game_started':False,'world_created':False,
        'world_cell_created':False,'world_loaded':False,'native_singleton_initialized':True,
        'installed':False,'enabled':False,'game_jar_sha256':sha(jar),'scope':'native parser plus actual vanilla Lua completion and actual ordinary upgrade Core/Refund with deterministic object shells',
        'native_parser_assertions':native_parser,'crafting_ui_cases':crafting_cases,'crafting_ui_assertions':crafting_assertions,
        'legacy_unsupported_cases':legacy_cases,'legacy_unsupported_assertions':legacy_assertions,
        'builtin_upgrade_model_cases':upgrade_cases,'builtin_upgrade_model_assertions':upgrade_assertions,
        'builtin_upgrade_native_cases':native_cases,'builtin_upgrade_native_assertions':native_assertions,'shipped_lua_compiled':len(sources),
        'limitations':['No full native HandcraftLogic inventory transaction or game UI/world load executed; actual vanilla completion Lua uses deterministic recipe-data shells.',
            'Native upgrade tests use actual InventoryContainer/ItemContainer/material/Thread objects with actor and kept-input shells; native Core/Refund methods execute unchanged.',
            'Native recipe tests use parsed Item/CraftRecipe objects registered in an isolated ScriptManager fixture, then the actual post-dictionary cache resolver; no full mod loader or save is initialized.',
            'The verified legacy 1.0.0 comparison intentionally lacks lunchbox support; a preserved deployment recovery copy is not the current personal installation. Source 1.0.3 provides built-in support without an adapter.',
            'User must validate both recipe routes, rendering, inventory movement and save/reload in game.'],
        'results':records,'references':references,'reference_source_hashes':protected,'reference_recipe_hashes':{str(ORDINARY/'media/scripts/SuQingContainerUpgrade.txt'):sha(ORDINARY/'media/scripts/SuQingContainerUpgrade.txt')}}
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Report: '+str(args.report))
    return 0

if __name__=='__main__':
    report_arg=Path(sys.argv[sys.argv.index('--report')+1]) if '--report' in sys.argv else ROOT/'tests/integration_validation.json'
    try:
        exit_code=main()
    except Exception as error:
        if '--inspect-references' in sys.argv: raise
        failure={'timestamp':datetime.now(timezone.utc).isoformat(),'result':'FAIL','passed':False,
            'game_started':False,'world_created':False,'installed':False,'enabled':False,
            'error':str(error)}
        report_arg.parent.mkdir(parents=True,exist_ok=True)
        report_arg.write_text(json.dumps(failure,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        raise
    sys.exit(exit_code)
