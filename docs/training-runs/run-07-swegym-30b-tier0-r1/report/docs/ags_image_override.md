# AGS 单工具多镜像方案（Image Override 指南）

> **面向对象**：需要在本项目（或任何使用腾讯云 AGS/Agent Runtime 的项目）中
> 动态拉起 SWE 沙箱的 Agent / 工程师。
>
> **核心结论**：AGS **支持**创建实例时动态指定镜像——一个通用沙箱工具即可服务任意
> 数量的题目镜像，**推翻** `docs/infrastructure/ags_tool_setup.md` 中"AGS 不支持创建实例时动态
> 指定镜像"的旧假设（该文档写作时尚未验证）。
>
> **实测日期**：2026-09-18（项目内全闭环验证通过，见第 6 节证据）

---

## 0. TL;DR

| 项 | 旧做法（逐题工具） | 新做法（单工具 + 镜像覆盖） |
|---|---|---|
| 工具数量 | 每道题 1 个（28 题 = 28 个） | **1 个通用工具** |
| 镜像绑定 | 工具创建时固定 | **实例创建时覆盖** |
| 配额（30/账号） | 28 个被占，无法扩展 | 仅占 1 个，**释放 27+** |
| 创建耗时 | — | SDK 创建 **4.2 秒直接 RUNNING**（镜像已预热） |
| e2b SDK | `Sandbox.create(template=工具名)` | **`Sandbox.connect(实例ID)`**（外部创建后接入） |

---

## 1. 概念模型

```
SandboxTool（模板）                     StartSandboxInstance（实例）
┌────────────────────────┐             ┌────────────────────────┐
│ 默认 CustomConfiguration │  ──创建──▶ │ 实例级 CustomConfiguration │
│  - Image   = 镜像A      │             │  - Image = 镜像B（覆盖！） │
│  - Command = /usr/bin/envd │          │  - 其余字段自动继承工具默认  │
│  - Ports/Probe/Resources │            │                        │
└────────────────────────┘             └────────────────────────┘
```

- **字段级合并**：`StartSandboxInstance` 的 `CustomConfiguration` 只需传要覆盖的字段
  （通常仅 `Image` + `ImageRegistryType`），未传字段继承工具的默认值。
- **envd 约定不变**：镜像内 envd 监听 49983，探针 `GET /health`；e2b connect 依赖此约定。
- **e2b 原生 `create()` 没有镜像参数**（只有 `template` 选择工具）——所以覆盖路径必须
  **先走 AGS API 创建实例，再用 `Sandbox.connect()` 接入**。

---

## 2. 前置条件

| 项 | 说明 |
|---|---|
| TCR 镜像 | `enterprise` 类型仓库（本例 `registry.example.com/swe-mirror/swe-ags:<tag>`），镜像内必须含 envd |
| 镜像预热 | `CreatePreCacheImageTask`（否则冷启动慢；预热后实测 4.2s 就绪） |
| RoleArn | TCR 拉取权限：`qcs::cam::uin/<YOUR_UIN>:roleName/<YOUR_TCR_ROLE>` |
| CAM 凭证 | `secretId` + `secretKey` + `token`（本项目 CVM 的 `~/.tccli/default.credential` 为**临时凭证**，含 `expiresAt`） |
| 配额 | 账号级沙箱工具上限 30 个（含其他项目占用） |

---

## 3. Recipe A：tccli 创建覆盖实例（手工/脚本）

