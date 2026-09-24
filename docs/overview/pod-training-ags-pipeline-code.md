# Pod 训练流程 × AGS 调用：代码级架构文档

> **定位**：把「verl 的 RL 训练循环」与「AGS 沙箱调用」的**咬合面**逐行落到代码——
> 每个环节给出 `文件:行号`、函数签名、数据结构字段与落盘时机。
> **读者**：需要审查/维护/复刻这套 pipeline 的工程师与架构评审者。
> **配套文档**：宏观闭环 [training-loop-flow.md](training-loop-flow.md)；
> 通信协议手册 [pod-ags-communication.md](pod-ags-communication.md)；
> 口头讲解稿 [ags-lifecycle-briefing-script.md](ags-lifecycle-briefing-script.md)。
> **行号基准**：`swe_agent_loop.py` = 246 行版本；`episode.py` / `ags_instance.py` 为当前 main。

---

## 0. 代码地图

### 0.1 文件清单与职责边界

| 文件 | 行数 | 职责 | 关键符号 |
|---|---|---|---|
| `verl_plugin/swe_agent_loop.py` | 246 | **桥接层**：实现 verl 的 AgentLoop 协议，驱动单条 episode 的全生命周期 | `SWEAgentLoop` / `_episode` / `run` |
| `sandbox/episode.py` | ~370 | **轨迹驱动**：沙箱会话、命令包装、补丁导出、判分 | `EpisodeSession` / `evaluate_patch` / `check_patch` / `atomic_json` |
| `sandbox/ags_instance.py` | 222 | **控制面封装**：AGS 实例创建/销毁、凭证刷新 | `start_instance` / `stop_instance` / `_client` / `_oauth_refresh` |
| `sandbox/harness.py` | — | **实例与判分**：实例表加载、日志解析、奖励计算 | `Instance` / `load_instances` / `grade` / `compute_reward` |
| `sandbox/action_protocol.py` | — | **动作协议**：动作解析、操作分类、观察截断 | `parse_action` / `classify_operation` / `bounded_observation` |
| `verl_plugin/reward.py` | 17 | **奖励函数**：消费 trusted 判分结果（无文本回退） | `compute_score` |
| `controller/eval_driver.py` | — | **评估 driver**：独立 vLLM 进程复用同一沙箱/判分栈 | `init_one` / `exec_one` / `judge_one` |
| `configs/swe_agent_v2.yaml` | — | AgentLoop 参数（轮数/预算/并发/纪律提示） | — |

### 0.2 系统边界（谁不做什么）

```
┌── 我们的代码 ────────────────────────────────┐  ┌── verl 框架（第三方） ──┐
│ SWEAgentLoop（继承 AgentLoopBase）            │  │ AgentLoopBase          │
│   ├─ EpisodeSession ──► 控制面/数据面（AGS）  │  │  · ct_build_initial_tokens│
│   ├─ evaluate_patch ──► 判分（AGS 新沙箱）    │  │  · ct_merge_context_msg   │
│   └─ 轨迹落盘（CFS）                          │  │  · ct_merge_assistant_token│
│                                               │  │ AgentLoopOutput（契约）  │
└───────────────────────────────────────────────┘  └─────────────────────────┘
   ★ 边界原则：模型命令只在 AGS 沙箱中执行；
     Pod 侧只做"包装/解析/记账"，永不执行模型命令（episode.py:1 文档字符串）
```

## 1. 启动链路：训练进程如何装载 AGS 能力

### 1.1 类注册与继承（verl 插件机制）

```24:36:verl_plugin/swe_agent_loop.py
class SWEAgentLoop(AgentLoopBase):
    _semaphore = None

    def __init__(self, *args, max_steps=8, action_tokens=512, observation_tokens=512,
                 sandbox_concurrency=2, system_prompt=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.instances = {i.instance_id: i for i in load_instances()}
        self.max_steps = int(max_steps)
        self.action_tokens = int(action_tokens)
        self.observation_tokens = int(observation_tokens)
        # 训练纪律提示：非空时覆写数据集 system 消息（prompt 策略集中在 agent 配置，数据保持可复用）
        self.system_prompt = (system_prompt or "").strip() or None
        if SWEAgentLoop._semaphore is None:
            SWEAgentLoop._semaphore = asyncio.Semaphore(int(sandbox_concurrency))
```

