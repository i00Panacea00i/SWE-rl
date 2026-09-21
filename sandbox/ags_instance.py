"""AGS 沙箱实例管理：通用工具 + 镜像覆盖（Image Override）+ 凭证自动刷新。

配套文档 docs/infrastructure/ags_image_override.md。核心流程：
  1. StartSandboxInstance(ToolName=<通用工具>, CustomConfiguration.Image=<题的TCR镜像>)
  2. 轮询至 RUNNING
  3. e2b Sandbox.connect(instance_id) 接入既有 Agent 工具链

凭证优先级（_current_credential）：
  1) 环境变量静态凭证 TENCENTCLOUD_SECRET_ID/KEY[/TOKEN]（子账号长期密钥，无需刷新）
  2) 环境变量 OAuth 刷新链 TENCENTCLOUD_REFRESH_TOKEN/OPEN_ID[/SITE]
     （刷新算法与 tccli oauth 一致：refresh_user_token → get_temp_cred，
       训练 Pod 长跑时凭证到期自动续期）
  3) 本机 ~/.tccli/default.credential（开发机；oauth 型凭证走同一刷新链）
"""
from __future__ import annotations

import json
import os
import time
import uuid
from pathlib import Path

DEFAULT_REGION = os.environ.get("DEPLOY_REGION", "ap-singapore")
DEFAULT_IMAGE_PREFIX = os.environ.get(
    "AGS_IMAGE_PREFIX",
    "registry.example.com/swe-mirror/swe-ags",
)
DEFAULT_TOOL = os.environ.get("AGS_MULTI_TOOL", "swe-ags")
OAUTH_ENDPOINT = "https://cli.cloud.tencent.com"
REFRESH_SAFE_DUR = 300  # 距过期 <5 分钟即刷新（与 tccli 一致）

_cred_cache: dict = {"data": None, "expires_at": 0.0}
_client_cache: dict = {}

# 跨进程凭证缓存：多 worker 并发时只允许一个进程真正刷新（避免 OAuth 每秒频率上限）
_CRED_CACHE_FILE = os.environ.get("AGS_CRED_CACHE", "/tmp/ags-cred-cache.json")


def _load_shared_cred() -> tuple[dict, float] | None:
    try:
        d = json.loads(Path(_CRED_CACHE_FILE).read_text())
        exp = float(d.get("expiresAt", 0) or 0)
        if exp - time.time() > REFRESH_SAFE_DUR:
            return ({"secretId": d["secretId"], "secretKey": d["secretKey"],
                     "token": d.get("token", "")}, exp)
    except Exception:
        pass
    return None


def _save_shared_cred(cred: dict, expires_at: float):
    try:
        Path(_CRED_CACHE_FILE).write_text(json.dumps(
            {"secretId": cred["secretId"], "secretKey": cred["secretKey"],
             "token": cred.get("token", ""), "expiresAt": expires_at}))
    except Exception:
        pass


def _oauth_refresh_with_retry(refresh_token: str, open_id: str,
                              site: str, attempts: int = 6) -> tuple[dict, float]:
    """限流（每秒请求上限）时退避重试；其余错误短暂等待后重试。"""
    last: Exception | None = None
    for i in range(attempts):
        try:
            return _oauth_refresh(refresh_token, open_id, site)
        except Exception as e:  # noqa: BLE001
            last = e
            msg = str(e)
            wait = 1.5 * (i + 1) if ("RequestLimitExceeded" in msg or "频率" in msg) else 1.0
            time.sleep(wait)
    raise last  # type: ignore[misc]


def tcr_image_for(instance_id: str, prefix: str = "") -> str:
    """实例 ID → swe-ags 批构建镜像地址。

    tag 规则（与 sandbox/build_swe_gym_images.sh 一致）：小写、`__` → `_s_`。
    例：python__mypy-5617 → <prefix>:python_s_mypy-5617
    """
    tag = instance_id.lower().replace("__", "_s_")
    return f"{prefix or DEFAULT_IMAGE_PREFIX}:{tag}"


def _oauth_refresh(refresh_token: str, open_id: str, site: str) -> tuple[dict, float]:
    """tccli 同款刷新链：refresh_user_token → get_temp_cred。"""
    import warnings

    import requests

    # 与 tccli 保持一致：该端点为 CLI 专用，证书链不完整，关闭校验仅用于凭据刷新
    warnings.filterwarnings("ignore", message="Unverified HTTPS request")
    r1 = requests.post(
        OAUTH_ENDPOINT + "/refresh_user_token",
        json={"TraceId": str(uuid.uuid4()), "RefreshToken": refresh_token,
              "OpenId": open_id, "Site": site},
        verify=False, timeout=30)
    d1 = r1.json()
    if "Error" in d1:
        raise RuntimeError(f"refresh_user_token failed: {json.dumps(d1)[:300]}")
    r2 = requests.post(
        OAUTH_ENDPOINT + "/get_temp_cred",
        json={"TraceId": str(uuid.uuid4()), "AccessToken": d1["AccessToken"],
              "Site": site},
        verify=False, timeout=30)
    d2 = r2.json()
    if "Error" in d2:
        raise RuntimeError(f"get_temp_cred failed: {json.dumps(d2)[:300]}")
    return ({"secretId": d2["SecretId"], "secretKey": d2["SecretKey"],
             "token": d2["Token"]}, float(d2["ExpiresAt"]))


