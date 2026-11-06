"""Authorized personal deployment. Full verified backup precedes every game-data write."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile
from concurrent.futures import ThreadPoolExecutor
from collections import deque

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
USER = Path(r"C:\Users\15792\Zomboid")
ARTIFACT = GAME / "CodexAssets/SuQingFreshnessLunchbox_20261106_rc2"
FROZEN = ARTIFACT / "release/mods"
BACKUPS = Path(r"D:\GameBackups\ProjectZomboid")
OLD_MOD = USER / "mods/SuQingContainerUpgrade_4221_Local"
NEW_BOX = USER / "mods/SuQingFreshnessLunchbox"
BOX_ID = "SuQingFreshnessLunchbox"
RETIRED_ID = "SuQingFreshnessLunchbox_ContainerUpgrade"
POWERSHELL = Path(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")

def stamp():
    return datetime.now(timezone(timedelta(hours=8))).isoformat()

def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def digest_stream(stream):
    result = hashlib.sha256()
    while data := stream.read(1024 * 1024):
        result.update(data)
    return result.hexdigest()

def sha(path):
    with path.open("rb") as source:
        return digest_stream(source)

def closed():
    code = r"$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match '^ProjectZomboid.*\.exe$' -or ($_.Name -match '^javaw?\.exe$' -and $_.CommandLine -match 'zombie\.gameStates\.MainScreenState|zombie\.GameWindow|zombie\.network\.GameServer') } | Select-Object ProcessId,Name,CommandLine | ConvertTo-Json -Compress"
    encoded = base64.b64encode(code.encode("utf-16-le")).decode("ascii")
    result = subprocess.run([str(POWERSHELL), "-NoProfile", "-EncodedCommand", encoded], capture_output=True, text=True, check=True)
    if result.stderr.strip():
        raise RuntimeError("Cannot verify game process state: " + result.stderr)
    if result.stdout.strip():
        raise RuntimeError("Game process is running; normal exit is required: " + result.stdout)

def current_save():
    lines = (USER / "latestSave.ini").read_text(encoding="utf-8-sig").splitlines()
    assert len(lines) == 2 and lines[1] == "Sandbox" and re.fullmatch(r"[A-Za-z0-9_-]+", lines[0])
    result = (USER / "Saves" / lines[1] / lines[0]).resolve(strict=True)
    assert result.parent == (USER / "Saves/Sandbox").resolve(strict=True)
    return result

def snapshot(folder):
    files, directories = {}, []
    pending = [folder]
    while pending:
        parent = pending.pop()
        # Explicit scandir fails on any inaccessible directory; Path.rglob may
        # silently suppress OSError and cannot establish complete backup scope.
        with os.scandir(parent) as listing:
            entries = sorted(listing, key=lambda entry: entry.name)
        for entry in entries:
            path = Path(entry.path)
            info = entry.stat(follow_symlinks=False)
            assert not entry.is_symlink() and not (getattr(info, "st_file_attributes", 0) & 0x400), "Reparse path: " + str(path)
            relative = path.relative_to(folder).as_posix()
            if stat.S_ISDIR(info.st_mode):
                directories.append(relative)
                pending.append(path)
            else:
                assert stat.S_ISREG(info.st_mode), "Unsupported file type: " + str(path)
                files[relative] = {"bytes": info.st_size, "mtime_ns": info.st_mtime_ns}
    return {"directories": sorted(directories), "files": dict(sorted(files.items()))}

def hashes(folder):
    return {relative: {"bytes": info["bytes"], "sha256": sha(folder / relative)}
            for relative, info in snapshot(folder)["files"].items()}

def candidate():
    receipt = read_json(ARTIFACT / "发行包校验回执.json")
    report = read_json(ARTIFACT / "validation/offline-validation.json")
    assert report["result"] == "PASS" and sha(Path(receipt["archive"])) == receipt["sha256"]
    assert {p.name for p in FROZEN.iterdir()} == {BOX_ID, "SuQingContainerUpgrade"}
    for name, expected in report["source_manifest"].items():
        assert hashes(FROZEN / name) == expected, "Frozen content changed: " + name
    return report["source_manifest"]

def ids(data):
    return re.findall(rb"(?m)^[ \t]*mod[ \t]*=[ \t]*([^,\r\n]+),", data)

def check_task(task):
    task = task.resolve(strict=True)
    assert task.parent == BACKUPS.resolve(strict=True) and task.name.startswith("返鲜餐盒正式档部署_")
    return task

def archive(folder, name, task):
    initial = snapshot(folder)
    count = len(initial["files"])
    total = sum(item["bytes"] for item in initial["files"].values())
    assert shutil.disk_usage(task).free > total + 512 * 1024 * 1024, "Insufficient backup space"
    partial = task / (name + ".zip.partial")
    target = task / (name + ".zip")
    assert not partial.exists() and not target.exists()
    print(json.dumps({"phase": "archive_start", "name": name, "files": count, "bytes": total}), flush=True)
    records = {}
    def read_source(pair):
        relative, info = pair
        path = folder / relative
        with path.open("rb") as source:
            opened = os.fstat(source.fileno())
            assert (opened.st_size, opened.st_mtime_ns) == (info["bytes"], info["mtime_ns"]), "Source changed: " + relative
            data = source.read()
            finished = os.fstat(source.fileno())
            assert (finished.st_size, finished.st_mtime_ns) == (info["bytes"], info["mtime_ns"]), "Source changed during read: " + relative
        assert len(data) == info["bytes"]
        return relative, info, data, hashlib.sha256(data).hexdigest(), opened
    def ordered_parallel(function, values):
        # Bounded lookahead avoids submitting hundreds of thousands of Futures.
        with ThreadPoolExecutor(max_workers=12) as pool:
            pending = deque()
            iterator = iter(values)
            for value in iterator:
                pending.append(pool.submit(function, value))
                if len(pending) >= 48:
                    yield pending.popleft().result()
            while pending:
                yield pending.popleft().result()
    class AppendOnly:
        # Streaming ZIP uses data descriptors and avoids a seek/write cycle for
        # every small file. The archive still has standard CRC and central data.
        def __init__(self, stream): self.stream, self.position = stream, 0
        def write(self, data):
            written = self.stream.write(data)
            self.position += written
            return written
        def tell(self): return self.position
        def flush(self): self.stream.flush()
    with partial.open("wb", buffering=4 * 1024 * 1024) as raw, zipfile.ZipFile(AppendOnly(raw), "w", zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=True) as output:
        for directory in initial["directories"]:
            output.writestr(directory + "/", b"")
        for index, (relative, info, data, fingerprint, original) in enumerate(ordered_parallel(read_source, initial["files"].items()), 1):
            entry = zipfile.ZipInfo(relative, datetime.fromtimestamp(original.st_mtime).timetuple()[:6])
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = (original.st_mode & 0xFFFF) << 16
            output.writestr(entry, data, compresslevel=1)
            records[relative] = dict(info, sha256=fingerprint)
            if index % 10000 == 0:
                print(json.dumps({"phase": "archive_write", "name": name, "done": index, "total": count}), flush=True)
    assert snapshot(folder) == initial, "Source inventory changed during backup"
    print(json.dumps({"phase": "archive_verify", "name": name, "files": count}), flush=True)
    with zipfile.ZipFile(partial) as check:
        expected = set(records) | {p + "/" for p in initial["directories"]}
        assert len(check.namelist()) == len(expected) and set(check.namelist()) == expected
        def current_hash(pair):
            relative, info = pair
            return relative, info, sha(folder / relative)
        for index, (relative, info, current_digest) in enumerate(ordered_parallel(current_hash, records.items()), 1):
            with check.open(relative) as content:
                assert digest_stream(content) == info["sha256"], "Archive content mismatch: " + relative
            assert check.getinfo(relative).file_size == info["bytes"]
            assert current_digest == info["sha256"], "Source changed after backup: " + relative
            if index % 10000 == 0:
                print(json.dumps({"phase": "archive_verified", "name": name, "done": index, "total": count}), flush=True)
    assert snapshot(folder) == initial, "Source inventory changed during verification"
    os.replace(partial, target)
    save_json(task / (name + "-manifest.json"), {"source": str(folder), "snapshot": initial, "files": records})
    result = {"result": "PASS", "source": str(folder), "archive": str(target), "files": count,
              "directories": len(initial["directories"]), "source_bytes": total, "archive_bytes": target.stat().st_size,
              "archive_sha256": sha(target), "all_members_sha256_verified": True, "source_stable": True,
            "hidden_files_included": True, "exclusions": [], "enumeration_method": "strict os.scandir", "parallel_readers": 12}
    print(json.dumps({"phase": "archive_complete", **result}, ensure_ascii=False), flush=True)
    return result

def backup():
    closed()
    world = current_save()
    candidate()
    assert OLD_MOD.is_dir() and not NEW_BOX.exists()
    enabled = ids((world / "mods.txt").read_bytes())
    assert enabled.count(b"SuQingContainerUpgrade_4221") == 1 and b"SuQingContainerUpgradeAuto_4221" not in enabled
    assert BOX_ID.encode() not in enabled and RETIRED_ID.encode() not in enabled
    name = "返鲜餐盒正式档部署_" + datetime.now(timezone(timedelta(hours=8))).strftime("%Y%m%d_%H%M%S")
    task = BACKUPS / name
    task.mkdir(exist_ok=False)
    save_json(ARTIFACT / "deployment-task.json", {"task": str(task), "status": "backup_in_progress"})
    print(json.dumps({"phase": "task_created", "task": str(task), "save": str(world)}, ensure_ascii=False), flush=True)
    protected_paths = read_json(ARTIFACT / "protected-before.json")["files"]
    protected = {path: sha(Path(path)) for path in protected_paths}
    save_json(task / "protected-before.json", {"files": protected})
    configs = {}
    for label, path in {"save-mods.txt": world / "mods.txt", "default.txt": USER / "mods/default.txt",
                        "latestSave.ini": USER / "latestSave.ini"}.items():
        target = task / "configuration" / label
        target.parent.mkdir(exist_ok=True)
        shutil.copy2(path, target)
        assert sha(target) == sha(path)
        configs[label] = {"source": str(path), "backup": str(target), "sha256": sha(path)}
    world_result = archive(world, "personal-save", task)
    closed()
    assert current_save() == world
    mod_result = archive(OLD_MOD, "ordinary-container-before", task)
    assert all(sha(Path(path)) == fingerprint for path, fingerprint in protected.items()), "Protected files changed during backup"
    closed()
    receipt = {"result": "PASS", "verified_at": stamp(), "task": str(task), "save": str(world),
               "save_backup": world_result, "mod_backup": mod_result, "configuration": configs,
               "complete_world_backup": True, "game_closed": True, "source_stable": True}
    save_json(task / "backup-verification.json", receipt)
    save_json(ARTIFACT / "deployment-task.json", {"task": str(task), "status": "backup_verified"})
    print(json.dumps({"phase": "backup_complete", "result": "PASS", "task": str(task)}, ensure_ascii=False), flush=True)

def atomic_write(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".suqing-lunchbox-", suffix=".tmp", delete=False) as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
        temporary = Path(stream.name)
    os.replace(temporary, path)

def strict_verify(task):
    task = check_task(task)
    closed()
    receipt = read_json(task / "backup-verification.json")
    assert receipt["result"] == "PASS"
    for name, key in [("personal-save", "save_backup"), ("ordinary-container-before", "mod_backup")]:
        record = receipt[key]
        folder = Path(record["source"])
        stored = read_json(task / (name + "-manifest.json"))
        assert snapshot(folder) == stored["snapshot"], "Strict inventory differs from backup: " + name
        assert sha(Path(record["archive"])) == record["archive_sha256"]
        def read_hash(pair):
            relative, item = pair
            return relative, item, sha(folder / relative)
        with ThreadPoolExecutor(max_workers=12) as pool:
            pending = deque()
            iterator = iter(stored["files"].items())
            index = 0
            while True:
                while len(pending) < 48:
                    pair = next(iterator, None)
                    if pair is None:
                        break
                    pending.append(pool.submit(read_hash, pair))
                if not pending:
                    break
                relative, item, current_digest = pending.popleft().result()
                assert current_digest == item["sha256"], "Strict source content changed: " + relative
                index += 1
                if index % 10000 == 0:
                    print(json.dumps({"phase": "strict_source_verify", "name": name, "done": index, "total": len(stored["files"])}), flush=True)
        assert snapshot(folder) == stored["snapshot"]
    closed()
    receipt["strict_enumeration_verified"] = True
    receipt["strict_verified_at"] = stamp()
    receipt["enumeration_method"] = "Explicit os.scandir, fail on every stat/scandir exception, reject all reparse paths"
    save_json(task / "backup-verification.json", receipt)
    print(json.dumps({"phase": "strict_backup_verified", "result": "PASS", "task": str(task)}, ensure_ascii=False), flush=True)

def deploy(task):
    task = check_task(task)
    closed()
    backup_receipt = read_json(task / "backup-verification.json")
    assert backup_receipt["result"] == "PASS" and backup_receipt["complete_world_backup"]
    assert backup_receipt.get("strict_enumeration_verified") is True
    assert not (task / "deployment.json").exists()
    world = current_save()
    assert str(world) == backup_receipt["save"]
    world_manifest = read_json(task / "personal-save-manifest.json")
    assert snapshot(world) == world_manifest["snapshot"], "World changed since verified backup"
    for key in ["save_backup", "mod_backup"]:
        record = backup_receipt[key]
        assert sha(Path(record["archive"])) == record["archive_sha256"]
    old_manifest = read_json(task / "ordinary-container-before-manifest.json")
    assert hashes(OLD_MOD) == {p: {"bytes": x["bytes"], "sha256": x["sha256"]} for p, x in old_manifest["files"].items()}
    expected = candidate()
    protected = read_json(task / "protected-before.json")["files"]
    assert all(sha(Path(p)) == fingerprint for p, fingerprint in protected.items())
    config = world / "mods.txt"
    before = config.read_bytes()
    assert before == (task / "configuration/save-mods.txt").read_bytes()
    block = re.search(rb"(?ms)(^mods[ \t]*\r?\n\{[ \t]*\r?\n.*?)(^\})", before)
    assert block and BOX_ID.encode() not in ids(before) and RETIRED_ID.encode() not in ids(before)
    newline = b"\r\n" if b"\r\n" in before else b"\n"
    addition = b"    mod = SuQingFreshnessLunchbox," + newline
    after = before[:block.end(1)] + addition + before[block.end(1):]
    assert ids(after) == ids(before) + [BOX_ID.encode()]
    staging = USER / "CodexDeploymentRecovery" / task.name
    assert not staging.exists() and not NEW_BOX.exists()
    staging.mkdir(parents=True)
    new_container = staging / "new-container"
    new_box = staging / "new-lunchbox"
    previous_container = staging / "previous-container-1.0.0"
    assert staging.resolve().parent == (USER / "CodexDeploymentRecovery").resolve()
    assert OLD_MOD.resolve().parent == (USER / "mods").resolve() and NEW_BOX.parent.resolve() == OLD_MOD.parent.resolve()
    shutil.copytree(FROZEN / "SuQingContainerUpgrade", new_container)
    shutil.copytree(FROZEN / BOX_ID, new_box)
    assert hashes(new_container) == expected["SuQingContainerUpgrade"] and hashes(new_box) == expected[BOX_ID]
    closed()
    assert snapshot(world) == world_manifest["snapshot"] and config.read_bytes() == before
    phase = "prepared"
    try:
        os.replace(OLD_MOD, previous_container)
        phase = "old_container_preserved"
        os.replace(new_container, OLD_MOD)
        phase = "container_replaced"
        os.replace(new_box, NEW_BOX)
        phase = "lunchbox_installed"
        assert hashes(OLD_MOD) == expected["SuQingContainerUpgrade"] and hashes(NEW_BOX) == expected[BOX_ID]
        assert config.read_bytes() == before
        atomic_write(config, after)
        phase = "save_enabled"
        assert config.read_bytes() == after
        changes = [p for p, fingerprint in protected.items() if sha(Path(p)) != fingerprint]
        allowed = {str(config)} | {str(OLD_MOD / p) for p in old_manifest["files"]}
        assert set(changes) <= allowed, "Unrelated protected file changed: " + str(set(changes) - allowed)
        current = snapshot(world)
        reference = world_manifest["snapshot"]
        assert current["directories"] == reference["directories"] and set(current["files"]) == set(reference["files"])
        assert all(current["files"][p] == x for p, x in reference["files"].items() if p != "mods.txt")
        assert (USER / "mods/default.txt").read_bytes() == (task / "configuration/default.txt").read_bytes()
        closed()
    except Exception as error:
        save_json(task / "deployment-interrupted.json", {"phase": phase, "error": str(error), "time": stamp(),
                  "previous_container": str(previous_container), "save_mods_backup": str(task / "configuration/save-mods.txt"),
                  "note": "Do not launch the game until the recorded phase has been reviewed."})
        raise
    result = {"result": "PASS", "deployed_at": stamp(), "save": str(world), "backup": str(task),
              "backup_verification": str(task / "backup-verification.json"), "complete_world_backup": True,
              "ordinary_container": {"path": str(OLD_MOD), "version": read_json(ARTIFACT / "发行包校验回执.json")["container_version"], "files": len(expected["SuQingContainerUpgrade"])},
              "lunchbox": {"path": str(NEW_BOX), "version": read_json(ARTIFACT / "发行包校验回执.json")["version"], "files": len(expected[BOX_ID])},
              "original_mod_count": len(ids(before)), "new_mod_count": len(ids(after)), "added_only": [BOX_ID],
              "original_order_preserved": True, "global_default_unchanged": True, "sandbox_unchanged": True,
              "world_other_file_metadata_unchanged": True, "retired_submod_installed": False,
              "previous_container_recovery": str(previous_container), "protected_changes": changes,
              "game_started": False, "in_game_tested": False, "published": False}
    save_json(task / "deployment.json", result)
    save_json(ARTIFACT / "deployment-task.json", {"task": str(task), "status": "deployed", "deployment": result})
    print(json.dumps(result, ensure_ascii=False), flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["backup", "strict-verify", "deploy"])
    parser.add_argument("--task", type=Path)
    parser.add_argument("--candidate-artifact", type=Path)
    arguments = parser.parse_args()
    if arguments.candidate_artifact:
        ARTIFACT = arguments.candidate_artifact.resolve(strict=True)
        assert ARTIFACT.parent == (GAME / "CodexAssets").resolve(strict=True) and ARTIFACT.name.startswith("SuQingFreshnessLunchbox_20261106")
        FROZEN = ARTIFACT / "release/mods"
    if arguments.command == "backup":
        backup()
    elif arguments.command == "strict-verify":
        assert arguments.task
        strict_verify(arguments.task)
    else:
        assert arguments.task, "An exact verified backup task is required"
        deploy(arguments.task)