四个要点：
1. **继承 `AgentLoopBase`**（`verl.experimental.agent_loop.agent_loop`）——verl 通过 `default_agent_loop=swe_ags` 配置找到本类；
2. **实例表预加载**：`load_instances()` 一次性读入题目表（含镜像地址），构造 `{instance_id: Instance}` 字典——**这是"题目 → 沙箱镜像"寻址的数据源**；
3. **`_semaphore` 是类变量**：同一 worker 进程内所有 episode 共享一个并发闸门（`sandbox_concurrency`）——完整并发 = 进程数（agent workers）× 每进程闸门值；
4. **`system_prompt` 覆写**（v2 新增）：非空时替换数据集 system 消息，把"行动纪律"从数据层挪到 agent 配置层。

### 1.2 实例表加载（`harness.py:64-101`）

```65:66:sandbox/harness.py
    source = Path(os.environ.get("SWE_INSTANCES_FILE", str(KIT_ROOT / "data" / "instances.jsonl")))
    rows = [json.loads(l) for l in source.read_text().splitlines() if l.strip()]
```
- 数据源：`SWE_INSTANCES_FILE`（默认 `data/instances.jsonl`）+ `task_specs/<iid>/`（eval.sh / gold.patch / test.patch / tests.json）；
- 产出 `Instance` 数据类（`harness.py:32-56`），字段：`instance_id / repo / base_commit / problem_statement / image_ags / image_env / tool_name / f2p / p2p / eval_sh / gold_patch / test_patch / log_parser / version / image_tcr`；
- 其中 **`image_tcr`**（默认空串）是"镜像覆盖模式"的开关：非空 → 沙箱走 `start_instance` 路径。

### 1.3 AgentLoop 参数与配置映射（`configs/swe_agent_v2.yaml`）

| YAML 字段 | 值（v2） | 进入代码的位置 | 作用 |
|---|---|---|---|
| `max_steps` | 16 | `self.max_steps` | 单条 episode 命令循环上限 |
| `action_tokens` | 2048 | 每轮 `params["max_tokens"]`（:95） | 单轮生成上限 |
| `observation_tokens` | 768 | `bounded_observation`（:159） | 观察回填 token 上限 |
| `sandbox_concurrency` | 16 | 类级 `Semaphore`（:35） | 进程内并发沙箱数 |
| `system_prompt` | 纪律文本 | `messages[0]` 覆写（:70-75） | 行为约束（v2） |

### 1.4 环境变量（AgLoop 运行依赖）

| 变量 | 影响 | 代码位置 |
|---|---|---|
| `SWE_RUN_ID` | 轨迹目录命名（`traces/<run>/...`） | `swe_agent_loop.py:54` |
| `SWE_TRACE_DIR` | 轨迹根目录（CFS） | `swe_agent_loop.py:55` |
| `SWE_INSTANCES_FILE` | 实例表路径 | `harness.py:65` |
| `AGS_IMAGE_PREFIX` / `AGS_MULTI_TOOL` | 镜像前缀 / 通用工具名 | `ags_instance.py:24-28` |
| `E2B_API_KEY` / `E2B_DOMAIN` | 数据面鉴权与端点 | e2b SDK 内部读取 |
| `DEPLOY_REGION` | AGS 区域 | `ags_instance.py:23` |

## 2. 单条 episode 的代码执行路径（核心章节）

### 2.1 入口 `_episode`：路由校验、目录与骨架（swe_agent_loop.py:39-88）

