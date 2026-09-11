"""从 princeton-nlp/SWE-bench 提取 10 题元数据 → instances.jsonl"""
import json, os
from datasets import load_dataset

# TCR tag → instance_id 映射（tag 格式: <org>_1776_<repo>-<num>）
TCR = "tcr.example.com"
TAGS = [
    "astropy_1776_astropy-12057", "django_1776_django-10939", "django_1776_django-11039",
    "matplotlib_1776_matplotlib-13859", "psf_1776_requests-1327", "pylint-dev_1776_pylint-4551",
    "scikit-learn_1776_scikit-learn-10198", "sphinx-doc_1776_sphinx-10021",
    "sympy_1776_sympy-11232", "sympy_1776_sympy-11384",
]
def tag_to_id(tag):
    # django_1776_django-10939 → django__django-10939
    org, rest = tag.split("_1776_", 1)
    return f"{org}__{rest}"

want = {tag_to_id(t): t for t in TAGS}
ds = load_dataset("princeton-nlp/SWE-bench", split="test")
out, seen = [], set()
for r in ds:
    iid = r["instance_id"]
    if iid not in want or iid in seen:
        continue
    seen.add(iid)
    tag = want[iid]
    rec = {
        "instance_id": iid,
        "repo": r["repo"],
        "base_commit": r["base_commit"],
        "patch": r["patch"],                 # golden patch（标准答案）
        "test_patch": r["test_patch"],
        "FAIL_TO_PASS": json.loads(r["FAIL_TO_PASS"]),
        "PASS_TO_PASS": json.loads(r["PASS_TO_PASS"]),
        "problem_statement": r["problem_statement"],
        "hints_text": r.get("hints_text", ""),
        "version": r.get("version", ""),
        "environment_setup_commit": r.get("environment_setup_commit", ""),
        "image_ags": f"{TCR}/swe-mirror/swe-ags:{tag}",
        "image_env": f"{TCR}/swe-mirror/swe-env:{tag}",
        "tool_name": "swe-" + tag.split("_1776_", 1)[1],   # AGS 沙箱工具名（控制台创建）
    }
    out.append(rec)

missing = set(want) - seen
assert not missing, f"missing: {missing}"
with open(os.path.join(os.path.dirname(__file__), "instances.jsonl"), "w") as f:
    for r in out:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print(f"wrote {len(out)} instances")
for r in out:
    print(f"  {r['instance_id']}: F2P={len(r['FAIL_TO_PASS'])} P2P={len(r['PASS_TO_PASS'])} tool={r['tool_name']}")
