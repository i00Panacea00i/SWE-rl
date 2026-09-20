# 03 · 沙箱平台问题（AGS / TCR / e2b）

> 沙箱工具配额、镜像覆盖、预热、创建竞态、凭证限流、环境激活——平台侧全部坑位的根因与修复。
> 方案全文见 [../ags_image_override.md](../ags_image_override.md)（含实测证据）。

---

## 1. 工具配额上限（30/账号）→ 镜像覆盖方案

**现象**：按"每题一个沙箱工具"做法，28 道题占掉 28/30 配额；新增题目直接触顶；后来平台清空工具，所有题集中失效。

**根因**：AGS 沙箱工具是**账号级 30 个上限**；传统做法把"题"绑定在"工具"上，无法扩展。

**修复（镜像覆盖）**：**1 个通用工具 + 创建实例时逐题覆盖镜像**：
```python
# 通用工具（仅 1 个，名为 swe-ags，默认镜像仅为占位）
# 做题时：StartSandboxInstance 覆盖该题镜像
StartSandboxInstance(ToolName="swe-ags",
                     CustomConfiguration={"Image": f"...swe-mirror/swe-ags:{tag}"})
# e2b SDK 接入（不是 create！）
sbx = Sandbox.connect(instance_id)
```
镜像 tag 规则：`instance_id` 小写、`__` → `_s_`（如 `python__mypy-5617` → `python_s_mypy-5617`）。

**沉淀**：
- 配额受限系统优先找"模板+覆盖"式的解耦设计；
- e2b 原生 `create()` **没有镜像参数**——覆盖必须走"AGS API 创建 + `Sandbox.connect()` 接入"两步。

---

## 2. 镜像未预热——`image is still preparing`

**现象**：创建实例报 `[TencentCloudSDKException] ResourceUnavailable: image is still preparing, please retry later`；或实例长时间卡 `CREATING`。

**根因**：题镜像只在 TCR 里，AGS 平台节点**没有缓存**——首次创建触发平台侧拉取/分发（分钟级）。

**修复**：批量预热（`CreatePreCacheImageTask`，入参仅 Image + ImageRegistryType='enterprise'）：
```python
for r in todo:
    req = models.CreatePreCacheImageTaskRequest()
    req.Image = r["image_tcr"]; req.ImageRegistryType = "enterprise"
    client.CreatePreCacheImageTask(req)
```
预热完成后实例创建 **~4.2 秒直接 RUNNING**。

**沉淀**：把"预热"作为数据准备流水线的标准一步（86 个镜像批量提交 <2 分钟）。

---

## 3. 实例创建竞态——`409 Sandbox is not active, current status: CREATING`

**现象**：`start_instance` 轮询已见 `RUNNING`，但 `Sandbox.connect()` 报 `409 ... not active, current status: CREATING`。

**根因**：平台状态机与 e2b 接入层**状态可见性存在秒级窗口**（Describe 显示 RUNNING，e2b 网关仍判 CREATING）。

**修复**：**暂时性错误自动重试**（已被固化进验证/训练链路）：
```python
RETRY_HINTS = ("409", "CREATING", "still preparing", "ResourceUnavailable")
for attempt in range(4):
    out = self._run_once(inst, mode)
    if not any(h in out.get("why", "") for h in RETRY_HINTS):
        return out
    time.sleep(40)          # 退避重试，最多 3 次
```

**沉淀**：所有"创建→就绪→接入"三段式平台调用都要假定**存在竞态窗口**，重试是标配而非兜底。

---

## 4. OAuth 凭证刷新限流——`RequestLimitExceeded`

**现象**：训练 mid-run 大量 `AgentLoopWorker` 报错：
```
RuntimeError: refresh_user_token failed: Code=RequestLimitExceeded,
Message=您当前每秒请求 `23` 次，超过了每秒频率上限 `20`
```

