"""Revalidate the selected ten environments, keeping per-test evidence."""
import argparse
import concurrent.futures
import json
from pathlib import Path

from sandbox.episode import atomic_json, evaluate_patch
from sandbox.harness import load_instances


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", required=True)
    ap.add_argument("--parallel", type=int, default=2)
    ap.add_argument("--instances", default="all")
    args = ap.parse_args()
    if not 1 <= args.parallel <= 4:
        ap.error("parallel must be between 1 and 4")
    root = Path(args.output)
    requested = None if args.instances == "all" else args.instances.split(",")
    instances = [i for i in load_instances(requested) if i.instance_id not in {
        "sympy__sympy-11384", "pylint-dev__pylint-4551"}]
    if not instances:
        ap.error("No selected candidates")

    def verify(inst):
        saved = root / inst.instance_id / "validation.json"
        if saved.exists():
            previous = json.loads(saved.read_text())
            if previous.get("status") in {"validated", "skipped"}:
                return previous
        results = {"baseline": [], "golden": []}
        for mode, patch in (("baseline", ""), ("golden", inst.gold_patch)):
            for repeat in range(2):
                result = evaluate_patch(inst, patch, root / inst.instance_id / mode / str(repeat),
                                        validation_gold=(mode == "golden"))
                results[mode].append(result)
                print(json.dumps({"instance_id": inst.instance_id, "mode": mode,
                                  "repeat": repeat, "reward": result["reward"],
                                  "resolved": result["resolved"]}), flush=True)
        bases = results["baseline"]
        golds = results["golden"]
        valid_base = all(not b["grade"]["f2p_passed"] and not b["grade"]["p2p_failed"] for b in bases)
        record = {"instance_id": inst.instance_id,
                  "status": "validated" if valid_base and all(g["resolved"] for g in golds) else "invalid",
                  "results": results}
        atomic_json(saved, record)
        return record

    def run(inst):
        try:
            return verify(inst)
        except RuntimeError as exc:
            if "cleanup" in str(exc).lower():
                raise
            record = {"instance_id": inst.instance_id, "status": "skipped",
                      "reason": str(exc), "evidence_directory": str(root / inst.instance_id)}
            atomic_json(root / inst.instance_id / "validation.json", record)
            print(json.dumps(record), flush=True)
            return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.parallel) as pool:
        results = list(pool.map(run, instances))
    report = {"total": len(results), "validated": sum(r["status"] == "validated" for r in results),
              "skipped": [r["instance_id"] for r in results if r["status"] != "validated"],
              "instances": results}
    report["ten_environment_gate"] = report["total"] == 10 and report["validated"] == 10
    atomic_json(root / ("summary.json" if args.instances == "all" else "subset-summary.json"), report)
    if report["validated"] != len(instances):
        raise SystemExit("Candidates failed validation; do not start acceptance training")


if __name__ == "__main__":
    main()
