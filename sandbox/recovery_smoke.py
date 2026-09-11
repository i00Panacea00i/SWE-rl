"""Bounded real-AGS regression; gold patches are used only by the trusted judge."""
import argparse
import json
from pathlib import Path

from sandbox.episode import EpisodeSession, evaluate_patch
from sandbox.harness import load_instances


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', required=True)
    args = ap.parse_args()
    root = Path(args.output)
    root.mkdir(parents=True, exist_ok=False)
    summary = []
    for iid in ('psf__requests-1327', 'django__django-12286'):
        inst = load_instances([iid])[0]
        baseline = evaluate_patch(inst, '', root / iid / 'baseline', timeout=300)
        golden = evaluate_patch(inst, inst.gold_patch, root / iid / 'golden', timeout=300,
                                validation_gold=True)
        assert baseline['reward'] == 0 and not baseline['resolved'], iid
        assert golden['reward'] == 1 and golden['resolved'], iid
        summary.append({'instance_id': iid, 'baseline': baseline['reward'], 'golden': golden['reward']})
    inst = load_instances(['psf__requests-1327'])[0]
    session = EpisodeSession(inst, root / 'export-stream', apply_test_patch=True)
    try:
        session.start()
        assert not session.export_patch().strip(), 'Preloaded tests leaked into patch'
        rc, output, _ = session.run("python -c \"print('x'*200000)\"; echo STREAM_FINISHED", 30)
        assert rc == 0 and 'STREAM_FINISHED' in output and 'truncated' in output
        rc, output, _ = session.run("echo forbidden > /tmp/partial; cat <<EOF\nunfinished", 30)
        assert rc == 2 and 'not executed' in output
        rc, _, _ = session.run("test ! -e /tmp/partial", 30)
        assert rc == 0, 'An incomplete script had side effects'
        rc, _, _ = session.run("printf '\ndef broken(:\n' >> requests/sessions.py", 30)
        assert rc == 0
        candidate = session.export_patch()
        assert 'requests/sessions.py' in candidate and 'test_requests.py' not in candidate
    finally:
        session.close()
    invalid = evaluate_patch(inst, candidate, root / 'syntax-candidate', timeout=300)
    assert invalid['reward'] == 0 and invalid['failure_kind'] == 'candidate_collection_or_import_error'
    summary.append({'stream_and_export': 'passed', 'candidate_error_reward': invalid['reward'],
                    'baseline_control': 'passed'})
    (root / 'summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    main()