```40:68:verl_plugin/swe_agent_loop.py
        info = kwargs["extra_info"]
        iid = info["instance_id"]
        inst = self.instances[iid]
        if info["tool_name"] != inst.tool_name:
            raise ValueError("Untrusted sandbox route")
        episode_id = uuid.uuid4().hex
        ...
        trace_root = Path(os.environ.get("SWE_TRACE_DIR", "/mnt/cfs/swe-rl/traces"))
        directory = trace_root / run_id / phase / f"step-{step}" / iid / episode_id
        directory.mkdir(parents=True, exist_ok=False)
        record = {
            "schema_version": 1, "run_id": run_id, "episode_id": episode_id,
            "instance_id": iid, "tool_name": inst.tool_name,
            ...
            "split": info.get("split"), "started_at": time.time(),
            "agent_kind": "model_generated", "gold_patch_visible": False, "steps": [],
        }
        # rollout 侧预置目标测试：让 Agent 能跑测试拿到执行反馈（奖励仍按 f2p/total 计算）
        session = EpisodeSession(inst, directory / "agent", timeout=1800,
                                 apply_test_patch=True)
```

三个设计点：
1. **双源路由校验**（:43-44）：训练数据的 `extra_info.tool_name` 必须与实例表一致，否则拒跑（防数据错配）；
2. **目录 = 身份**：`traces/<run>/<phase>/step-<N>/<iid>/<episode_id>/`，每条轨迹独占目录（`exist_ok=False`）；
3. **`apply_test_patch=True`**：rollout 侧把目标测试预置进沙箱（模型能跑测试），且快照在预置**之后**做——保证导出的候选补丁只含模型改动。

### 2.2 阶段 A · 沙箱创建（入口 `episode.py:124`）

完整链路（详见 `pod-ags-communication.md` §1.2，此处只列代码坐标）：

| 步骤 | 代码位置 |
|---|---|
| `session.start()`（线程池执行，不阻塞事件循环） | `swe_agent_loop.py:85` |
| 模式分支：`image_tcr` 非空 → 镜像覆盖 | `episode.py:124-138` |
| `start_instance()` → `StartSandboxInstance` + 轮询 | `ags_instance.py:179-208` |
| `Sandbox.connect()`（e2b 接入） | `episode.py:134` |
| 连接失败兜底 `stop_instance()` | `episode.py:137` |
| 四道自检（HEAD / 构建 / 指纹 / 快照） | `episode.py:143-190` |
| 沙箱三件套写回 record | `swe_agent_loop.py:86-88` |

### 2.3 阶段 B · 命令循环（`for turn in range(self.max_steps)`，:89-172）

**每轮的代码顺序**（这张表就是 pipeline 的心跳）：

| # | 动作 | 代码位置 | 关键数据结构 |
|---|---|---|---|
| 1 | token 预算检查（不足则 `token_budget` 收尾） | :90-93 | `budget = rollout_config.response_length` |
| 2 | vLLM 生成（异步） | :94-99 | `server_manager.generate(prompt_ids=runtime_ids, ...)` |
| 3 | token 合并（生成段并入连续序列） | :103-106 | `ct_merge_assistant_token(...)` → `mask/logprobs` |
| 4 | 解码为动作文本 | :108 | `tokenizer.decode(generated.token_ids)` |
| 5 | 动作解析（宽松模式） | :114 | `parse_action(action)` → `(command, submit_requested)` |
| 6 | **AGS 执行**（线程池，60s 超时） | :116 | `session.run(command, 60)` → `(code, out, err)` |
| 7 | 组装观察 | :117 | `f"exit_code={code}\n{out}{err}"` |
| 8 | submit 门禁（<3 次操作则驳回） | :121-128 | `operations` 计数器 |
| 9 | 操作分类 + 步骤落盘 | :130-143 | `classify_operation` → `record["steps"].append(...)` + `atomic_json` |
| 10 | 终止判定 | :144-157 | `stop_reason ∈ {submit, step_budget, token_budget}` |
| 11 | 观察截断（token 级） | :159-160 | `bounded_observation(tokenizer, obs, observation_tokens)` |
| 12 | 上下文合并（观察段并入序列，mask=0） | :162-164 | `ct_merge_context_msg(...)` |

**关键：token 级账本的三次合并**（这是"AGS 交互能进梯度"的唯一通道）：

```
ct_build_initial_tokens   (:76)   messages → runtime_ids   （初始 prompt）
ct_merge_assistant_token  (:103)  生成 token → mask=1      （模型的"动作"，参与训练）
ct_merge_context_msg      (:162)  观察文本 → mask=0         （环境反馈，不参与梯度）
```

