"""从 SWE-bench/swe-bench-tasks 拉取 10 题官方 eval 协议"""
import json, os, urllib.request, concurrent.futures

INSTANCES = [json.loads(l)["instance_id"] for l in open("data/instances.jsonl")]
BASE = "https://raw.githubusercontent.com/SWE-bench/swe-bench-tasks/main/tasks"
FILES = ["eval.sh", "tests.json", "task.yaml", "test.patch", "gold.patch"]

def fetch(args):
    iid, fn = args
    url = f"{BASE}/{iid}/{fn}"
    dst = f"data/task_specs/{iid}/{fn}"
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                data = r.read()
            open(dst, "wb").write(data)
            return iid, fn, len(data)
        except Exception as e:
            if attempt == 2:
                return iid, fn, f"FAIL {e}"

jobs = [(i, f) for i in INSTANCES for f in FILES]
with concurrent.futures.ThreadPoolExecutor(10) as ex:
    results = list(ex.map(fetch, jobs))
fails = [r for r in results if isinstance(r[2], str)]
print(f"fetched {len(results)-len(fails)}/{len(results)} files")
for f in fails: print(" ", f)