```bash
# 一次性：创建通用工具（默认镜像随意，只作为模板）
tccli ags CreateSandboxTool --region ap-singapore --cli-unfold-argument \
  --ToolName "swe-ags" \
  --ToolType custom \
  --NetworkConfiguration.NetworkMode SANDBOX \
  --CustomConfiguration.Image "registry.example.com/swe-mirror/swe-ags:conan-io_s_conan-10408" \
  --CustomConfiguration.ImageRegistryType enterprise \
  --CustomConfiguration.Command /usr/bin/envd \
  --CustomConfiguration.Ports.0.Name envd \
  --CustomConfiguration.Ports.0.Port 49983 \
  --CustomConfiguration.Ports.0.Protocol TCP \
  --CustomConfiguration.Probe.HttpGet.Path /health \
  --CustomConfiguration.Probe.HttpGet.Port 49983 \
  --CustomConfiguration.Probe.HttpGet.Scheme HTTP \
  --CustomConfiguration.Probe.ReadyTimeoutMs 30000 \
  --CustomConfiguration.Probe.ProbeTimeoutMs 3000 \
  --CustomConfiguration.Probe.ProbePeriodMs 3000 \
  --CustomConfiguration.Probe.SuccessThreshold 1 \
  --CustomConfiguration.Probe.FailureThreshold 100 \
  --CustomConfiguration.Resources.CPU 1 \
  --CustomConfiguration.Resources.Memory 2Gi \
  --CustomConfiguration.Resources.Storage 10Gi \
  --RoleArn "qcs::cam::uin/<YOUR_UIN>:roleName/<YOUR_TCR_ROLE>" \
  --DefaultTimeout 1h

# 每次拉起某道题的环境：覆盖镜像（新题只需改最后一段 tag）
tccli ags StartSandboxInstance --region ap-singapore --cli-unfold-argument \
  --ToolName "swe-ags" --Timeout 30m \
  --CustomConfiguration.Image "registry.example.com/swe-mirror/swe-ags:python_s_mypy-5617" \
  --CustomConfiguration.ImageRegistryType enterprise
# 返回 InstanceId 与 Status（镜像已预热时直接 RUNNING）
```

**镜像 tag 规则**（本项目 swe-ags 镜像）：`instance_id` 小写、`__` → `_s_`。
例：`python__mypy-5617` → `python_s_mypy-5617`。

---

## 4. Recipe B：Python SDK 创建（训练/Agent 集成推荐）

```python
import json, time
from tencentcloud.common import credential
from tencentcloud.ags.v20250920 import ags_client, models

# 凭据（临时的 secretId/secretKey/token）
creds = json.load(open("/root/.tccli/default.credential"))   # {secretId, secretKey, token, ...}
cred = credential.Credential(creds["secretId"], creds["secretKey"], creds.get("token", ""))
client = ags_client.AgsClient(cred, "ap-singapore")

def start_swe_instance(image_tag: str, tool: str = "swe-ags", timeout: str = "30m") -> str:
    """通用工具 + 镜像覆盖拉起题目环境，返回 InstanceId。"""
    req = models.StartSandboxInstanceRequest()
    req.ToolName = tool
    req.Timeout = timeout                     # 必传！默认仅 5m，最大 24h
    cc = models.CustomConfiguration()
    cc.Image = f"registry.example.com/swe-mirror/swe-ags:{image_tag}"
    cc.ImageRegistryType = "enterprise"
    req.CustomConfiguration = cc              # ★ 镜像覆盖发生在这里
    resp = client.StartSandboxInstance(req)
    return resp.Instance.InstanceId           # 实测 4.2s，Status 直接 RUNNING

# 清理：实例用完即停（工具删除前也必须先停实例）
def stop_instance(iid: str):
    req = models.StopSandboxInstanceRequest(); req.InstanceId = iid
    client.StopSandboxInstance(req)
```

**就绪检查**（镜像未预热时建议轮询）：
```python
req = models.DescribeSandboxInstanceListRequest(); req.Limit = 100
lst = client.DescribeSandboxInstanceList(req)          # 注意：响应字段是 InstanceSet
status = [i.Status for i in lst.InstanceSet if i.InstanceId == iid]  # RUNNING 即就绪
```

---

## 5. Recipe C：e2b bridge（接入现有 Agent 工具链）

AGS API 创建的实例**可以被 e2b SDK 直接连接**——这是复用既有 AgentLoop
（命令执行/观察截断/token 对齐 tracing）的关键：

```python
from e2b import Sandbox

iid = start_swe_instance("python_s_mypy-5617")   # Recipe B
sbx = Sandbox.connect(iid, timeout=1800)         # ★ 接入 e2b（不是 create！）
r = sbx.commands.run("cd /testbed && git log --oneline -1 && "
                     "/opt/miniconda3/envs/testbed/bin/python -c \"import mypy\"",
                     user="root")
print(r.stdout)                                  # 预期: <base_commit 行> + 无报错
sbx.kill()                                       # 内部走 kill API，实例随之回收
```

