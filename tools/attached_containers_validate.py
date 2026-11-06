"""Targeted offline attachment UI/ordinary-upgrade bridge regression; no game or deployment."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MAIN = ROOT / 'mods/SuQingFreshnessLunchbox/42/media/lua'
ORDINARY = Path(r'E:\code\suqing-container-upgrade\SuQingContainerUpgrade\42\media\lua\shared\SuQingContainerUpgrade')
JDK = Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin')
TARGET = MAIN / 'client/SuQingFreshnessLunchbox_AttachedContainers.lua'


def run(command):
    result = subprocess.run([str(value) for value in command], cwd=GAME, capture_output=True, encoding='utf-8', errors='replace')
    output = result.stdout + result.stderr
    if result.returncode:
        raise AssertionError(output)
    return output.strip()


def method(text, signature):
    start = text.index(signature)
    end = re.search(r'\n  (?:public|private|protected|static) ', text[start + len(signature):])
    return text[start:] if not end else text[start:start + len(signature) + end.start()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, default=ROOT / 'tests/attached_containers_validation.json')
    args = parser.parse_args()
    workspace = ROOT / 'tests/attached_containers_validation'
    classes = workspace / 'classes'
    classes.mkdir(parents=True, exist_ok=True)
    run([JDK / 'javac.exe', '-encoding', 'UTF-8', '-d', classes, ROOT / 'tools/integration_KahluaRunner.java'])
    cp = f'{classes};{GAME / "pzopt/aot/pzopt.jar"};{GAME / "projectzomboid.jar"};{GAME};{GAME / "*"}'
    java = [GAME / 'jre64/bin/java.exe', '--enable-native-access=ALL-UNNAMED',
            f'-Duser.home={workspace / "home"}', '-Dfile.encoding=UTF-8', '-cp', cp, 'integration_KahluaRunner']
    common = [ROOT / 'tests/integration_bootstrap.lua', MAIN / 'shared/SuQingFreshnessLunchbox/Core.lua',
              ROOT / 'tests/attached_containers_setup.lua']
    records = []
    for name, files in [
        ('native_kahlua_compile', ['--compile', TARGET]),
        ('container_ui_and_wrapper_boundaries', common + [TARGET, ROOT / 'tests/attached_containers_cases.lua']),
        ('actual_ordinary_core_calls', common + [ROOT / 'tests/integration_upgrade_setup.lua',
            ORDINARY / 'Compatibility.lua', ORDINARY / 'Core.lua', ORDINARY / 'Refund.lua',
            TARGET, ROOT / 'tests/attached_containers_native_core_cases.lua']),
    ]:
        output = run(java + files)
        records.append({'name': name, 'result': 'PASS', 'output': output})
        print(output, flush=True)
    # Execute the installed ordinary/EX/HavenFall Lua and vanilla completion in
    # both file orders. This bridge must not disturb the strict outer identity.
    personal = Path(r'C:\Users\15792\Zomboid\mods')
    ex = personal / 'ExSuQingBackpackSuperUpgrade_4221/42/media/lua'
    havenfall = personal / 'Codex_SuQingWearableCompat_4221/42/media/lua/client/Codex_SuQingHavenFallEX.lua'
    lunchbox_client = MAIN / 'client/SuQingFreshnessLunchbox_Crafting.lua'
    ordinary_client = ORDINARY.parents[1] / 'client'
    fixture = workspace / 'chain_config.lua'
    fixture.write_text('GuardExpectBroken=false\n', encoding='utf-8')
    for first in ['lunchbox_file_first', 'havenfall_file_first']:
        files = [ROOT / 'tests/integration_bootstrap.lua', ROOT / 'tests/integration_ex_guard_setup.lua',
            GAME / 'media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua',
            MAIN / 'shared/SuQingFreshnessLunchbox/Core.lua', MAIN / 'shared/SuQingFreshnessLunchbox/Crafting.lua',
            ORDINARY / 'Compatibility.lua', ORDINARY / 'Core.lua', ORDINARY / 'Refund.lua',
            ordinary_client / 'SuQingContainerUpgrade_Crafting.lua', ordinary_client / 'SuQingContainerUpgrade_Variant.lua',
            *[ex / 'shared/ExSuQingBackpackSuperUpgrade' / name for name in ['Core.lua', 'Capacity.lua', 'Refund.lua']],
            ex / 'client/ExSuQingBackpackSuperUpgrade_Crafting.lua']
        files += [lunchbox_client, havenfall] if first == 'lunchbox_file_first' else [havenfall, lunchbox_client]
        files += [TARGET, fixture, ROOT / 'tests/integration_ex_guard_cases.lua',
                  ROOT / 'tests/attached_containers_completion_cases.lua']
        output = run(java + files)
        records.append({'name': 'strict_ex_chain_' + first, 'result': 'PASS', 'output': output})
        print(output, flush=True)
    classpath = f'{GAME / "pzopt/aot/pzopt.jar"};{GAME / "projectzomboid.jar"}'
    def bytecode(name):
        return run([JDK / 'javap.exe', '-classpath', classpath, '-c', '-p', name])
    character = bytecode('zombie.characters.IsoGameCharacter')
    inventory = bytecode('zombie.inventory.InventoryItem')
    script = bytecode('zombie.scripting.objects.Item')
    equipped = method(character, 'public boolean isEquipped(zombie.inventory.InventoryItem);')
    assert 'isEquippedClothing' in equipped and 'isHandItem' in equipped and 'isAttachedItem' not in equipped
    attached = method(character, 'public boolean isAttachedItem(zombie.inventory.InventoryItem);')
    assert 'getAttachedItems' in attached and 'AttachedItems.contains' in attached
    weight = method(character, 'public float getInventoryWeight();')
    assert 'getAttachedSlot' in weight and 'getHotbarEquippedWeight' in weight
    hotbar_weight = method(inventory, 'public float getHotbarEquippedWeight();')
    assert '0.7f' in hotbar_weight and 'getContentsWeight' in hotbar_weight
    static_model = method(inventory, 'public java.lang.String getStaticModel();')
    assert 'zombie/scripting/objects/Item.getStaticModel' in static_model
    attachment_type = method(inventory, 'public java.lang.String getAttachmentType();')
    assert 'Field attachmentType' in attachment_type
    # Current Item.InstanceItem populates this nonserialized field from the current script.
    assert 'InventoryItem.setAttachmentType' in script
    assert len(re.findall(r'// Field attachmentType:', inventory)) == 2
    records.append({'name': 'current_native_method_semantics', 'result': 'PASS', 'checks': [
        'isEquipped includes worn/hands, excludes attached collection',
        'isAttachedItem queries actual attached collection',
        'attached inventory weight follows native hotbar weight branch',
        'normal hotbar weight is 0.7 times item plus contents, without invented reductions',
        'static model reads current script unless a separate explicit per-item override exists',
        'current script instance initialization supplies nonserialized attachment type; no custom item migration',
    ]})
    report = {'result': 'PASS', 'checked_at_bjt': datetime.now(timezone(timedelta(hours=8))).isoformat(),
              'game_started': False, 'world_loaded': False, 'deployed': False, 'checks': records,
              'source_sha256': hashlib.sha256(TARGET.read_bytes()).hexdigest(),
              'scope': 'Current native Kahlua and Java bytecode; deterministic actor/inventory shells, no UI/game state'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'result': 'PASS', 'groups': len(records), 'report': str(args.report)}))


if __name__ == '__main__':
    main()
