# 01 · 历次训练运行复盘（Runs Postmortem）

> 从零到 30B-MoE 完成：7 次训练运行的时间线、终止根因、转折点。
> 每条为「现象 → 根因 → 修复 → 沉淀」四段式；细节可跳转对应专题文档。

---

## Run 1 · round0-train（7B，2026-09-11）

**现象**：训练 8 步，`critic/score/max=0.0`、`advantages/max=0.0`、`grad_norm=0.0`——指标全零。

**根因**：**算法正确行为，不是缺陷**。GRPO 组内奖励全相同 → 优势恒 0。7B 模型在 12 道题上做不到任何一题（reward 全 0），且训练批次未覆盖全部题目（组内采样不足）。
经六步诊断路径（只读取证 + CPU 隔离回放）确认：奖励链路（judge → rm_scores → GRPO scores）逐段正确；评分器区分度 9/9 通过（baseline=0、golden=1）。

**修复**：
1. 训练批次设为全题数（`train_batch_size = 题数`），确保每组覆盖不同题目；
2. `rollout.n ≥ 4` 保证组内多样性；
3. 接受"模型太弱 → 无信号"的物理事实，启动模型升级路线（7B → 14B → 30B）。

**沉淀**：
- 零奖励的排查顺序：`critic/score/max` 是否为 0 → 是则模型没解出任何题（不是框架 bug）；`score>0 但 adv=0` 才是链路问题。
- 教学案例：见 [05-data-judging.md §1](05-data-judging.md)。

---

## Run 2 · recovery-14b-adapter-v2-warmup（14B，2026-09-11）

**现象**：warmup 2 步后终止：pipeline `status=stopped, fatal_log=true`；判分器抛 `RuntimeError`。

**根因**：**判分器对模型产出的坏补丁不健壮**——Django 类仓库的补丁引入 `SystemCheckError`（框架级启动失败），官方 log parser 无法解析非常规输出 → 判分器崩溃 → 流水线 fatal-log 检测终止整个运行。

**修复**：判分器三级降级（`sandbox/harness.py` / `episode.py`）：
1. 语法/收集/框架级失败（有"无补丁对照"确认）→ `failure_kind=candidate_collection_or_import_error`，**记 0 分**；
2. 残余判分异常 → `failure_kind=judge_error`，**降级 0 分样本**；
3. 任何情况**不中断训练**。

**沉淀**：RL 训练里"坏补丁"是常态而非异常——判分器必须把"解析失败"定义为 0 分而不是崩溃。

---

## Run 3/4 · recovery-14b-fullbatch-v2 / v3（2026-09-12/13）

**现象**：**首次出现正奖励**（v2 step-1 `django__django-12286` 组内 `[0,1,0]`；v3 step-1 `[0,1,1,1]`），但运行仍在 step-1 更新前被终止。

**根因**：与 Run 2 相同——同组内有一条样本因判分器 RuntimeError 被丢弃，随后 fatal-log 终止。**"有信号但没来得及更新"是最可惜的失败模式**。

**修复**：同 Run 2（降级修复）+ 补充验证：修复后用隔离回放重建了全部历史分组，确认"若判分降级在位，v2/v3 的 step-1 更新都能发生"。

**沉淀**：
- 诊断"有信号却无更新"三步法：① 重建真实组内奖励（从轨迹）→ ② 隔离回放优势计算 → ③ 对比日志时间线找终止点。
- 诊断报告全文：`artifacts/grpo-diagnosis-20260911/REPORT.md`。

---

## Run 5 · swegym-7b-tier0-r1（7B + SWE-Gym 简单题，2026-09-17，23/50 步）

**现象**：104 分钟完成 23 步（手动终止）；305 条轨迹中 **303 条 0 分、2 条满分（0.7%）**；step 1 全零（符合预期）。

**根因**：**模型能力瓶颈**。管道全链路正常（2 条满分轨迹 + 非零梯度 1.2~6.1 + 优势 1.5 均已验证）。7B 模型在"Easy 档"题目上的天花板 ≈ 1%，GRPO 信号密度不足（每 ~10 步才有 1 次有效组）。

**修复**：
1. 短期：接受信号稀疏，继续跑通管道（工程验证价值）；
2. 根本解：**升模型**（后由 30B-MoE 实现，见 Run 7）。

