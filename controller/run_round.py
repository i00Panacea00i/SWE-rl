"""Execute an explicit bounded Pod plan, preserving evidence and stopping on errors."""
import argparse
import json
import re
import subprocess
import time
from pathlib import Path

ERROR = re.compile(r'Traceback \(most recent call last\)|Error executing job|OutOfMemoryError|OOMKilled')


def kubectl(*args, check=True):
    result = subprocess.run(['kubectl', '--request-timeout=25s', *args],
                            capture_output=True, text=True, timeout=40)
    if check and result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--plan', required=True)
    args = ap.parse_args()
    plan_path = Path(args.plan).resolve()
    plan = json.loads(plan_path.read_text())
    output = plan_path.parent / 'pipeline'
    output.mkdir(parents=True, exist_ok=False)
    for stage in plan['stages']:
        name = stage['pod']
        if not name.startswith('swe-rl-'):
            raise ValueError('Unexpected Pod name')
        existing = kubectl('get', 'pod', name, '--ignore-not-found', '-o', 'json').stdout.strip()
        if not existing:
            manifest = (plan_path.parent / stage['manifest']).resolve()
            kubectl('create', '-f', str(manifest))
        deadline = time.monotonic() + stage['timeout_seconds']
        path = output / name
        path.mkdir()
        while True:
            pod = json.loads(kubectl('get', 'pod', name, '-o', 'json').stdout)
            phase = pod['status']['phase']
            state = {'name': name, 'phase': phase, 'time': time.time(),
                     'containers': [s.get('state') for s in pod['status'].get('containerStatuses', [])]}
            (path / 'state.json').write_text(json.dumps(state, indent=2))
            log_result = kubectl('logs', name, '--tail=500', check=False)
            log = log_result.stdout
            fatal = ERROR.search(log)
            expired = time.monotonic() >= deadline
            print(json.dumps(state), flush=True)
            if phase in ('Succeeded', 'Failed') or fatal or expired:
                full = kubectl('logs', name, check=False)
                (path / 'pod.log').write_text(full.stdout + full.stderr)
                if phase != 'Succeeded' or fatal or expired:
                    if phase not in ('Succeeded', 'Failed'):
                        kubectl('delete', 'pod', name, '--wait=false')
                    reason = {'stage': name, 'status': 'stopped', 'phase': phase,
                              'fatal_log': bool(fatal), 'deadline_exceeded': expired}
                    (output / 'result.json').write_text(json.dumps(reason, indent=2))
                    raise SystemExit('Pipeline stopped; evidence preserved at ' + str(path))
                break
            time.sleep(30)
    (output / 'result.json').write_text(json.dumps({'status': 'all_stages_completed',
                                                  'time': time.time()}, indent=2))
    print('All planned stages completed; inspect evidence for measured improvement.', flush=True)


if __name__ == '__main__':
    main()