> `mask=1` 的 token 才是 GRPO 的学习对象；AGS 的观察被记为 `mask=0`（上下文但不训练）——
> 这一分离由 `AgentLoopOutput.response_mask` 语义定义（verl 源码：`1 for LLM generated token, 0 for tool response token`）。

**五种 episode 终态**（`stop_reason`，含落盘时机）：

| 终态 | 触发条件 | 代码位置 |
|---|---|---|
| `submit` | 模型输出 SUBMIT 且 `operations ≥ 3` | :121-124, 145 |
| `step_budget` | 用满 `max_steps` 轮 | :147-148 |
| `token_budget` | 剩余预算不足以生成 | :90-93 / :151-152 / :165-166 |
| （无终态） | 异常中断 → `record["error"]` 落盘后 raise | :233-236 |
| （无终态） | 进程被 OOM 杀死 → 目录里只有部分文件 | 平台侧 |

### 2.4 阶段 C · 收尾：补丁导出与沙箱关闭（:175-190）

```177:184:verl_plugin/swe_agent_loop.py
            try:
                record["changed_files"] = await asyncio.to_thread(session.changed_files)
            except RuntimeError:
                record["changed_files"] = None
            await asyncio.to_thread(session.close)
            closed = True
```

| 步骤 | 代码 | 说明 |
|---|---|---|
| ① 导出补丁 `export_patch()` | `episode.py:233-246` | `git diff` 相对"原始树快照"——**只含模型改动** |
| ② 补丁安全校验 `check_patch()` | `episode.py:48-64` | 拒绝：超大（256KB）/二进制/重命名/受保护路径（tests、.*配置）|
| ③ 改动清单 `changed_files()` | `episode.py:248-263` | 与补丁互证（空列表 = 模型未做任何改动）|
| ④ 关闭沙箱 `close()` | `episode.py:265-279` | `sb.kill()` + 落盘 `execution.json` |

**双失败语义**（补丁被拒时的降级，:185-188）：
```python
            if patch_error:
                final = {"instance_id": iid, "reward": 0.0, "resolved": False,
                         "rejection": patch_error, "failure_kind": "candidate_rejected"}
```
——补丁被拒 = 直接 0 分（**不再起判分沙箱**，节约一次沙箱生命周期）。

### 2.5 阶段 D · 判分 `evaluate_patch`（episode.py:282-367，独立第二沙箱）

| 步骤 | 代码位置 | 关键细节 |
|---|---|---|
| ① 新建判分沙箱 | `episode.py:287-290` | `EpisodeSession(inst, directory, timeout+300)` + `start()`——**与 rollout 沙箱物理隔离**（实测 `sandbox_id` 不同）|
| ② 重放补丁 | `episode.py:291-297` | `files.write("/tmp/candidate.patch")` → `git apply --check && git apply` |
| ③ 写判分脚本 | `episode.py:298` | `prepare_eval_script(inst)`（改写官方 eval.sh：替换 pip 安装为源码导入自检，:67-105）|
| ④ 执行并整份取回日志 | `episode.py:300-308` | `bash /tmp/swe-eval.sh > /tmp/swe-eval.log` → `files.read` → 落盘 `test.log`（**不截断**）|
| ⑤ 解析逐用例状态 | `episode.py:309-321` | `extract_test_log` + `log_parsers.<parser>`（按题指定，如 `parse_log_pytest`）|
| ⑥ 假阴性防护 | `episode.py:322-343` | 候选补丁引发收集/导入错误时，**先跑 baseline-control**（空补丁对照）——对照也失败则拒绝给分 |
| ⑦ 组装结果 | `episode.py:344-361` | `result.json`（见下方字段表），含 `patch_sha256` |

**`judge/result.json` 字段表**（训练的奖励源头）：

