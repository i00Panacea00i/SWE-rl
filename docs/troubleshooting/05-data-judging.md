# 05 · 数据与判分问题（Data & Judging）

> GRPO 零奖励诊断方法论、判分器鲁棒性、双向验证过滤（假阳性/flaky/坏题）、数据字段完整性。

---

## 1. GRPO 零奖励诊断（六步路径，可复用方法论）⭐

**现象**：`critic/score/max=0.0`、`advantages/max=0.0`、`grad_norm=0.0`——训练指标全零，连续多个运行出现。

**核心结论（先给判断标准）**：

| 观测 | 判定 |
|---|---|
| `score/max = 0` 且**所有题都做不出** | **算法正确**——模型能力不足（组内全错 = 无相对信号）|
| `score/max > 0` 但 `adv/max = 0` | **链路缺陷**——奖励传递/优势计算有问题 |

**六步诊断路径**（只读取证 + CPU 隔离回放，不修改训练）：

1. **确认是否真全零**：逐运行核对 `score/max`、`adv/max`、`grad_norm`（三个运行完全一致地全零 → 同构问题）；
2. **评分器区分度**：用已验证实例跑 baseline（期望 0）/ golden（期望 1）——9/9 通过 → 判分器能区分好坏；
3. **奖励传递对齐**：逐段核验代码链 `final["reward"]` → `rm_scores` → `extract_reward` → `token_level_scores` → GRPO `scores`；并用数字吻合验证（1/12 满分 → `reward/mean=0.0833` ✓）；
4. **重建真实组内奖励**：从轨迹文件重建每个组的原始分数序列——发现关键事实：**有信号的组确实存在**（如 `[0,1,0]`），但更新前运行被终止；
5. **隔离回放优势计算**：CPU 上跑冻结的 GRPO 函数——`[0,1] → [-0.707,+0.707]`、`[0,0] → [0,0]`（预期）——算法正确；
6. **找真正的终止点**：对比日志时间线——真正的凶手是**判分器 RuntimeError 触发的 fatal-log 终止**（见 §2）。

**最终定性**：已记录的零优势步是**正确的算法结果**（模型确实全错）；而"有信号却无更新"的运行死于判分器崩溃。

**沉淀**：
- 零奖励问题必须**先分"能力问题"与"链路问题"**再动手（`score/max` 分水岭）；
- 诊断方法论本身值得复用：**只读取证 + 数字吻合验证 + 隔离回放**（不动生产环境）。

---

## 2. 判分器鲁棒性——三级降级（坏补丁 ≠ 崩溃）

**现象**：模型产出的补丁引入 Django `SystemCheckError`（框架级启动失败）→ 官方 log parser 解析失败 → 判分器抛 `RuntimeError` → **流水线 fatal-log 检测终止整个训练运行**。

**根因**：判分器假定"eval.sh 总能产出可解析日志"；但 RL 早期模型的补丁是"任意程序"，收集失败/导入错误/框架异常全是常态。

**修复（三级降级，见 `sandbox/harness.py` / `episode.py`）**：
1. 语法/收集/框架级失败 → 先跑**无补丁对照**确认是候选补丁引起 → `failure_kind=candidate_collection_or_import_error`，**记 0 分**；
2. 残余判分异常 → `failure_kind=judge_error`，**0 分样本**（不丢轨迹）；
3. 任何情况**不抛出、不中断**训练。

**沉淀**：
- RL 训练的判分器设计原则：**对"最坏的候选补丁"鲁棒**——判分失败 = 0 分信号，而不是系统故障；
- 该修复直接解锁了后续两次"有信号运行"的更新机会（修复前后对比见 [01 §Run3/4](01-runs-postmortem.md)）。

---

## 3. 环境双向验证（数据质量门禁）

### 3.1 假阳性题（baseline 就通过）

**现象**：无补丁的 baseline 沙箱里 F2P 测试**通过**（应全 FAIL）——题目"生来就是对的"，模型不做任何事也能拿分。
**修复**：验证门禁新增该检查——baseline 出现 F2P 通过 → `invalid / baseline_pass`，**剔除**。

### 3.2 Flaky 题（golden 结果不稳定）

**现象**：同一题 golden 补丁两次运行结果不一致（通过率 ~50%），如 `sympy__sympy-11384`。
**修复**：`--verify-runs 2`（golden 跑两次）——两次不一致 → `invalid / flaky`，剔除。

### 3.3 坏题（golden 也无法全过）

**现象**：golden 补丁应用后 F2P 仍失败（如 `conan-io__conan-11505`：4 个参数化测试中 2 个未过）。
**修复**：`invalid / f2p_fail` 剔除。**注意区分诱因**——若大量题突然 f2p_fail，先查"镜像未预热/创建竞态"（暂时性），而不是直接判死（见 [03 §2/§3](03-sandbox-ags.md)）。

### 3.4 数据质量结果（本项目统计）

| 指标 | 值 |
|---|---|
| 双向验证通过 | 22 题（进训练集）|
| 因假阳性剔除 | pylint-4551 等（baseline ImportError / 通过） |
| 因 flaky 剔除 | sympy-11384 |
| 因 f2p_fail 剔除 | 若干（含 conan-11505） |

**沉淀**：
- **"已验证"必须双向**（baseline 测假阳性 + golden×2 测可用性），单侧验证会放进假题；
- 验证失败要分"题目质量"与"平台暂时性"两类——**预热/竞态类失败必须重试后才能定性**。

---

## 4. 数据字段完整性（KeyError 链条）

**现象链**：
```
KeyError: 'image_env'            ← preflight 读 instances.jsonl 时
FileNotFoundError: task_specs/…  ← load_instances 找不到题面
Instance is not validated: …     ← prepare_data 校验门禁
```
**根因**：数据管线三段（instances.jsonl / parquet extra_info / task_specs）来源不一致——第一次构建 instances.jsonl 时用了"验证产物"（缺 `image_env`），而 harness 需要原始池字段。

**修复**：统一构建脚本——**以原始池（含 image_env）为字段基底 + 验证记录（含 validation）为准入 + image_tcr 按规则生成**：
```python
r = dict(base_pool[iid])          # 含 image_env 等全字段
r["image_tcr"] = tcr_image_for(iid)
r["validation"] = validated_record["validation"]
```
并配套 `sha256sum -c protocol.sha256`（kit 完整性）+ `python -m sandbox.preflight`（路由一致性）双预检。

**沉淀**：
- 数据管线的字段来源必须**单一权威**（字段基底池 + 增量字段映射表）；
- 任何"手工拼过一份数据"的历史都要在启动前用**字段断言**扫一遍（`assert r.get("image_env")`）。

---

## 5. 判分口径统一（与 SWE-bench 官方对齐）

- **奖励** = F2P 通过数 / F2P 总数（0~1 连续）；
- **resolved** = F2P 全过 **且** P2P 无回归（与官方一致）；
- 测试日志解析用官方 marker（`>>>>> Start Test Output` / `End`）；
- 判分在**全新沙箱**执行（golden/agent/baseline 不共用沙箱——镜像内存在构建期未提交修改）。

**沉淀**：判分口径的每次放宽/收紧都要有回归测试（`tests/test_episode.py`），防止"宽到假阳性、严到误杀"。
