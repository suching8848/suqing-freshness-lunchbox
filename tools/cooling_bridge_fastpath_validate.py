"""Run the real Lua cooling bridge in standalone Kahlua; never start a game/world.

Creates a unique results directory per invocation, preserving earlier reports.
Optional --reference-core runs the same behavior cases and records old-path counts.
"""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CORE = ROOT / "mods/SuQingFreshnessLunchbox/42/media/lua/shared/SuQingFreshnessLunchbox/Core.lua"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=ROOT.parents[1])
    parser.add_argument("--javac", type=Path)
    parser.add_argument("--core", type=Path, default=DEFAULT_CORE)
    parser.add_argument("--reference-core", type=Path)
    args = parser.parse_args()
    game = args.game.resolve()
    core = args.core.resolve()
    java = game / "jre64/bin/java.exe"
    jar = game / "projectzomboid.jar"
    javac = args.javac
    if javac is None and shutil.which("javac"):
        javac = Path(shutil.which("javac"))
    if javac is None:
        candidates = sorted(Path("E:/code").glob("java*/bin/javac.exe"))
        javac = candidates[0] if candidates else None
    if not javac or not javac.is_file() or not java.is_file() or not jar.is_file() or not core.is_file():
        raise RuntimeError("Existing game JAR/runtime, Core.lua, and javac are required")
    if args.reference_core and not args.reference_core.is_file():
        raise RuntimeError("Reference Core.lua does not exist")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    output = ROOT / "tests/results" / ("cooling_bridge_fastpath_" + stamp)
    output.mkdir(parents=True, exist_ok=False)
    classes = output / "classes"
    classes.mkdir()
    home = output / "isolated_home"
    home.mkdir()
    environment = os.environ.copy()
    environment["USERPROFILE"] = str(home)
    environment["APPDATA"] = str(home / "AppData/Roaming")
    environment["LOCALAPPDATA"] = str(home / "AppData/Local")
    report = {"result": "FAIL", "checked_utc": datetime.now(timezone.utc).isoformat(),
              "game_started": False, "world_created": False, "world_loaded": False,
              "user_save_read": False, "in_game_tested": False, "results": str(output),
              "game_jar": str(jar), "game_jar_sha256": sha256(jar),
              "core": str(core), "core_sha256": sha256(core)}

    def execute(label, command):
        result = subprocess.run([str(value) for value in command], cwd=game, env=environment,
                                capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        content = result.stdout + result.stderr
        (output / (label + ".log")).write_text(content, encoding="utf-8")
        if result.returncode:
            raise RuntimeError(f"{label} failed; see {output / (label + '.log')}\n{content[-7000:]}")
        return content

    try:
        source = ROOT / "tools/runtime_KahluaAudit.java"
        execute("javac", [javac, "-encoding", "UTF-8", "-d", classes, source])
        classpath = os.pathsep.join(map(str, (classes, game, jar, game / "*")))
        cases = ROOT / "tests/cooling_bridge_fastpath_cases.lua"

        def run(label, target, expected):
            setup = output / (label + "_mode.lua")
            setup.write_text("EXPECT_FASTPATH=" + ("true" if expected else "false") + "\n", encoding="utf-8")
            content = execute(label, [java, "-Duser.home=" + str(home), "-cp", classpath,
                                      "runtime_KahluaAudit", setup, target, cases])
            summary = re.search(r"COOLING_BRIDGE_FASTPATH cases=(\d+) assertions=(\d+) PASS", content)
            metrics = re.search(r"COOLING_BRIDGE_METRICS ([^\r\n]+)", content)
            if summary is None or metrics is None:
                raise RuntimeError(f"{label} did not produce a complete PASS summary")
            return {"core": str(target), "core_sha256": sha256(target), "cases": int(summary[1]),
                    "assertions": int(summary[2]),
                    "ordinary_1000_calls": {key: int(value) for key, value in
                                            re.findall(r"(\w+)=(\d+)", metrics[1])}}

        report["candidate"] = run("candidate", core, True)
        if args.reference_core:
            report["reference"] = run("reference", args.reference_core.resolve(), False)
        report["limits"] = ["Method-level mocked ownership and hook-chain behavior only.",
                            "Operation counts are not an in-game frame-rate prediction.",
                            "User must perform in-game save, interaction and performance acceptance."]
        report["result"] = "PASS"
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