def _fetch_credential() -> tuple[dict, float]:
    """返回 (cred, expires_at)。expires_at=0.0 表示永久凭证（无需刷新）。

    优先级：OAuth 刷新链（长跑自动续期）> 静态密钥 > 本机 tccli 文件。
    """
    rt = os.environ.get("TENCENTCLOUD_REFRESH_TOKEN")
    oid = os.environ.get("TENCENTCLOUD_OPEN_ID")
    if rt and oid:
        shared = _load_shared_cred()
        if shared:
            return shared
        cred, exp = _oauth_refresh_with_retry(rt, oid, os.environ.get("TENCENTCLOUD_SITE", "cn"))
        _save_shared_cred(cred, exp)
        return cred, exp

    sid = os.environ.get("TENCENTCLOUD_SECRET_ID")
    skey = os.environ.get("TENCENTCLOUD_SECRET_KEY")
    if sid and skey:
        return ({"secretId": sid, "secretKey": skey,
                 "token": os.environ.get("TENCENTCLOUD_TOKEN", "")},
                0.0 if not os.environ.get("TENCENTCLOUD_TOKEN") else
                float(os.environ.get("TENCENTCLOUD_EXPIRES_AT", 0) or 0))

    data = json.loads(Path("~/.tccli/default.credential").expanduser().read_text())
    oauth = data.get("oauth") or {}
    if data.get("type") == "oauth" and oauth.get("refreshToken"):
        shared = _load_shared_cred()
        if shared:
            return shared
        cred, exp = _oauth_refresh_with_retry(oauth["refreshToken"], oauth["openId"],
                                              oauth.get("site", "cn"))
        _save_shared_cred(cred, exp)
        return cred, exp
    return ({"secretId": data["secretId"], "secretKey": data["secretKey"],
             "token": data.get("token", "")}, float(data.get("expiresAt", 0) or 0))


def _current_credential() -> dict:
    now = time.time()
    cached = _cred_cache["data"]
    if cached and (_cred_cache["expires_at"] == 0.0
                   or _cred_cache["expires_at"] - now > REFRESH_SAFE_DUR):
        return cached
    cred, expires_at = _fetch_credential()
    _cred_cache.update(data=cred, expires_at=expires_at)
    return cred


def _client(region: str = ""):
    region = region or DEFAULT_REGION
    now = time.time()
    state = _client_cache.get(region)
    if state and (state["expires_at"] == 0.0
                  or state["expires_at"] - now > REFRESH_SAFE_DUR):
        return state["client"]
    from tencentcloud.ags.v20250920 import ags_client
    from tencentcloud.common import credential as tc_credential

    cred = _current_credential()
    client = ags_client.AgsClient(
        tc_credential.Credential(cred["secretId"], cred["secretKey"], cred["token"]),
        region)
    _client_cache[region] = {"client": client, "expires_at": _cred_cache["expires_at"]}
    return client


def start_instance(image_tcr: str, tool_name: str = "", timeout_s: int = 3600,
                   ready_timeout_s: int = 90, region: str = "") -> str:
    """通用工具 + 镜像覆盖拉起实例，等待 RUNNING 后返回 InstanceId。

    镜像已预热时通常 ~5s 就绪；未预热时启动更慢（ready_timeout_s 内轮询）。
    """
    from tencentcloud.ags.v20250920 import models

    client = _client(region)
    req = models.StartSandboxInstanceRequest()
    req.ToolName = tool_name or DEFAULT_TOOL
    req.Timeout = f"{int(timeout_s)}s"          # 必传：默认仅 5 分钟
    cc = models.CustomConfiguration()
    cc.Image = image_tcr
    cc.ImageRegistryType = "enterprise"
    req.CustomConfiguration = cc
    resp = client.StartSandboxInstance(req)
    iid, status = resp.Instance.InstanceId, resp.Instance.Status
    deadline = time.time() + ready_timeout_s
    while status != "RUNNING":
        if time.time() > deadline:
            raise TimeoutError(
                f"AGS instance not RUNNING within {ready_timeout_s}s: {iid} status={status}")
        time.sleep(3)
        q = models.DescribeSandboxInstanceListRequest()
        q.Limit = 100
        found = [i.Status for i in client.DescribeSandboxInstanceList(q).InstanceSet
                 if i.InstanceId == iid]
        status = found[0] if found else "UNKNOWN"
    return iid


def stop_instance(instance_id: str, region: str = "") -> bool:
    """停止实例（best-effort，用于创建/连接失败后的兜底清理）。"""
    from tencentcloud.ags.v20250920 import models

    try:
        req = models.StopSandboxInstanceRequest()
        req.InstanceId = instance_id
        _client(region).StopSandboxInstance(req)
        return True
    except Exception:
        return False
