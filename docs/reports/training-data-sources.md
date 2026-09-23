# 训练数据来源说明（汇报版）

> **项目**：SWE-RL —— 面向真实软件工程任务的强化学习训练（Qwen3-Coder-30B-A3B + LoRA-GRPO）
> **版本**：2026-09-23 · 全部数据与规模均为系统实际清点结果，样例为原始文件真实片段
> **一句话结论**：训练数据 **100% 来自公开数据集与内部生成**——**无网络爬虫、无合作方数据、无个人隐私数据**。

---

## 一、数据来源总览表

| # | 来源渠道 | 数据类型 | 规模 | 用途 | 获取方式 | 许可证 |
|---|---|---|---|---|---|---|
| 1 | **SWE-Gym**（HuggingFace 公开数据集，Princeton NLP） | 真实 GitHub issue 题目 | 全量 2,438 实例 / 11 仓库；本项目入选 **180 题 / 9 仓库** | 训练题池 + 评估集 | 公开 parquet 导入 | **MIT** |
| 2 | **Qwen3-Coder-30B-A3B-Instruct**（阿里通义开源） | 基座模型权重（61GB / 16 分片） | 1 个 | 训练起点（LoRA 微调） | 官方发布下载 | **Apache 2.0** |
| 3 | **Qwen2.5-Coder-7B / 14B、Qwen3.5-9B**（阿里） | 基座模型权重 | 3 个 | 早期规模验证 | 官方发布下载 | Apache 2.0 |
| 4 | **SWE-Gym 官方沙箱镜像**（社区公开） | 可复现执行环境 | 180 个（每题一镜像） | 代码执行沙箱 | 转存至内部镜像仓库（TCR） | 公开镜像 |
| 5 | **内部生成**（本训练系统 rollout） | 模型交互轨迹 + 判分结果 | r1: 1,692 条 · 画像: 268 条 · r2: 1,186+ 条（进行中） | GRPO 强化学习训练样本 | 模型采样自动生成 | 内部生成 |
| 6 | **内部构建**（从公开数据衍生） | 任务判分规格 task_specs | 210 题 | 自动化判分与验证 | 从公开数据提取 | 内部衍生 |
| 7 | **内部划分** | 防泄漏评估集 | 40 题（与训练零重叠） | 独立效果评估 | 哈希划分 | 内部衍生 |

### 渠道类型核查（明确说明）

| 渠道类型 | 是否使用 | 说明 |
|---|---|---|
| 公开数据集 | ✅ **是**（唯一的外部数据源） | SWE-Gym（MIT）+ 开源模型权重（Apache 2.0） |
| 网络爬虫 | ❌ **否** | 未使用任何爬虫；题目来自公开数据集，代码来自数据集自带的 commit 快照 |
| 合作方提供 | ❌ **否** | 无第三方商业数据接入 |
| 内部生成 | ✅ **是** | 全部训练轨迹由本系统模型采样生成 |
| 用户隐私 / 个人数据 | ❌ **否** | 数据仅含开源仓库代码与 issue 文本，不含任何个人信息 |

---

## 二、数据分类说明

### 2.1 题目数据 —— 公开数据集（SWE-Gym）

- **来源**：HuggingFace `SWE-Gym/SWE-Gym`（2,438 实例、11 个仓库、**MIT 许可**）
- **构建方式**：由公开数据集的 PR 反向构造为训练题（issue 描述 → 对应修复 commit → 测试用例）
- **筛选链路**：
  1. **结构筛选**（FAIL_TO_PASS / PASS_TO_PASS 测试完整）→ 入选 **180 题 / 9 仓库**
  2. **镜像化**：每题构建独立沙箱镜像（见 2.3）
  3. **golden 双向验证**：镜像可启动 + gold patch 能使目标测试通过 → **22 题通过验证**
- **划分**：
  - **训练题池**：r1 = 20 题 → r2 = 18 题（经数据画像二次筛选）
  - **评估集（heldout）**：**40 题**，哈希划分，**与训练池零重叠**（防止数据泄漏）

**仓库分布**（180 题）：
```
Project-MONAI/MONAI            55 题
python/mypy                    41 题
iterative/dvc                  34 题
getmoto/moto                   18 题
pandas-dev/pandas              15 题
conan-io/conan                 10 题
pydantic/pydantic               4 题
dask/dask                       2 题
facebookresearch/hydra          1 题
```

### 2.2 模型权重 —— 开源模型

- **主训练模型**：Qwen3-Coder-30B-A3B-Instruct（MoE 架构，128 专家 / 激活 3B）
  - 许可证：**Apache 2.0**（模型目录内附完整 LICENSE 与模型卡标注）
- **训练方式**：**LoRA 微调**（rank 32，仅 attention 层 q/k/v/o）——**基座权重不被修改**，训练产物为独立的适配器（adapter，约 228MB）
- **早期验证模型**：Qwen2.5-Coder-7B / 14B、Qwen3.5-9B（同在 CFS 模型库）