**根因**：`ags_instance.py` 的凭证缓存是**进程内缓存**——训练有 10 个 AgentLoop worker 进程，凭证过期瞬间**各进程并发刷新** → 超过 OAuth 接口每秒 20 次上限 → 全部失败 → 沙箱创建连锁失败。

**修复（两层）**：
1. **跨进程文件缓存**（`/tmp/ags-cred-cache.json`）：第一个进程刷新成功后写文件，其余进程直接读取——10 个进程只刷新 1 次；
2. **退避重试**：限流错误按 1.5s×(n+1) 递增等待重试（最多 6 次）。

```python
def _load_shared_cred():   # 文件缓存（未过期直接返回）
    d = json.loads(Path(_CRED_CACHE_FILE).read_text())
    if d["expiresAt"] - time.time() > REFRESH_SAFE_DUR:
        return {...}, d["expiresAt"]
```

**沉淀**：
- **多进程 + 会过期的凭证 = 必须跨进程共享刷新结果**（进程内缓存是陷阱）；
- 所有"临时凭证刷新"都要做限流退避（平台侧限速通常很低）。

---

## 5. 沙箱内 Python 环境激活

**现象**：沙箱里直接 `python -c "import pydantic"` 报 `ModuleNotFoundError`；`bash /tmp/eval.sh` 却正常。

**根因**：SWE-bench 镜像的测试环境在 conda 环境 `/opt/miniconda3/envs/testbed`，**系统 python 一无所有**；官方 eval.sh 自带 activate。

**修复**：
```bash
# 方式一（绝对路径）
/opt/miniconda3/envs/testbed/bin/python -c "import pydantic"
# 方式二（激活）
source /opt/miniconda3/bin/activate testbed
```

**沉淀**：与沙箱交互的一切排障脚本，**先激活环境再 import**；不要用系统 python 判断环境健康。

---

## 6. 沙箱路由预检——`Untrusted sandbox route`

**现象**：训练启动即报沙箱路由错误（parquet 的 `tool_name` 与实例表不一致）。

**根因**：数据管线的三段（instances.jsonl / parquet extra_info / AgentLoop 构建）引用的**工具/镜像标识不一致**——如 parquet 里是旧 `tool_name`，而平台侧工具已被清理。

**修复**：
1. 数据侧：新增 `image_tcr` 字段贯通全链路（`prepare_data.py` 自动生成，`episode.py` 优先读它）；
2. 运行侧：训练启动前跑预检：
```bash
python -m sandbox.preflight <train.parquet> <eval.parquet>
# 输出 PREFLIGHT OK: 沙箱路由表一致
```

**沉淀**：数据管线的"标识字段"（tool_name/image/image_tcr）必须**单一来源、全链路校验**；预检失败 fail-fast 好过训练中途暴雷。

---

## 7. 工具/实例生命周期约束

**现象**：删除沙箱工具报 `ResourceInUse.SandboxTool: N instances are still active`。

**根因**：AGS 约束——**工具删除前必须先停掉其全部实例**。

**修复**：
```bash
# 1) 查 RUNNING 实例 → 逐个 StopSandboxInstance
# 2) 再删工具
```

**沉淀**：`Timeout` 参数必须显式传（默认 5 分钟自动回收）；训练 episode 用 30m~1h。用完 **kill 沙箱**（`finally` 里 best-effort），避免实例泄漏积压配额。

---

## 8. 平台侧"清空事件"的应对（2026-09-17）

**现象**：旧工具全部消失（19 个 swe-* 只剩 1 个通用工具）；已预热镜像的部分缓存失效。

**根因**：平台侧变更（未公告）——工具/缓存被重置。

**修复**：由于此前已落地**镜像覆盖方案**（不依赖逐题工具）+ 数据侧 `image_tcr` 字段 —— **训练侧零代码改动**即恢复：重建 1 个通用工具 + 重跑预热任务列表。

**沉淀**：这是"镜像覆盖"设计的**最大红利**——平台清空工具时，逐题工具方案要重建 28+ 个工具，单工具方案只需 1 个。**把平台易变性隔离在最小面积内。**
