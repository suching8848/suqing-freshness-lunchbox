"""Validate and freeze a non-installing lunchbox candidate. Never starts the game."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
USER = Path(r"C:\Users\15792\Zomboid")
ARTIFACT = GAME / "CodexAssets/SuQingFreshnessLunchbox_20261106_rc5"
VALIDATION = ARTIFACT / "validation"
VERSION = "0.1.0-rc.5"
CONTAINER_VERSION = "1.0.3"
CONTAINER_REPO = Path(r"E:\code\suqing-container-upgrade")
CONTAINER = CONTAINER_REPO / "SuQingContainerUpgrade"
MOD_IDS = ["SuQingFreshnessLunchbox"]
RETIRED_ID = "SuQingFreshnessLunchbox_ContainerUpgrade"
JAVA = GAME / "jre64/bin/java.exe"
JDK = Path(r"E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64/bin")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def stamp():
    return datetime.now(timezone(timedelta(hours=8))).isoformat()

def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def manifest(folder):
    return {p.relative_to(folder).as_posix(): {"sha256": sha(p), "bytes": p.stat().st_size}
            for p in sorted(folder.rglob("*")) if p.is_file()}

def runtime_manifest():
    return {"SuQingFreshnessLunchbox": manifest(ROOT / "mods/SuQingFreshnessLunchbox"),
            "SuQingContainerUpgrade": manifest(CONTAINER)}

def run(label, command):
    result = subprocess.run([str(p) for p in command], cwd=GAME,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.decode("utf-8", errors="replace")
    (VALIDATION / (label + ".log")).write_text(output, encoding="utf-8")
    if result.returncode:
        raise AssertionError(label + " failed; see " + str(VALIDATION / (label + ".log")) + "\n" + output[-3500:])
    return output

def validate():
    VALIDATION.mkdir(parents=True, exist_ok=True)
    initial = runtime_manifest()
    checks = []
    def check(value, description):
        if not value:
            raise AssertionError(description)
        checks.append(description)

    # Independent component tools use separate test homes and helper filenames.
    components = {"runtime": "runtime_validate.py", "assets": "assets_validate.py", "integration": "integration_validate.py",
                  "preservation": "direct_upgrade_audit.py", "isa": "runtime_isa_validate.py"}
    with ThreadPoolExecutor(max_workers=3) as executor:
        jobs = {name: executor.submit(run, name, [sys.executable, ROOT / "tools" / entry] + (["--native"] if name == "assets" else []))
                for name, entry in components.items()}
        outputs = {name: job.result() for name, job in jobs.items()}
    for name, output in outputs.items():
        check("PASS" in output, name + " component passed")
    ex_output = run("ex_guard", [sys.executable, ROOT / "tools/integration_ex_guard_validate.py"])
    check("PASS report" in ex_output, "installed HavenFall EX crafting guard regression passed")

    helper = ROOT / "tools/ReleaseLuaCompile.java"
    check(helper.exists(), "installed Kahlua compile helper present")
    run("compile_helper", [JDK / "javac.exe", "-encoding", "UTF-8", helper])
    lua_files = sorted((ROOT / "mods").rglob("*.lua")) + sorted(CONTAINER.rglob("*.lua"))
    output = run("all_lua_compile", [JAVA, "-Duser.home=" + str(VALIDATION / "compile_home"),
                 "-cp", str(ROOT / "tools") + ";" + str(GAME / "projectzomboid.jar"), "ReleaseLuaCompile", *lua_files])
    check("LUA_COMPILE files=" + str(len(lua_files)) + " PASS" in output, "all shipped Lua compiles with current Kahlua")

    check({p.name for p in (ROOT / "mods").iterdir()} == {"SuQingFreshnessLunchbox"},
          "lunchbox project contains exactly one main mod and no compatibility submod")
    container_info = (CONTAINER / "42/mod.info").read_text(encoding="utf-8-sig")
    check(re.search(r"(?m)^id=SuQingContainerUpgrade_4221\s*$", container_info) is not None,
          "ordinary container Mod ID retained")
    check("modversion=" + CONTAINER_VERSION in container_info, "ordinary container candidate version")
    main_info = (ROOT / "mods/SuQingFreshnessLunchbox/42/mod.info").read_text(encoding="utf-8-sig")
    check(not re.search(r"(?m)^require=.*SuQingContainerUpgrade", main_info),
          "lunchbox can run without ordinary container upgrades")
    def after_ids(info):
        value = re.search(r"(?m)^loadModAfter=(.*)$", info)
        return {name.strip() for name in value.group(1).split(",")} if value else set()
    check(not ("SuQingFreshnessLunchbox" in after_ids(container_info)
               and "SuQingContainerUpgrade_4221" in after_ids(main_info)),
          "no loadModAfter cycle between the two main mods")
    check(not re.search(r"(?m)^require=.*SuQingFreshnessLunchbox", container_info),
          "ordinary container upgrades do not require the optional lunchbox provider")

    from PIL import Image
    translations = 0
    for mod_id in MOD_IDS:
        mod = ROOT / "mods" / mod_id / "42"
        info = (mod / "mod.info").read_text(encoding="utf-8-sig")
        check(re.search(r"(?m)^id=" + re.escape(mod_id) + r"\s*$", info) is not None, "exact ID " + mod_id)
        check("modversion=" + VERSION in info, "candidate version " + mod_id)
        check("namezh=" not in info, "native localized metadata used for " + mod_id)
        for name in ["poster.png", "icon.png"]:
            with Image.open(mod / name) as image:
                image.load()
                check(image.format == "PNG" and min(image.size) >= 128, "real readable PNG " + mod_id + "/" + name)
        folders = {lang: mod / "media/lua/shared/Translate" / lang for lang in ["CN", "EN", "CH"]}
        names = {lang: {p.name for p in folder.glob("*.json")} for lang, folder in folders.items()}
        check(names["CN"] == names["EN"] == names["CH"] and "Mod.json" in names["EN"], "translation file parity " + mod_id)
        for name in sorted(names["EN"]):
            texts = {lang: read_json(folder / name) for lang, folder in folders.items()}
            check(set(texts["CN"]) == set(texts["EN"]) == set(texts["CH"]), "translation key parity " + mod_id + "/" + name)
            for key, value in texts["EN"].items():
                check(all(sorted(re.findall(r"%\d+", texts[lang][key])) == sorted(re.findall(r"%\d+", value))
                          for lang in ["CN", "CH"]), "placeholder parity " + mod_id + "/" + name + "/" + key)
            translations += len(texts["EN"])

    main = ROOT / "mods/SuQingFreshnessLunchbox/42"
    with Image.open(main / "media/textures/Item_SuQingFreshnessLunchbox.png") as item_icon:
        check(item_icon.mode == "RGBA" and item_icon.getextrema()[-1][0] == 0, "item icon preserves genuine transparency")
    check(sha(main / "icon.png") != sha(main / "poster.png"), "small icon is not the poster asset")
    sandbox = (main / "media/sandbox-options.txt").read_text(encoding="utf-8-sig")
    capacity = sandbox.split("option SuQingFreshnessLunchbox.BaseCapacity", 1)[1].split("}", 1)[0]
    check(all(re.search(r"\b" + key + r"\s*=\s*" + value + r"\b", capacity)
              for key, value in [("default", "4"), ("min", "1"), ("max", "30")]), "base capacity 4 / range 1–30")

    installed = USER / "mods/SuQingFreshnessLunchbox"
    old_frozen = GAME / "CodexAssets/SuQingFreshnessLunchbox_20261106_rc3_CU103/release/mods/SuQingFreshnessLunchbox"
    check(manifest(installed) == manifest(old_frozen), "currently installed rc3 remains unchanged before verified hotfix")
    save_ids = re.findall(r"(?m)^\s*mod\s*=\s*([^,\r\n]+),", (USER / "Saves/Sandbox/2026-10-09_18-19-22/mods.txt").read_text(encoding="utf-8-sig"))
    check(save_ids.count("SuQingFreshnessLunchbox") == 1, "target save already enables exactly one lunchbox main mod")
    check("SuQingFreshnessLunchbox" not in (USER / "mods/default.txt").read_text(encoding="utf-8-sig"),
          "global new-save defaults retain their intentional difference")
    local_ids = {}
    for info_file in (USER / "mods").rglob("mod.info"):
        match = re.search(r"(?m)^id=([^\r\n]+)", info_file.read_text(encoding="utf-8-sig", errors="replace"))
        if match:
            local_ids.setdefault(match.group(1).strip(), []).append(str(info_file))
    check(len(local_ids.get("SuQingFreshnessLunchbox", [])) == 1 and RETIRED_ID not in local_ids,
          "one existing lunchbox source and no retired submod, regardless of folder name")
    check(not (USER / "mods" / RETIRED_ID).exists(), "retired submod has never been deployed")
    for file in [USER / "mods/default.txt", USER / "Saves/Sandbox/2026-10-09_18-19-22/mods.txt"]:
        check(RETIRED_ID not in file.read_text(encoding="utf-8-sig"), "retired submod absent from enable lists")
    before = read_json(ARTIFACT / "protected-before.json")["files"]
    after = {p: sha(Path(p)) for p in before if Path(p).is_file()}
    save(VALIDATION / "protected-after.json", {"checkedAt": stamp(), "files": after})
    changed_protected = [p for p in before if before[p] != after.get(p)]
    # A separate game run occurred during source development. Retain the original
    # snapshot and record reviewed mutable-profile drift without restoring it.
    reviewed_path = ARTIFACT / "reviewed-profile-drift.json"
    reviewed = read_json(reviewed_path) if reviewed_path.exists() else {"files": {}}
    expected_drift = reviewed["files"]
    check(set(changed_protected) == set(expected_drift)
          and all(after.get(path) == expected_drift[path]["observed_sha256"] for path in changed_protected),
          "protected hashes match the original snapshot or exact reviewed concurrent profile changes")
    check(initial == runtime_manifest(), "both main-mod sources stayed stable during aggregate validation")
    reports = {
        "runtime": read_json(ROOT / "tests/runtime_validation.json"),
        "assets": read_json(ROOT / "art/model/asset_validation.json"),
        "integration": read_json(ROOT / "tests/integration_validation.json"),
        "preservation": read_json(ROOT / "tests/direct_upgrade_audit.json"),
        "ex_guard": read_json(ROOT / "tests/integration_ex_guard_validation.json"),
        "isa": read_json(ROOT / "tests/runtime_isa_validation.json"),
    }
    for name, report in reports.items():
        check(report.get("result") == "PASS", name + " structured report passed")
    result = {"result": "PASS", "checkedAt": stamp(), "version": VERSION, "checks": checks,
              "lua_files": len(lua_files), "translation_keys": translations, "reports": reports,
              "source_manifest": runtime_manifest(), "container_version": CONTAINER_VERSION,
              "personal_container_locations": local_ids.get("SuQingContainerUpgrade_4221", []),
              "protected_file_count": len(before),
              "protected_unchanged_count": len(before) - len(changed_protected),
              "concurrent_profile_changes": reviewed,
              "installed": False, "enabled": False, "game_started": False, "in_game_tested": False,
              "git_committed": False, "workshop_published": False}
    save(VALIDATION / "offline-validation.json", result)
    print(json.dumps({"result": "PASS", "checks": len(checks), "lua_files": len(lua_files),
                      "translation_keys": translations,
                      "runtime_files": sum(len(files) for files in result["source_manifest"].values()),
                      "protected_file_count": len(before), "installed": False}, ensure_ascii=False))

def package():
    report = read_json(VALIDATION / "offline-validation.json")
    if report["result"] != "PASS" or report["source_manifest"] != runtime_manifest():
        raise AssertionError("Validate the unchanged current runtime before freezing")
    frozen = ARTIFACT / "release"
    archive = ARTIFACT / ("返鲜餐盒_" + VERSION + "_容器升级_" + CONTAINER_VERSION + "_内置兼容测试包.zip")
    receipt_path = ARTIFACT / "发行包校验回执.json"
    if frozen.exists() or archive.exists() or receipt_path.exists():
        raise AssertionError("Refuse to overwrite an existing frozen candidate")
    frozen.mkdir()
    shutil.copytree(ROOT / "mods", frozen / "mods")
    shutil.copytree(CONTAINER, frozen / "mods/SuQingContainerUpgrade")
    frozen_manifest = {name: manifest(frozen / "mods" / name) for name in report["source_manifest"]}
    if frozen_manifest != report["source_manifest"]:
        raise AssertionError("Frozen runtime does not match the validated source")
    if {p.name for p in (frozen / "mods").iterdir()} != {"SuQingFreshnessLunchbox", "SuQingContainerUpgrade"}:
        raise AssertionError("Expected exactly the two main mods")
    for source, name in [(ROOT / "README.md", "使用说明.md"), (ROOT / "README.en.md", "README.en.md"),
                         (ARTIFACT / "集中验收清单.txt", "集中验收清单.txt"),
                         (VALIDATION / "offline-validation.json", "离线验证结果.json")]:
        shutil.copy2(source, frozen / name)
    shutil.copy2(CONTAINER / "README.txt", frozen / "容器升级说明_CN_EN.txt")
    files = manifest(frozen)
    save(frozen / "文件校验.json", files)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for path in sorted(frozen.rglob("*")):
            if path.is_file():
                output.write(path, path.relative_to(frozen).as_posix())
    with zipfile.ZipFile(archive) as check:
        if check.testzip() is not None:
            raise AssertionError("Archive CRC failed")
        current = manifest(frozen)
        if set(check.namelist()) != set(current):
            raise AssertionError("Archive membership mismatch")
        for name, item in current.items():
            if hashlib.sha256(check.read(name)).hexdigest() != item["sha256"]:
                raise AssertionError("Archive readback mismatch: " + name)
    receipt = {"version": VERSION, "container_version": CONTAINER_VERSION, "createdAt": stamp(), "archive": str(archive), "sha256": sha(archive),
               "bytes": archive.stat().st_size, "verified_members": len(current), "source": str(ROOT),
               "frozen": str(frozen), "container_source": str(CONTAINER_REPO),
               "retired_submod_included": False, "installed": False, "enabled": False, "in_game_tested": False,
               "backup_created": False, "existing_profile_modified_by_this_task": False,
               "concurrent_profile_changes": report.get("concurrent_profile_changes", {})}
    save(receipt_path, receipt)
    print(json.dumps(receipt, ensure_ascii=False))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["validate", "package"])
    action = parser.parse_args().command
    VALIDATION.mkdir(parents=True, exist_ok=True)
    {"validate": validate, "package": package}[action]()