| 字段 | 来源 | 用途 |
|---|---|---|
| `reward` | `compute_reward`（harness.py:217-224）| **f2p 通过比例**（`len(f2p_passed)/len(f2p)`，非 0/1 二元！）|
| `resolved` | 全部 f2p + p2p 通过 | 评估口径（pass@k）|
| `grade` | `grade()`（harness.py:188-215）| `f2p_passed/f2p_failed/p2p_passed/p2p_failed` 逐用例清单 |
| `sandbox_id` | 判分沙箱 ID | 与 rollout 沙箱对照审计 |
| `suite_exit` / `suite_collected` | 判分脚本退出码 | 基础设施失败 vs 真实失败的分界 |
| `failure_kind` | 候选错误分类 | `candidate_collection_or_import_error` 等 |
| `patch_sha256` | 补丁哈希 | 证据链固定 |

### 2.6 数据契约 · `AgentLoopOutput`（交回 verl 的最终结构）

```224:231:verl_plugin/swe_agent_loop.py
            return AgentLoopOutput(
                prompt_ids=prompt_ids, response_ids=response_ids, response_mask=mask,
                response_logprobs=logprobs if logprobs else None,
                reward_score=float(final["reward"]), num_turns=len(messages),
                metrics=metrics, extra_fields=model_extra)
```

| 字段 | 本地来源（代码行） | 语义 |
|---|---|---|
| `prompt_ids` | `runtime_ids[:-len(mask)]`（:216） | 初始 prompt（含纪律提示）|
| `response_ids` | `runtime_ids[-len(mask):]`（:215） | 生成 + 观察的连续 token 序列 |
| `response_mask` | 三次合并累计（:103/:162） | **1=模型生成（训练）· 0=观察回填（不训练）** |
| `response_logprobs` | vLLM 生成时返回（:105） | 逐 token 对数概率（GRPO 重要性采样用）|
| `reward_score` | `final["reward"]`（判分结果）| 训练奖励 |
| `num_turns` | `len(messages)` | 交互轮数 |
| `extra_fields` | `swe_evaluation` + `trace_path` + `reward_extra_info`（:238-243）| 判分全量结果 + 轨迹路径 + 奖励明细 |

> **双重奖励通道**：`reward_score` 与 `extra_fields.swe_evaluation` 同时携带奖励信息——
> 前者供 verl 的 rollout 统计；后者供自定义奖励函数 `reward.py:compute_score` 二次校验
> （`compute_score` 只认 `swe_evaluation`，缺失即 raise，**无文本回退**）。

## 3. 四个接口契约的代码级实现

| # | 契约 | 上游 → 下游 | 代码链 |
|---|---|---|---|
| ① | **任务寻址** | parquet → 沙箱 | `extra_info.instance_id`（:40）→ `self.instances[iid]`（:42）→ `inst.image_tcr`（`episode.py:124`）→ `start_instance()` |
| ② | **动作闭环** | token → 命令 → 观察 → token | `decode`（:108）→ `parse_action`（:114）→ `session.run`（:116）→ 观察（:117）→ `ct_merge_context_msg`（:162）|
| ③ | **奖励回传** | 判分 → GRPO | `result.json` → `record["final"]`（:206）→ `model_extra["swe_evaluation"]`（:239）→ `compute_score`（reward.py）→ `AgentLoopOutput.reward_score`（:229）|
| ④ | **训练对齐** | 轨迹 → DataProto | `token_alignment`（:216-219）→ `AgentLoopOutput`（:224-231）→ verl 侧拼批 → GRPO 输入 |

**契约 ④ 的完整性要求**（易错点）：
```216:222:verl_plugin/swe_agent_loop.py
            response_ids = runtime_ids[-len(mask):]
            prompt_ids = runtime_ids[:-len(mask)]
            if len(response_ids) > budget:
                raise RuntimeError("Continuous-token response exceeds configured budget")
            record["token_alignment"] = {
                "prompt_ids": prompt_ids, "response_ids": response_ids,
                "response_mask": mask, "response_logprobs": logprobs,
            }
```
- `len(response_ids) > budget` 直接抛错——**token 预算必须严格闭环**（这也是 v2 把预算从 8192 提到 16384 的代码层原因）；
- `token_alignment` 与 `AgentLoopOutput` 同源同值——轨迹档案里存的就是回传训练框架的张量。

## 4. 一个训练步内的代码级时序（真实耗时对照）