**沉淀**：
- 小模型 RL 的瓶颈往往不是算法而是"做题能力下限"——组内全错 = 无梯度。
- 判断标准：若满分轨迹存在但稀疏 → 管道健康、能力不足 → 升模型；若**任何拓扑下 score/max 恒 0** → 查链路。

---

## Run 6 · swegym-9b-tier0-r1（Qwen3.5-9B 单卡，2026-09-18，未完成）

**现象**：启动阶段连撞 **十余项障碍**（详见 [04-training-engine.md](04-training-engine.md) / [06-agent-protocol.md](06-agent-protocol.md)）：镜像 digest 笔误、kit 数据不完整、多模态处理器文件缺失、thinking 模式、KV cache 不足、权重同步 OOM、`free_cache_engine` 顺序矛盾……最终换模型路线。

**根因（归纳）**：
1. **模型形态意外**：Qwen3.5-9B 是**原生多模态**（vision+language 混合）——单卡训练需 preprocessor 文件 + vLLM nightly 级支持；
2. **单卡 44GB 极限**：262144 原生上下文 → KV cache 8.1GB 需求于 0.45 利用率下不可满足；训练期 vLLM 不释放显存（`free_cache_engine` 默认未启用）；
3. **权重同步路径缺陷**：`update_weights` 需先唤醒 vLLM 再搬运全量参数（18GB+18.4GB≈44GB 贴线）。

**修复（逐项）**：digest 修正 / kit 补 instances+task_specs / HF 补 preprocessor 文件 / `enable_thinking=false` / `max_model_len=16384` / `free_cache_engine=True` / 逐单元 LoRA 导出（≤1.2MB）。最终因平台侧工具清空 + 模型形态过于特殊，**战略性放弃，转 30B-MoE + 4 卡**。

**沉淀**：选模型前先查**架构形态**（`config.json` 的 architectures / 是否有 vision_config）与 **vLLM 支持列表**——"看起来是语言模型"的模型可能是多模态混合体。

---

## Run 7 · swegym-30b-tier0-r1（Qwen3-Coder-30B-A3B，4×L20，2026-09-18/19）✅

**现象**：✅ **50/50 步完成**，21 小时，1692 条轨迹。中途经历一次 CPU 内存 OOM（286/300GB），修复后从 step 5 无损续训至完成。

**起步障碍（都在启动 1 小时内解决）**：
| 现象 | 根因 | 修复 | 详见 |
|---|---|---|---|
| `ModuleNotFoundError: tencentcloud` | 训练镜像未装云 SDK（镜像覆盖模式需要） | pip 加 `tencentcloud-sdk-python-ags` | [04 §5](04-training-engine.md) |
| `format_error` 率 45% | 模型输出"思考+```bash 块"被严格解析器拒绝 | 宽容解析（提取首个代码块） | [06 §1](06-agent-protocol.md) |
| OAuth 刷新 `RequestLimitExceeded` | 10 worker 并发刷新（23 次/秒 > 上限 20） | 跨进程文件缓存 + 退避重试 | [03 §4](03-sandbox-ags.md) |
| `RayTaskError(OutOfMemoryError)` | CPU 内存 286/300GB（vLLM 备份+双模型 offload+64Gi shm） | limit 350Gi / shm 32Gi / util 0.5 / workers 8 | [04 §2](04-training-engine.md) |

**成果**：奖励滑动平均 0.042→0.119（+183%）、best-so-far 0.281、157 条满分轨迹、零崩溃（修复后）。

**沉淀**：30B-MoE 单机训练的**最小可行配置**：4×L20（192GB 显存）+ **350Gi 内存**（≈3× 模型大小：vLLM 备份 100GB + actor 61GB + ref 61GB + shm 32GB）。

---

## 跨运行教训总结（Top 5）

1. **零奖励先分"算法正确"与"链路缺陷"**——`score/max` 是分水岭；
2. **判分器必须对坏补丁免疫**（降级 0 分，不中断）——这曾让两次"有信号"的运行功亏一篑；
3. **RL 的瓶颈常是模型能力下限**（组内全错 = 无梯度）——先用双向验证保证题目质量，再谈算法调参；
4. **单卡/单机的资源账要按峰值算**（内存 ≈ 3× 模型）；留 15%+ 余量；
5. **每一步都留可续训的检查点**（LoRA-only 每 5 步）——OOM 之类的中断从"灾难"变成"插曲"。
