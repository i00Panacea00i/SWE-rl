"""Bounded, read-only Pod monitoring with durable logs and a 30-second interval."""
import argparse
import json
import re
import subprocess
import time
from pathlib import Path


ERROR = re.compile(r"Traceback \(most recent call last\)|Error executing job|OutOfMemoryError|OOMKilled")


def kubectl(*args):
    result = subprocess.run(["kubectl", "--request-timeout=20s", *args],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pod", required=True)
    ap.add_argument("--minutes", type=int, default=10)
    ap.add_argument("--output", default="artifacts/monitor")
    args = ap.parse_args()
    output = Path(args.output) / args.pod
    output.mkdir(parents=True, exist_ok=True)
    stop = time.monotonic() + args.minutes * 60
    while time.monotonic() < stop:
        status = json.loads(kubectl("get", "pod", args.pod, "-o", "json"))
        phase = status["status"]["phase"]
        log = kubectl("logs", args.pod, "--timestamps", "--tail=400")
        clean = re.sub(r"\x1b\[[0-9;]*m", "", log).replace("\r", "\n")
        lines = [line for line in clean.splitlines() if line.strip()]
        states = status["status"].get("containerStatuses", [])
        print(time.strftime("%H:%M:%S"), phase, lines[-1][-280:] if lines else "no log", flush=True)
        snapshot = {"time": time.time(), "phase": phase,
                    "containers": [{"name": s["name"], "state": s.get("state")} for s in states]}
        with (output / "states.jsonl").open("a") as f:
            f.write(json.dumps(snapshot) + "\n")
        if ERROR.search(clean) or phase in {"Succeeded", "Failed"}:
            full = kubectl("logs", args.pod, "--timestamps")
            (output / "pod.log").write_text(full)
            (output / "final-state.json").write_text(json.dumps(snapshot, indent=2))
            errors = ERROR.findall(full)
            print("\n".join(full.splitlines()[-20:])[-7000:], flush=True)
            print(json.dumps(snapshot), flush=True)
            if errors or phase == "Failed":
                raise SystemExit(1)
            return
        time.sleep(30)
    (output / "pod.log").write_text(kubectl("logs", args.pod, "--timestamps"))
    print("Monitoring window ended; Pod still active. No completion claimed.", flush=True)


if __name__ == "__main__":
    main()