| 阶段 | verl 侧动作 | 本仓库代码入口 | AGS 是否参与 | 落盘产物 | 实测耗时（step 11 稳态）|
|---|---|---|---|---|---|
| **rollout** | `generate_sequences` → `SWEAgentLoop.run` | `_episode` 全流程（:39-243）| **是**（创建/命令/销毁/判分）| `episode.json` + `execution.json` + `candidate.patch` + `judge/*` | **641.3s** |
| old_log_prob | 重算策略概率 | — | 否 | — | 31.1s |
| ref | 参考模型前向 | — | 否 | — | 29.9s |
| adv | GRPO 组内优势 | — | 否 | — | 0.06s |
| update_actor | LoRA 梯度更新（26.7M 参数）| — | 否 | 检查点（每 5 步：`save_lora_only`）| 75.4s |
| update_weights | LoRA 灌回 vLLM（51MB 逐单元）| `adapter_export.py`（补丁）| — | `BOUNDED_LORA_EXPORT` 日志 | 3.4s |
| 合计 | — | — | — | — | **781.3s** |
> 数据来源：step 11 日志行 2001（各项加总 = `perf/time_per_step` 自洽）；早期版本混用了 step 6/11 两行数据，已勘误——详见 [single-training-step-anatomy.md](single-training-step-anatomy.md) §0.3。

> **代码级结论**：AGS 只出现在 rollout 阶段（一条直线：`_episode`），
> 但其内部有 4 次 AGS 云 API 交互（创建 rollout 沙箱 / 销毁 / 创建判分沙箱 / 销毁）
> 与 ≤16 轮命令往返——全部收敛在 `AgentLoopOutput` 这一个数据结构里交回 verl。

---

## 5. 配置与参数全景（全部来自代码）

### 5.1 关键常量与超时矩阵

| 项 | 值 | 代码位置 | 说明 |
|---|---|---|---|
| 模型命令执行超时 | **60s**（沙箱内 `timeout -k 5s 60s`）| `swe_agent_loop.py:116` → `episode.py:217` | 超时命令返回 `exit=124` |
| e2b 调用侧超时 | `timeout + 20` = 80s | `episode.py:223` | 防网络挂起（比沙箱内多 20s）|
| 框架自检命令超时 | 30s（HEAD/指纹）/ 60s（快照/补丁）| `episode.py:144/174/180/187` | trusted 路径 |
| 沙箱存活 TTL | 1800s | `episode.py:109`（`timeout=1800`）→ `ags_instance.py:190` | 平台级兜底回收 |
| 沙箱就绪等待 | 90s | `ags_instance.py:180` | 轮询间隔 3s |
| 判分脚本超时 | `timeout + 30`（≈1830s）| `episode.py:303` | 官方测试套件 |
| 输出上限 | 32,768 B（drain 头 25%+尾 75%）| `episode.py:22`（`MAX_OUTPUT_BYTES`）| 防日志撑爆回传 |
| 补丁上限 | 256,000 B | `episode.py:21`（`MAX_PATCH_BYTES`）| `check_patch` 首检 |
| 模型命令长度上限 | 12,000 字符 | `episode.py:196` | 超长直接 `exit=2` |
| 观察回填上限 | 768 token（v2）| `swe_agent_v2.yaml` → `bounded_observation`（:159）| token 级截断 |
| 单轮生成上限 | 2048 token | `swe_agent_v2.yaml` → `params["max_tokens"]`（:95）| 受剩余预算约束 |

### 5.2 `exit_code` 语义表（模型实际看到的世界）

| 码 | 含义 | 产生位置 |
|---|---|---|
| 0 | 成功 | — |
| 1 | 命令执行但失败（测试挂/断言错）| 沙箱内命令的真实退出码 |
| 2 | **未执行**：语法预检拦截 / 命令非法 | `episode.py:196`（长度/空）或 `:214`（`bash -n` 预检）|
| 124 | 超时（60s）| 沙箱内 `timeout` 命令 |
| 125 | 管道/环境异常（drain 崩溃）| `episode.py:220`（`PIPESTATUS[1]` 非零）|
| 127 | 命令不存在（散文被执行）| 沙箱 bash |

## 6. 错误处理与降级路径（代码级）

