"""Regression: full PZ module/model registration, including the frozen rc.6 failure."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[1]
MODEL = Path('42/media/scripts/models_FreshnessLunchbox_Attached.txt')
SOURCE = ROOT / 'mods/SuQingFreshnessLunchbox' / MODEL
LEGACY = (GAME / 'CodexAssets/SuQingFreshnessLunchbox_Attachments_20261107'
          / 'candidate-0.1.0-rc.6/mods/SuQingFreshnessLunchbox' / MODEL)
JAVAC = Path(r'E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javac.exe')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--legacy', type=Path, default=LEGACY)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'tests/model_registration_runtime')
    parser.add_argument('--report', type=Path, default=ROOT / 'tests/model_registration_validation.json')
    parser.add_argument('--javac', type=Path, default=JAVAC)
    args = parser.parse_args()
    inputs = {str(p): sha(p) for p in [args.source, args.legacy]}
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    classes = out / 'classes'
    classes.mkdir(exist_ok=True)
    logs = {}

    def run(name, command):
        result = subprocess.run([str(v) for v in command], cwd=GAME, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=60)
        text = result.stdout.decode('utf-8', errors='replace')
        (out / (name + '.log')).write_text(text, encoding='utf-8')
        logs[name] = str(out / (name + '.log'))
        if result.returncode:
            raise RuntimeError(f'{name} failed (exit {result.returncode}):\n{text}')
        return text

    run('javac', [args.javac, '-encoding', 'UTF-8', '-d', classes, ROOT / 'tools/model_registration_Probe.java'])
    cp = ';'.join(str(v) for v in [classes, GAME / 'pzopt/aot/pzopt.jar', GAME / 'projectzomboid.jar', GAME, GAME / '*'])
    cases = []
    for name, model, expected in [('legacy_rc6_unregistered', args.legacy, 'missing'),
                                   ('current_registered', args.source, 'registered')]:
        home = out / name
        home.mkdir(exist_ok=True)
        text = run(name, [GAME / 'jre64/bin/java.exe', '--enable-native-access=ALL-UNNAMED',
                         f'-Duser.home={home}', '-Djava.awt.headless=true', '-cp', cp,
                         'model_registration_Probe', model.resolve(), home / 'Zomboid', expected])
        record = json.loads(next(line.split(' ', 1)[1] for line in text.splitlines()
                                 if line.startswith('MODEL_REGISTRATION_RESULT ')))
        record.update(name=name, input=str(model.resolve()), sha256=sha(model))
        cases.append(record)
        print(f"PASS {name}: {record['checks']} assertions", flush=True)
    assert inputs == {path: sha(path) for path in inputs}, 'Input scripts changed during native regression'
    report = dict(result='PASS', checked_at_bjt=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  cases=cases, assertion_count=sum(c['checks'] for c in cases), input_hashes_unchanged=True,
                  method='Full file -> native stripComments -> ParseScript Init -> Base.models.LoadScripts -> ScriptManager.getModelScript / item-side resolveModelScript',
                  classpath=cp, logs=logs, game_started=False, world_created=False, gl_context=False,
                  limitation='Native registration and lookup only; no asset-render/animated-fit/gameplay acceptance')
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ['result', 'assertion_count', 'input_hashes_unchanged']}), flush=True)


if __name__ == '__main__':
    main()
