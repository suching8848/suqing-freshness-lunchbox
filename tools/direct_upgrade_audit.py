"""Read-only comparison of direct lunchbox support against the clean container baseline."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPO = Path(r"E:\code\suqing-container-upgrade")
BASE = "fbe52f89ceeee5769098a1e293cbece5952cc142"
NEW = "SuQingFreshnessLunchbox.FreshnessLunchbox"
PREFIX = "SuQingContainerUpgrade/"
checks = []

def check(value, message):
    if not value:
        raise AssertionError(message)
    checks.append(message)

def before(path):
    return subprocess.check_output(["git", "-C", str(REPO), "show", BASE + ":" + path]).decode("utf-8-sig").replace("\r\n", "\n")

def current(path):
    return (REPO / path).read_text(encoding="utf-8-sig").replace("\r\n", "\n")

registry = PREFIX + "compatibility/registry.json"
old = json.loads(before(registry))
new = json.loads(current(registry))
old_items = {item["fullType"]: item for item in old["items"]}
new_items = {item["fullType"]: item for item in new["items"]}
check(set(new_items) - set(old_items) == {NEW}, "exactly one new registry item")
check(set(old_items) <= set(new_items), "all previous registry items retained")
check(all(new_items[key] == value for key, value in old_items.items()), "all 191 previous registry rows unchanged")
check(new_items[NEW]["profile"] == "mod_container", "new lunchbox uses the ordinary mod-container profile")

core = PREFIX + "42/media/lua/shared/SuQingContainerUpgrade/Core.lua"
normalize_version = lambda text: re.sub(r'C\.version = "[^"]+"', 'C.version = "VERSION"', text)
check(normalize_version(before(core)) == normalize_version(current(core)), "ordinary core behavior unchanged apart from version")
recipes = PREFIX + "42/media/scripts/SuQingContainerUpgrade.txt"
recipe_text = current(recipes)
check(recipe_text.count(NEW) == 6, "all five native upgrade recipes and restore contain one lunchbox input")
without_new = recipe_text.replace(";" + NEW, "").replace(NEW + ";", "")
check(without_new == before(recipes), "all existing recipe inputs, costs, flags and callbacks unchanged")
compatibility = PREFIX + "42/media/lua/shared/SuQingContainerUpgrade/Compatibility.lua"
def normalize_registry(text):
    text = "\n".join(line for line in text.splitlines() if NEW not in line) + "\n"
    return re.sub(r'registrySha256 = "[^"]+"', 'registrySha256 = "HASH"', text)
check(normalize_registry(before(compatibility)) == normalize_registry(current(compatibility)),
      "generated compatibility adds only lunchbox support/profile plus registry digest")

runtime_prefix = PREFIX + "42/media/lua/"
tracked = subprocess.check_output(["git", "-C", str(REPO), "ls-tree", "-r", "--name-only", BASE, runtime_prefix]).decode().splitlines()
for path in tracked:
    if path not in {core, compatibility}:
        check(before(path) == current(path), "existing Lua/localization preserved: " + path.removeprefix(runtime_prefix))
check({p.name for p in (ROOT / "mods").iterdir()} == {"SuQingFreshnessLunchbox"}, "no independent compatibility submod in current source")
previous_release = ROOT.parents[1] / "CodexAssets/SuQingFreshnessLunchbox_20261106_rc3_CU103"
receipt = json.loads((previous_release / "发行包校验回执.json").read_text(encoding="utf-8"))
archive = Path(receipt["archive"])
check(hashlib.sha256(archive.read_bytes()).hexdigest() == receipt["sha256"], "historical rc3 deployment archive still matches its receipt")
main = ROOT / "mods/SuQingFreshnessLunchbox"
prefix = "mods/SuQingFreshnessLunchbox/"
allowed_changes = {"42/mod.info", "42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua"}
allowed_changes.update({"42/media/lua/client/SuQingFreshnessLunchbox_Runtime.lua",
                        "42/media/lua/client/SuQingFreshnessLunchbox_UI.lua",
                        "42/media/textures/Item_SuQingFreshnessLunchbox.png"})
allowed_changes.update("42/media/lua/shared/Translate/" + lang + "/" + category for lang in ["CN", "EN", "CH"]
                       for category in ["Mod.json", "IG_UI.json"])
with zipfile.ZipFile(archive) as previous:
    prior_names = {name.removeprefix(prefix) for name in previous.namelist() if name.startswith(prefix)}
    current_names = {path.relative_to(main).as_posix() for path in main.rglob("*") if path.is_file()}
    check(current_names - prior_names == {"42/media/fileGuidTable.xml"} and prior_names <= current_names,
          "only new runtime resource is the required clothing GUID table")
    for name in prior_names - allowed_changes:
        check(previous.read(prefix + name) == (main / name).read_bytes(), "lunchbox runtime/assets preserved: " + name)
    name = "42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua"
    prior_core = previous.read(prefix + name).decode("utf-8-sig").replace("\r\n", "\n")
    current_core = (main / name).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    for function in ["C.Config", "C.Coverage", "C.SettleFood"]:
        def body(text):
            tail = text.split("function " + function + "(", 1)[1]
            return re.split(r"\n(?:local )?function |\nreturn C", tail, maxsplit=1)[0]
        check(body(prior_core) == body(current_core), "freshness settings/age calculation preserved: " + function)
    crafting_name = "42/media/lua/client/SuQingFreshnessLunchbox_Crafting.lua"
    old_crafting = previous.read(prefix + crafting_name).decode("utf-8-sig").replace("\r\n", "\n")
    new_crafting = (main / crafting_name).read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    check(old_crafting == new_crafting, "existing EX crafting preflight compatibility preserved")
    ordinary_prefix = "mods/SuQingContainerUpgrade/"
    for name in previous.namelist():
        if name.startswith(ordinary_prefix):
            check(previous.read(name) == (REPO / "SuQingContainerUpgrade" / name.removeprefix(ordinary_prefix)).read_bytes(),
                  "ordinary1.0.3 source retained: " + name.removeprefix(ordinary_prefix))
subprocess.run(["python", str(REPO / PREFIX / "tools/build_compatibility.py"), "--check"], check=True)
check(True, "registry generator reproduces every generated file")

head = subprocess.check_output(["git", "-C", str(REPO), "rev-parse", "HEAD"]).decode().strip()
check(head == BASE, "no Git commit created")
patch = subprocess.check_output(["git", "-C", str(REPO), "diff", "--binary", BASE], stderr=subprocess.PIPE)
artifact = ROOT.parents[1] / "CodexAssets/SuQingFreshnessLunchbox_20261106_rc4"
(artifact / "container-source-changes.patch").write_bytes(patch)
report = {"result": "PASS", "checked_at": datetime.now(timezone.utc).isoformat(), "checks": checks,
          "baseline_commit": BASE, "new_item": NEW, "existing_rows_preserved": len(old_items),
          "patch_sha256": hashlib.sha256(patch).hexdigest(), "source_only": True,
          "installed": False, "game_started": False}
(ROOT / "tests/direct_upgrade_audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"result": "PASS", "checks": len(checks), "existing_rows_preserved": len(old_items)}))