| 异常/失败 | 捕获位置 | 落盘 | 对训练的影响 |
|---|---|---|---|
| 沙箱创建超时（90s）| `ags_instance.py:200` 抛 `TimeoutError` | `record["error"]`（:233-236）| 该 episode 异常退出 → verl 侧重采样 |
| 云 SDK 缺失/凭证失败 | 无捕获，直接抛 | 同上（含真实报错文本）| 同上（v1 启动期实录：10 条）|
| 模型输出无有效命令 | **非异常**：`parse_action` 抛 `ValueError` → 捕获（:129-130）| `kind=format_error`，`exit_code=2` | 记一次"无效轮次"，继续循环 |
| SUBMIT 但操作 <3 次 | 非异常：驳回并追加提示（:121-128）| 步骤记录保留 | 防"未编辑就提交" |
| 补丁被安全校验拒绝 | `check_patch` 抛 `ValueError` → 捕获（:180-182）| `failure_kind=candidate_rejected` | **0 分**，跳过判分（省一次沙箱）|
| 判分基础设施失败 | `evaluate_patch` 抛异常 → 捕获（:195-208）| `failure_kind=judge_error` + 打印 `swe_judge_error` 事件 | **0 分但不崩训练**（否则 Ray Traceback 会触发流水线 fatal 停机）|
| 连续 token 超预算 | `RuntimeError`（:218）| `record["error"]` | 异常退出（v2 预算翻倍即为消除此路径）|
| 轨迹中进程被杀（OOM）| 无代码参与 | 目录残留部分文件（每轮 `atomic_json` 已落盘）| 已完成步骤不丢，可事后审计 |

## 7. 可观测与证据链（落盘点清单）

**`atomic_json` 三处调用**（原子写：临时文件 + `fsync` + `os.replace`，`episode.py:25-33`）：

| 落盘 | 时机 | 频率 | 内容 |
|---|---|---|---|
| `episode.json` | **每轮循环后**（:143）| 每条 episode ≤16 次 | 全部步骤 + 沙箱三件套 + token_alignment（收尾时 :221）|
| `agent/execution.json` | 沙箱关闭时（`episode.py:273-277`）| 每条 episode 1 次 | 命令级档案 + `cleanup_error` |
| `judge/result.json` | 判分完成（`episode.py:360`）| 每条 episode 1 次 | 奖励 + 逐用例清单 + `patch_sha256` |

**实时 JSON 事件**（stdout，供训练日志采集）：
- `{"event": "swe_episode_complete", ...}`（:237-240）——轨迹完成（题号/步数/操作数/奖励）；
- `{"event": "swe_judge_error", ...}`（:200-204）——判分异常（不崩训练但留痕）。

**与 verl 的指标对接**：`metrics = {"generate_sequences", "tool_calls", "compute_score"}`（:80）随 `AgentLoopOutput` 回传，进入 `timing_s/gen` 等训练指标。

## 8. 训练 / 评估同源复用（eval_driver 对照）

| 组件 | 训练路径 | 评估路径（`controller/eval_driver.py`）| 是否同一份代码 |
|---|---|---|---|
| 沙箱会话 | `EpisodeSession`（`swe_agent_loop.py:67`）| `EpisodeSession`（`eval_driver.py:107`）| ✅ 同 |
| 动作协议 | `parse_action` / `bounded_observation` | 同（`eval_driver.py:35`）| ✅ 同 |
| 判分 | `evaluate_patch`（`swe_agent_loop.py:191`）| `evaluate_patch`（`eval_driver.py:201`）| ✅ 同 |
| 实例表 | `load_instances` | 同（`eval_driver.py:37`）| ✅ 同 |
| 推理引擎 | verl 内嵌 vLLM（colocate）| 独立 vLLM 进程 + LoRA 在线加载（`LoRARequest`）| ❌ 不同（部署形态）|
| 轨迹目录 | `traces/<run>/train/step-N/...` | `traces/<run>/vllm[-pass4]/<iid>__sK/` | ❌ 不同（命名空间）|

