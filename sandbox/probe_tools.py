"""探测 AGS 沙箱工具与 TCR 镜像就绪状态（控制台创建工具后运行本脚本确认）。

用法：
  set -a && source .env && set +a
  venv/bin/python sandbox/probe_tools.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import load_instances  # noqa: E402

from e2b_code_interpreter import Sandbox  # noqa: E402


def check_tcr_tag(image: str) -> bool:
    """TCR 企业版 manifest 检查：先取 Bearer token 再查 tag（basic auth 直查会 401）"""
    import base64
    import urllib.parse
    import urllib.request
    cfg = Path.home() / ".docker/config.json"
    if not cfg.exists():
        return False
    auths = json.loads(cfg.read_text())["auths"]
    basic = ""
    for host in auths:
        basic = base64.b64decode(auths[host]["auth"]).decode()
        break
    registry = image.split("/")[0]
    repo, tag = ("/".join(image.split("/")[1:])).rsplit(":", 1)
    scope = urllib.parse.quote(f"repository:{repo}:pull")
    tok_req = urllib.request.Request(
        f"https://{registry}/service/token?service=harbor-registry&scope={scope}",
        headers={"Authorization": "Basic " + base64.b64encode(basic.encode()).decode()})
    try:
        with urllib.request.urlopen(tok_req, timeout=15) as r:
            token = json.loads(r.read())["token"]
    except Exception:
        return False
    req = urllib.request.Request(
        f"https://{registry}/v2/{repo}/manifests/{tag}",
        headers={"Authorization": "Bearer " + token,
                 "Accept": "application/vnd.docker.distribution.manifest.v2+json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status == 200
    except Exception:
        return False


def main():
    insts = load_instances()
    print(f"探测 {len(insts)} 个工具（E2B_DOMAIN={os.environ.get('E2B_DOMAIN', '?')}）\n")
    ready, missing = [], []
    for i in insts:
        tcr_ok = check_tcr_tag(i.image_ags)
        tool_ok = "?"
        try:
            sb = Sandbox.create(template=i.tool_name, timeout=60)
            sb.kill()
            tool_ok = "OK"
        except Exception as e:
            tool_ok = f"MISSING ({str(e)[:80]})"
        line = (f"{i.tool_name:36s} tool={tool_ok:20s} "
                f"tcr={'OK' if tcr_ok else 'MISSING'} ({i.image_ags.split('/')[-1]})")
        print(line)
        if tool_ok == "OK" and tcr_ok:
            ready.append(i.instance_id)
        else:
            missing.append(i.instance_id)
    print(f"\n就绪 {len(ready)}/{len(insts)}" + (f"；未就绪: {missing}" if missing else "，全部就绪"))
    sys.exit(0 if not missing else 1)


if __name__ == "__main__":
    main()