### 2.3 沙箱执行环境 —— 镜像化（内部转存）

- **来源**：SWE-Gym 配套的公开评测镜像（`xingyaoww/sweb.eval.x86_64.*`）
- **内部化**：转存至内部镜像仓库（腾讯云 TCR），命名规则可追溯：
  ```
  公开镜像: xingyaoww/sweb.eval.x86_64.python_s_mypy-17256
  内部镜像: benchmark-upload-sicheng.tencentcloudcr.com/swe-mirror/swe-ags:python_s_mypy-17256
  ```
- **环境特性**：每题独立容器（预置仓库快照 @ 指定 commit + 测试依赖，**无外网访问**）

### 2.4 训练轨迹数据 —— 内部生成（RL 训练样本）

**生成方式**：模型在沙箱中通过"读代码 → 编辑 → 跑测试"多轮交互完成任务，系统逐步记录全量轨迹与判分结果。

**规模**（实际清点）：
| 数据集 | 规模 | 用途 |
|---|---|---|
| r1 训练轨迹（50 步） | **1,692 条** | 首轮 GRPO 训练 |
| 难度画像（67 题 × 4 采样） | **268 条** | 数据筛选（下一轮题池） |
| r2 冒烟 + 主训练（进行中） | 1,186+ 条 | 第二轮 GRPO 训练 |
| 评估轨迹（pass@1 / pass@4） | 400 条 | 独立效果评估 |

**数据特点**（每条轨迹 = 一次完整任务尝试）：
- **逐步四元组**：`(action, observation, reward, done)` —— 与 verl 训练框架 DataProto 严格对齐
- **token 级对齐**：`prompt_ids / response_ids / response_mask / response_logprobs`（覆盖率 98%，可直接重建训练张量）
- **判分结果**：FAIL_TO_PASS 通过清单（自动判分，无人工标注）

### 2.5 评估数据 —— 独立划分（防泄漏）

- **heldout 评估集 40 题**：与训练池**零重叠**（哈希划分规则固定，不随训练题替换而重抽）
- **评估协议**：独立 vLLM 推理（与训练解耦），每题 4 采样 × 温度 0.7，报告 pass@1 / pass@4

---

## 三、真实样例展示

### 样例 A · 题目数据（SWE-Gym，公开数据集）

```jsonc
// 文件: data/swe-gym-instances-tcr.jsonl（字段完整展示）
{
  "instance_id": "python__mypy-17256",
  "repo": "python/mypy",
  "base_commit": "cdc956bd209285b43cfca712902be2da04d133f9",
  "problem_statement": "Missing type narrowing with Literal[-1]\n```python\nfrom collections.abc import Callable\nfrom typing import Literal, TypeVar, Generic...",
  "image_ags": "xingyaoww/sweb.eval.x86_64.python_s_mypy-17256",
  "tool_name": "swe-mypy-17256",
  "version": "1.11",
  "source": "SWE-Gym"
}
```

另一题（不同仓库）：
```
[题号] iterative__dvc-9391
[仓库] iterative/dvc @ 6b6084a84829  [版本] 2.56
[问题描述] Being able to call `exp show` with multiple branches (`--rev`) and a number of
commits (`-n`) In the VS Code extension, we would like to show multiple branches...
```

### 样例 B · 任务判分规格（内部构建，从公开数据衍生）

```
data/task_specs/iterative__dvc-4817/
├── eval.sh        2634 B   官方评测脚本（提取测试命令）
├── test.patch     1772 B   测试补丁（判分前应用）
├── gold.patch     1288 B   参考修复（仅用于验证，训练中模型不可见）
├── tests.json      151 B   判分清单 ↓
└── task.yaml       151 B   任务元信息

tests.json 内容：
  FAIL_TO_PASS (2 项): ["tests/unit/command/test_imp.py::test_import",
                        "tests/unit/command/test_imp.py::test_import_no_exec"]
  PASS_TO_PASS (0 项)
