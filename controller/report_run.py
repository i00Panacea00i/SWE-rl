"""Validate real rollout evidence; fail closed before advancing an unattended round."""
import argparse
import json
import math
import re
import statistics
from collections import defaultdict
from pathlib import Path


def summarize(root, manifest, mode):
    rows = []
    failures = []
    allowed = set(manifest['train'] if mode in ('pilot', 'train') else manifest['eval'])
    for path in sorted(root.rglob('episode.json')):
        episode = json.loads(path.read_text())
        if episode.get('error'):
            failures.append(str(path) + ': ' + str(episode['error']))
        if mode == 'train' and episode.get('phase') != 'train':
            continue
        if episode['instance_id'] not in allowed:
            failures.append(str(path) + ': wrong dataset partition')
        final = episode.get('final')
        alignment = episode.get('token_alignment', {})
        ids, mask = alignment.get('response_ids', []), alignment.get('response_mask', [])
        probs = alignment.get('response_logprobs') or []
        if not final or not ids or len(ids) != len(mask) or (probs and len(probs) != len(ids)):
            failures.append(str(path) + ': incomplete result or token alignment')
            continue
        if not all(v in (0, 1) for v in mask) or not any(mask):
            failures.append(str(path) + ': invalid response mask')
        steps = episode['steps']
        if (not steps or not steps[-1].get('done') or
                any(not all(k in s for k in ('action', 'observation', 'reward', 'done')) for s in steps)):
            failures.append(str(path) + ': invalid transition schema')
        if episode.get('shell_operations', 0) < 3:
            failures.append(str(path) + ': fewer than three shell operations')
        reward = float(final['reward'])
        if not math.isfinite(reward) or not 0 <= reward <= 1:
            failures.append(str(path) + ': invalid reward')
        rows.append({'instance_id': episode['instance_id'], 'step': episode['global_step'],
                     'reward': reward, 'resolved': bool(final['resolved'])})
    groups = defaultdict(list)
    for row in rows:
        groups[(row['step'], row['instance_id'])].append(row['reward'])
    informative = sum(len(values) >= 2 and statistics.pvariance(values) > 0
                      for values in groups.values())
    return {'episodes': len(rows), 'instances': sorted({r['instance_id'] for r in rows}),
            'mean_reward': statistics.mean(r['reward'] for r in rows) if rows else None,
            'resolved_rate': statistics.mean(r['resolved'] for r in rows) if rows else None,
            'informative_groups': informative, 'max_step': max((r['step'] for r in rows), default=-1),
            'failures': failures, 'rows': rows}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--traces', required=True)
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--mode', choices=['pilot', 'baseline', 'train', 'after'], required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--expected', type=int)
    ap.add_argument('--require-signal', action='store_true')
    ap.add_argument('--min-step', type=int)
    ap.add_argument('--checkpoint-dir')
    ap.add_argument('--log-dir')
    ap.add_argument('--baseline-report')
    args = ap.parse_args()
    result = summarize(Path(args.traces), json.loads(Path(args.manifest).read_text()), args.mode)
    if args.expected is not None and result['episodes'] != args.expected:
        result['failures'].append(f"Expected {args.expected} episodes, got {result['episodes']}")
    if args.require_signal and not result['informative_groups']:
        result['failures'].append('No within-prompt reward variation; do not start a long zero-signal run')
    if args.min_step is not None and result['max_step'] < args.min_step:
        result['failures'].append('Required training step not reached')
    if args.checkpoint_dir:
        path = Path(args.checkpoint_dir) / 'latest_checkpointed_iteration.txt'
        checkpoint_step = int(path.read_text().strip()) if path.is_file() else -1
        result['checkpoint_step'] = checkpoint_step
        if checkpoint_step < (args.min_step or 1):
            result['failures'].append('Required checkpoint was not saved')
    if args.log_dir:
        text = '\n'.join(p.read_text(errors='replace') for p in Path(args.log_dir).glob('train-*.log'))
        gradients = [float(v) for v in re.findall(r'actor/grad_norm:([-+\d.eE]+)', text)]
        result['nonzero_gradient_steps'] = sum(math.isfinite(v) and v > 0 for v in gradients)
        if args.require_signal and not result['nonzero_gradient_steps']:
            result['failures'].append('No recorded nonzero actor gradient')
    if args.baseline_report:
        baseline = json.loads(Path(args.baseline_report).read_text())
        if not baseline['passed'] or baseline['instances'] != result['instances']:
            result['failures'].append('Baseline is invalid or uses a different evaluation set')
        elif result['resolved_rate'] is not None:
            result['pass_at_1_before'] = baseline['resolved_rate']
            result['pass_at_1_after'] = result['resolved_rate']
            result['pass_at_1_delta'] = result['resolved_rate'] - baseline['resolved_rate']
            result['observed_improvement'] = result['pass_at_1_delta'] > 0
    result['mode'] = args.mode
    result['passed'] = bool(result['episodes']) and not result['failures']
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2))
    print('RUN_SUMMARY ' + json.dumps({k: v for k, v in result.items() if k != 'rows'}), flush=True)
    if not result['passed']:
        raise SystemExit(2)


if __name__ == '__main__':
    main()
