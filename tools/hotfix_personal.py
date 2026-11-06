"""Back up and replace only the authorized lunchbox mod; never write save/config files."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import importlib.util
import json
import os
import shutil

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
USER = Path(r"C:\Users\15792\Zomboid")
ARTIFACT = GAME / "CodexAssets/SuQingFreshnessLunchbox_20261106_rc4"
TARGET = USER / "mods/SuQingFreshnessLunchbox"
FROZEN = ARTIFACT / "release/mods/SuQingFreshnessLunchbox"
BACKUPS = Path(r"D:\GameBackups\ProjectZomboid")
SPEC = importlib.util.spec_from_file_location("verified_deployment", ROOT / "tools/deploy_personal.py")
H = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(H)

def check_task(task):
    task = task.resolve(strict=True)
    assert task.parent == BACKUPS.resolve(strict=True) and task.name.startswith("返鲜餐盒三项修复_")
    return task

def backup():
    H.closed()
    world = H.current_save()
    name = "返鲜餐盒三项修复_" + datetime.now(timezone(timedelta(hours=8))).strftime("%Y%m%d_%H%M%S")
    task = BACKUPS / name
    task.mkdir(exist_ok=False)
    previous = GAME / "CodexAssets/SuQingFreshnessLunchbox_20261106_rc3_CU103"
    paths = H.read_json(previous / "protected-before.json")["files"]
    # Protect current code outside this mod and every important save/config;
    # snapshot all world paths/metadata without creating another full-world copy.
    protected = {path: H.sha(Path(path)) for path in paths}
    protected[str(world / "global_mod_data.bin")] = H.sha(world / "global_mod_data.bin")
    main_before = H.hashes(TARGET)
    H.save_json(task / "protected-before.json", {"files": protected})
    H.save_json(task / "save-inventory-before.json", H.snapshot(world))
    H.save_json(task / "main-before.json", main_before)
    result = H.archive(TARGET, "lunchbox-rc3-before", task)
    H.closed()
    assert H.current_save() == world
    assert H.hashes(TARGET) == main_before and all(H.sha(Path(p)) == value for p, value in protected.items())
    receipt = {"result": "PASS", "verified_at": H.stamp(), "task": str(task), "save": str(world),
               "scope": "Complete existing lunchbox mod only; no world/configuration files are being written",
               "main_backup": result, "complete_world_backup_created_this_task": False,
               "earlier_complete_world_backup": r"D:\GameBackups\ProjectZomboid\返鲜餐盒正式档部署_20261106_144445\personal-save.zip",
               "earlier_world_backup_scope": "Pre-deployment historical world progress; does not include this later user gameplay",
               "world_and_config_protected": True}
    H.save_json(task / "backup-verification.json", receipt)
    H.save_json(ARTIFACT / "hotfix-task.json", {"task": str(task), "status": "backup_verified"})
    print(json.dumps(receipt, ensure_ascii=False), flush=True)

def apply(task):
    task = check_task(task)
    H.closed()
    assert not (task / "deployment.json").exists()
    receipt = H.read_json(task / "backup-verification.json")
    assert receipt["result"] == "PASS"
    backup = receipt["main_backup"]
    assert H.sha(Path(backup["archive"])) == backup["archive_sha256"]
    world = H.current_save()
    assert str(world) == receipt["save"]
    before = H.read_json(task / "main-before.json")
    protected = H.read_json(task / "protected-before.json")["files"]
    world_before = H.read_json(task / "save-inventory-before.json")
    assert H.hashes(TARGET) == before
    assert all(H.sha(Path(p)) == value for p, value in protected.items())
    assert H.snapshot(world) == world_before
    validation = H.read_json(ARTIFACT / "validation/offline-validation.json")
    assert validation["result"] == "PASS" and validation["version"] == "0.1.0-rc.4"
    expected = validation["source_manifest"]["SuQingFreshnessLunchbox"]
    assert H.hashes(FROZEN) == expected
    staging = USER / "CodexDeploymentRecovery" / task.name
    assert not staging.exists()
    assert TARGET.resolve().parent == (USER / "mods").resolve()
    staging.mkdir(parents=True)
    assert staging.resolve().parent == (USER / "CodexDeploymentRecovery").resolve()
    candidate = staging / "new-lunchbox-rc4"
    recovery = staging / "previous-lunchbox-rc3"
    shutil.copytree(FROZEN, candidate)
    assert H.hashes(candidate) == expected
    H.closed()
    assert H.hashes(TARGET) == before and all(H.sha(Path(p)) == value for p, value in protected.items())
    try:
        os.replace(TARGET, recovery)
        os.replace(candidate, TARGET)
        assert H.hashes(TARGET) == expected
        assert H.hashes(recovery) == before
        assert all(H.sha(Path(p)) == value for p, value in protected.items())
        assert H.snapshot(world) == world_before
        H.closed()
    except Exception as error:
        H.save_json(task / "deployment-interrupted.json", {"error": str(error), "time": H.stamp(), "old_mod": str(recovery)})
        raise
    result = {"result": "PASS", "deployed_at": H.stamp(), "task": str(task), "save": str(world),
              "installed": str(TARGET), "version": "0.1.0-rc.4", "files": len(expected),
              "previous_mod_recovery": str(recovery), "main_mod_backup": backup,
              "ordinary_container_version": "1.0.3", "ordinary_container_unchanged": True,
              "protected_file_count": len(protected), "protected_files_unchanged": True,
              "all_world_paths_and_metadata_unchanged": True, "enabled_lists_unchanged": True,
              "game_started": False, "in_game_tested": False, "workshop_modified": False}
    H.save_json(task / "deployment.json", result)
    H.save_json(ARTIFACT / "hotfix-task.json", {"task": str(task), "status": "deployed", "deployment": result})
    print(json.dumps(result, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["backup", "apply"])
    parser.add_argument("--task", type=Path)
    args = parser.parse_args()
    if args.command == "backup":
        backup()
    else:
        assert args.task
        apply(args.task)