```

### 样例 C · 训练轨迹（内部生成，真实片段）

```
目录规则: traces/<run_id>/<phase>/step-<N>/<题号>/<uuid>/episode.json
真实路径: traces/swegym-30b-tier0-r2/train/step-1/conan-io__conan-14362/<uuid>/episode.json
```

```jsonc
{
  "schema_version": 1, "run_id": "swegym-30b-tier0-r2",
  "instance_id": "conan-io__conan-14362",
  "model": "/mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct",
  "phase": "train", "global_step": 1, "split": "train",
  "steps": [
    {
      "step": 1, "kind": "inspect",
      "action": "Looking at the issue, I need to understand how CMAKE_SYSTEM_PROCESSOR is being set incorrectly for armv8 architectu...",
      "executed_command": "grep -n \"CMAKE_SYSTEM_PROCESSOR\" ...",
      "observation": "exit_code=0\n/testbed/conan/tools/cmake/toolchain/blocks.py\n...",
      "reward": 0.0, "done": false, "exit_code": 0,
      "action_token_ids": [22464, 518, ...]        // 模型输出 token（训练级）
    }
    // ... 后续轮次（最多 16 轮）
  ],
  "stop_reason": "submit",                          // submit | step_budget | token_budget
  "final": { "reward": 1.0, "resolved": true, "grade": {...} },
  "token_alignment": {                              // → VERL DataProto 对齐字段
    "prompt_ids": [2487 tokens], "response_ids": [5428 tokens],
    "response_mask": [...], "response_logprobs": [...]
  }
}
```

### 样例 D · 模型权重（开源模型，Apache 2.0）

```
模型目录: /mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct/
├── LICENSE               → "Apache License Version 2.0, January 2004"
├── README.md             → license: apache-2.0
├── config.json           → architectures: ["Qwen3MoeForCausalLM"], 128 experts
└── model-00001~00016-of-00016.safetensors   （16 分片，61GB）
```

---

## 四、来源合规性说明

| 数据 | 来源性质 | 许可证 / 依据 | 合规结论 |
|---|---|---|---|
| SWE-Gym 题目 | 公开数据集 | **MIT License**（HuggingFace 数据集页标注）；导入脚本 `data/import_swe_gym.py` 首行明确记录 | ✅ 允许使用与再分发 |
| Qwen3-Coder / Qwen2.5-Coder 权重 | 开源模型 | **Apache 2.0**（模型目录内 LICENSE + 模型卡） | ✅ 允许微调与商用 |
| 沙箱镜像 | 公开评测镜像内部转存 | 基于 SWE-Gym 官方公开镜像 | ✅ 内部使用 |
| 训练轨迹 / 判分数据 | **内部生成** | 无第三方版权（模型对开源仓库代码的交互产物） | ✅ 自有资产 |
| 评估集（heldout） | 内部划分 | 来自同一公开数据集，通过哈希划分与训练集隔离 | ✅ 无泄漏风险 |

**三条明确边界**（供汇报重点强调）：
1. **不使用网络爬虫**——所有题目来自公开数据集自带的 PR/issue 快照；
2. **不使用合作方或商业数据**——无第三方数据采买/接入；
3. **不含个人隐私数据**——数据仅涉及开源代码仓库的技术文本。

**数据隔离机制**：
- **训练/评估严格隔离**：heldout 40 题与训练池零重叠（哈希划分，`data/prepare_data.py` 内有 manifest 记录 sha256 溯源）
- **gold patch 不可见**：参考修复仅用于镜像验证与判分，训练中模型不可见（`gold_patch_visible: false` 每轨迹记录）

---

## 五、数据血缘链路（一图看清）

```
HuggingFace SWE-Gym（公开数据集，2,438 实例 / 11 仓库 / MIT）
        │  ① 结构筛选（F2P/P2P 完整性）
        ▼
180 题候选池（9 仓库）──────────► 沙箱镜像构建（公开镜像 → 内部 TCR）
        │  ② golden 双向验证（镜像启动 + gold patch 通过）
        ▼
22 题已验证 ──► r1 训练池 20 题  ──► 模型 rollout ──► 1,692 条轨迹 ──► r1 GRPO 训练（50 步）
        │                                        │
        │                          ③ 数据画像（base 模型 pass@4，268 条）
        ▼                                        ▼
r2 训练池 18 题（v1 信号 × 画像交叉筛选）──► rollout（r2，进行中）──► r2 GRPO 训练（70 步）
        │
        └──► 40 题 heldout 评估集（独立划分，零重叠）──► 独立 vLLM 评估（pass@1 / pass@4）
```

---

## 附录 · 关键文件索引（可现场取证）

| 数据 | 位置 | 说明 |
|---|---|---|
| 题目元数据（180 题） | `data/swe-gym-candidates.jsonl` / `data/swe-gym-instances-tcr.jsonl` | 含 `source: "SWE-Gym"` 标注 |
| 导入脚本（来源声明） | `data/import_swe_gym.py` | 首行注明来源、规模、MIT 许可 |
| 训练数据构建 | `data/prepare_data.py` | 生成 verl 标准 parquet（含 system prompt 哈希） |
| 任务规格（210 题） | `data/task_specs/<instance_id>/` | eval.sh / gold.patch / test.patch / tests.json |
| 训练轨迹 | CFS `/mnt/cfs/swe-rl/traces/<run_id>/` + GitHub 归档 | r1: 1,692 条（已归档 `artifacts/archive/cfs-traces-30b/`） |
| 模型权重 | CFS `/mnt/cfs/swe-rl/model/`（4 个模型） | LICENSE 与模型卡随权重分发 |
| 数据划分 manifest | `data/tier0-r2/manifest.json`（各 run） | split 规则 + 逐题 sha256 |

> **统计口径说明**：题目规模按 `instance_id` 计；轨迹按 `episode.json` 计（一次任务尝试 = 1 条，含多轮交互）；全部数字取自 2026-09-23 系统实际清点。