> **同源的意义**：训练奖励与评估奖励出自**同一 `compute_reward`**——
> 训练通过率与评估 pass@k 的差异只可能来自"题目不同 / 采样不同"，
> 不可能来自"判分器不同"（这是本项目经得起 A/B 对照的代码基础）。

---

## 附录 A · 关键函数索引

| 函数 | 位置 | 职责 |
|---|---|---|
| `SWEAgentLoop.__init__` | `swe_agent_loop.py:29-38` | 实例表加载 / 参数 / 并发闸门 |
| `SWEAgentLoop.run` | `:39-41` | 信号量包裹入口 |
| `SWEAgentLoop._episode` | `:43-246` | 单条 episode 全生命周期（核心）|
| `EpisodeSession.start` | `episode.py:124-191` | 建沙箱 + 四道自检 + 快照 |
| `EpisodeSession.run` | `:193-231` | 5 层包装 + e2b 执行 + 命令记账 |
| `EpisodeSession.export_patch` | `:233-246` | 相对原始树导出补丁 |
| `EpisodeSession.changed_files` | `:248-263` | 改动清单（与补丁互证）|
| `EpisodeSession.close` | `:265-279` | kill + execution.json 落盘 |
| `evaluate_patch` | `:282-367` | 独立沙箱判分（含 baseline-control）|
| `check_patch` | `:48-64` | 补丁安全校验 |
| `prepare_eval_script` | `:67-105` | 官方 eval.sh 改写（pip→导入自检）|
| `atomic_json` | `:25-33` | 原子落盘 |
| `start_instance` / `stop_instance` | `ags_instance.py:179-221` | AGS 创建 / 销毁 |
| `_client` / `_current_credential` | `:161-176 / :150-158` | SDK 客户端 / 凭证 |
| `_oauth_refresh` (+retry) | `:85-110 / :60-72` | OAuth 两步刷新 + 退避 |
| `load_instances` / `Instance` | `harness.py:64-101 / :32-56` | 实例表 |
| `grade` / `compute_reward` | `harness.py:188-215 / :217-224` | 逐用例判分 / 奖励比例 |
| `parse_action` / `classify_operation` / `bounded_observation` | `action_protocol.py:5 / :55 / :76` | 动作协议 |
| `compute_score` | `reward.py` | 奖励函数（消费 trusted 判分）|

## 附录 B · 一页纸调用链（打印备用）

```
【一步训练 · rollout 阶段 · 641s】
 AgentLoop.run
  └─ _episode                                    swe_agent_loop.py:43
      ├─ 路由校验 / 目录 / record 骨架            :40-65
      ├─ [A] session.start()                     :85   → episode.py:124
      │      start_instance → StartSandboxInstance + 轮询   ags_instance.py:179
      │      Sandbox.connect(instance_id)               episode.py:134
      │      四道自检 + 工作树快照                        episode.py:143-190
      ├─ [B] for turn in range(16):              :89
      │      generate → ct_merge_assistant_token  :97 / :103
      │      decode → parse_action                :108 / :114
      │      session.run(cmd, 60)  ──► AGS 执行   :116
      │      observation → bounded_observation    :117 / :159
      │      steps.append → atomic_json(episode)  :138 / :143
      │      ct_merge_context_msg                 :162
      ├─ [C] export_patch → check_patch           :181 / episode.py:233
      │      changed_files → session.close        :179 / :183
      └─ [D] evaluate_patch（第二沙箱）            :191 → episode.py:282
             git apply → swe-eval.sh → test.log → result.json
      └─ AgentLoopOutput（token 对齐 + reward）    :224-231

【一步训练 · 训练阶段 · 140s】（AGS 不参与）
 old_log_prob 31s → ref 30s → adv 0.06s → update_actor 75s → update_weights 3.4s
```

---

> **维护提示**：本文所有行号以 2026-09-23 的 main 分支为准；
> 修改 `swe_agent_loop.py` / `episode.py` 后请同步更新 §2 与附录 A。
> 已知数字勘误：① 早期文档中的"命令超时 120s"实为 **60s**（本文以代码为准，见 §5.1）；
> ② 早期文档混用 step 6/11 两行日志，导致"生成占 88.7% / update 26s"有误——正确值见 §4 表（82.1% / 75.4s）。
