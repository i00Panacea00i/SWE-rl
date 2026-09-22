# 数据案例：swegym-30b-tier0-r1 训练轨迹（step-0/1/2 完整版）

30B 模型（Qwen3-Coder-30B-A3B-Instruct + LoRA r=32，GRPO）训练**前 3 个 step** 的
完整原始轨迹——未压缩、可直接浏览，用于行为分析、格式参考与调试复现。

> 全量归档（1692 条 / 67MB tar.gz）：`../../archive/cfs-traces-30b/swegym-30b-tier0-r1.tar.gz`
> 症状分类学研究：`../../../docs/validation/trajectory-symptom-study.md`

---

## 统计概览

| step | 轨迹 | 题 | 通过 | 空补丁 | 均轮次 | stop_reason 分布 |
|---|---|---|---|---|---|---|
| step-0 | 8 | 2 | 1 | 2 | 8.4 | step_budget:5, None:2, submit:1 |
| step-1 | 96 | 8 | 4 | 52 | 8.9 | step_budget:58, None:27, token_budget:8 |
| step-2 | 32 | 8 | 0 | 25 | 10.9 | step_budget:22, token_budget:6, submit:4 |

**早期症状读数**：空补丁率 step-1 54% → step-2 78%；均轮次 8.4 → 10.9（"越跑越能熬"）；
step-2 全败（8 题 × 4 采样 0 通过）——正对应症状学研究中的 S2（只读）/S4（试错）高发期。

---

## 目录结构

```
train/step-N/<instance_id>/<rollout_uuid>/
├── episode.json            # 完整对话（每步 action/observation/reward/token_ids）
├── candidate.patch         # 该 rollout 的最终补丁（0 字节 = 空补丁）
├── agent/execution.json    # 沙箱创建与执行记录
└── judge/
    ├── result.json         # 判分结果：f2p_passed / f2p_failed / reward / resolved
    ├── execution.json      # 判分命令执行记录
    └── test.log            # 判分测试输出（pytest）
```

## episode.json 关键字段

```jsonc
{
  "schema_version": ..., "run_id": ..., "episode_id": ...,
  "instance_id": "python__mypy-15131",     // SWE-Gym 题号
  "model": ..., "phase": "train", "global_step": 1, "split": "train",
  "started_at": 1789723680.47,             // 批次判定用（见下）
  "steps": [
    {
      "step": 1,
      "kind": "format_error",              // execute|inspect|test|edit|submit|format_error
      "action": "Looking at the issue...",  // 模型原始输出（常含散文）
      "executed_command": "",               // 实际执行的 bash（格式错误时为空）
      "observation": "Action format error; no command executed: Mixed prose/code fences...",
      "reward": 0.0, "done": false,
      "exit_code": 2,                       // 0=成功 1=测试失败 2=格式拦截 127=散文被执行
      "action_token_ids": [22464, 518, ...] // 模型输出 token IDs（训练级数据）
    }
  ],
  "stop_reason": "step_budget",             // submit|step_budget|token_budget|None(异常)
  "error": null
}
```

## 值得直接阅读的案例

| 路径 | 看点 |
|---|---|
| `step-0/python__mypy-15131/` | **同题 4 采样**：1 条成功、1 条 12 轮格式灾难（症状学研究 §S3 对照证据） |
| `step-0/conan-io__conan-14177/` | 空 episode（steps=0，沙箱创建失败样本） |
| `step-1/conan-io__conan-14397/` | 12 条中 9 条耗满 12 轮（step_budget 主导） |
| `step-1/*` | **每题 3 个 rollout 批次**（started_at 时间簇：1789723680 / 1789724218 / 1789725172，间隔 ~9min / ~16min）——训练中断恢复后重跑留下的完整记录 |

## 备注

- step-1 每题 12 条 = 3 批次 × 4 采样；step-0/2 为单批次 4 采样/题（step-0 仅 2 题进入轨迹）
- `candidate.patch` 为 0 字节时对应"空补丁"症状（幻觉提交 / 只读瘫痪的判分证据）
- 判分口径：f2p 全过 = resolved（reward=1.0）；部分过 = 小数 reward
