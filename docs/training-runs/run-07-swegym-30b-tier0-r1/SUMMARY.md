# Run 07 · swegym-30b-tier0-r1（Qwen3-Coder-30B-A3B，4×L20）✅ 主成果

| 项 | 内容 |
|---|---|
| 日期 | 2026-09-18 ~ 09-19 |
| 模型 | Qwen3-Coder-30B-A3B-Instruct（MoE，激活 3B）+ LoRA（r=32, attention-only） |
| 硬件 | **4×L20（192GB 显存）+ 350Gi 内存**（单机） |
| 数据 | SWE-Gym tier0 已验证子集（20 题训练池） |
| 规模 | **50/50 步完成**，21 小时，1692 条轨迹 |
| 结果 | 奖励滑动平均 **0.042 → 0.119（+183%）**、best-so-far 0.281、157 条满分轨迹 |
| 状态 | ✅ **完成——项目主成果** |

## 目标
用 30B 级 MoE 突破 7B/14B 的能力下限（信号密度问题），跑通完整 RL 训练。

## 遇到的问题与解决方案（启动 1 小时内的 4 项障碍）

| 现象 | 根因 | 解决方案 |
|---|---|---|
| `ModuleNotFoundError: tencentcloud` | 训练镜像未装云 SDK（镜像覆盖模式需要） | pip 装 `tencentcloud-sdk-python-ags` |
| `format_error` 率 45% | 模型输出"思考 + ```bash 块"，严格解析器拒绝 | 宽容解析（提取首个代码块，见 06 §1） |
| OAuth 刷新 `RequestLimitExceeded` | 10 worker 并发刷新（23 次/秒 > 上限 20） | 跨进程文件缓存 + 退避重试 |
| `RayTaskError(OutOfMemoryError)`（CPU） | 内存 286/300GB（vLLM 备份 + 双模型 offload + 64Gi shm） | limit 350Gi / shm 32Gi / util 0.5 / workers 8 → **从 step 5 无损续训** |

## 关键工程决策
1. **镜像覆盖方案**：1 个通用工具（`swe-ags`）服务全部题目（配额 28→1）；
2. **LoRA-only 每 5 步检查点**：任何中断都从"灾难"降级为"插曲"（CPU OOM 实证）；
3. **独立评估数据**（与训练集不重叠）。

## 沉淀（最小可行配置）
30B-MoE 单机训练：4×L20（192GB 显存）+ **350Gi 内存（≈3× 模型大小）**：
vLLM 备份 100GB + actor 61GB + ref 61GB + shm 32GB。

## 产物
- `pod-manifest.yaml`（本次运行清单）
- `report/`（完整训练报告：README / REFERENCE / configs / metrics / figs）
- CFS：`checkpoints/swegym-30b-tier0-r1/`（step-50 LoRA adapter + merged 模型）、
  `traces/swegym-30b-tier0-r1/`（1692 条轨迹）