实测输出（2026-09-18）：
```
5db3e1a02 [mypyc] Add 'bit' primitive type and streamline branching (#9606)
mypy OK
```

---

## 6. 实测证据（2026-09-18）

| # | 测试 | 结果 |
|---|---|---|
| 1 | 同工具（默认 conan-10408）拉起不覆盖实例 | RUNNING，Image=conan-10408 ✓ |
| 2 | 同工具覆盖 mypy-5617 镜像 | RUNNING，Image=mypy-5617 ✓（覆盖生效） |
| 3 | Python SDK 创建（pydantic-5529 覆盖） | 4.2s 直接 RUNNING ✓ |
| 4 | `Sandbox.connect` 覆盖实例 + 执行命令 | 输出正确（仓库/环境可见）✓ |
| 5 | kill + 实例清理 | 无残留 ✓ |

> 可直接复核的字段：`DescribeSandboxInstanceList` 返回中
> `CustomConfiguration.Image` 回显实际使用的镜像与 `ImageDigest`。

---

## 7. 陷阱与约束（踩坑清单）

1. **e2b `create()` 无法传镜像**——覆盖必须走 AGS API + `connect()` 两步。
2. **删除工具前必须先停其全部实例**，否则报
   `ResourceInUse.SandboxTool: N instances are still active`；
   先 `DescribeSandboxInstanceList` 找 RUNNING 实例 → `StopSandboxInstance` → 再删工具。
3. **`Timeout` 参数必须显式传**：默认 5 分钟回收，训练 episode 建议 `30m`~`1h`。
4. **临时凭证会过期**：`~/.tccli/default.credential` 含 `expiresAt` 与 `token`；
   服务化部署请改用子账号永久密钥或定期刷新，并在 401/鉴权错误时重建 client。
5. **配额是账号级 30 个工具**（含其他项目）——单工具方案正是为绕开此限制。
6. **镜像未预热时启动显著变慢**：先 `CreatePreCacheImageTask`（入参仅
   `Image` + `ImageRegistryType`），返回值里的 `ImageDigest` 可用于对账。
7. **环境激活**：swe-ags 镜像的 testbed 环境在 `/opt/miniconda3/envs/testbed`；
   直接用系统 python 会缺依赖（如 `ModuleNotFoundError: pydantic_core`），
   需用绝对路径 python 或 `conda activate testbed`。
8. **资源规格档位**：`Storage` 仅支持 `1Gi/5Gi/10Gi/20Gi`；CPU/Memory 自由（如 `1`/`2Gi`）。

---

## 8. 压缩模式对训练侧的改造点（供集成参考）

| 层 | 改动 |
|---|---|
| 数据集 | `extra_info` 增加 `image_tcr`（由 instance_id 推导 tag）；`tool_name` 全部指向通用工具 |
| AgentLoop | `Sandbox.create(template=...)` → `start_swe_instance(image_tcr)` + `Sandbox.connect(iid)`；kill 逻辑不变 |
| Pod | 注入 CAM 凭证（k8s secret）+ 安装 `tencentcloud-sdk-python`（NAT 出网可装） |
| 工具 | 只需 1 个通用工具（default 镜像任意），题量不再受配额约束 |

---

## 9. 官方参考

- 启动沙箱实例（StartSandboxInstance，含 CustomConfiguration 输入）：
  https://cloud.tencent.com/document/product/1814/124816
- 数据结构（CustomConfiguration / ProbeConfiguration / ResourceConfiguration 字段定义）：
  https://cloud.tencent.com/document/api/1814/124823
- 创建预热镜像任务（CreatePreCacheImageTask）：
  https://cloud.tencent.com/document/api/1814/127508

---

*文档作者：SWE-RL Kit · 2026-09-18 · 配套代码：`sandbox/create_tools_precache.sh`（预热+建工具）、`sandbox/ags_image_override_demo.py`（全闭环验证脚本，可直接运行）*
