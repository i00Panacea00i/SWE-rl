# SWE-RL Kit — 真实 Bug 修复的强化学习训练套件

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

基于 [SWE-bench](https://www.swebench.com/) 真实 GitHub issue，用 **GRPO 算法**训练 Qwen2.5-Coder 的 LoRA 适配器：模型在云沙箱（官方评测镜像）中用 shell 命令修复真实 bug，独立判分器按"修复了多少个原本失败的测试"打分，奖励经组内归一化驱动策略更新。

## 功能特性

- **沙箱执行协议** — 模型命令全部在远程沙箱执行（bash 语法预检、超时控制、输出限额、工作树快照、补丁导出），训练主机零接触模型输出
- **独立判分器** — 全新沙箱运行 SWE-bench 官方 `eval.sh` 协议，官方 log parser 解析；候选补丁引发的语法/收集/框架级失败稳健记 0 分，不中断训练
- **环境双向验证** — 每题 baseline×2（期望 0 分）+ golden×2（期望 1 分），未通过不进训练集
- **AgentLoop** — verl 框架插件：逐轮生成 → 沙箱执行 → 观察回填，逐轮原子落盘（崩溃不丢数据）
- **验收门** — 训练后自动检查：轨迹数 / 步数 / 组内奖励差异 / 非零梯度 / 检查点
- **可复现性** — 每次训练使用不可变代码快照（SHA256 清单）+ 冻结数据切分

## 技术栈

Python 3.11 · [verl](https://github.com/volcengine/verl) 0.10.0.dev · Ray · vLLM · FSDP · LoRA (PEFT) · Kubernetes · e2b 协议沙箱

## 目录结构

```
├── sandbox/        # 沙箱执行与判分（episode.py 判分器、harness.py 协议核心）
├── verl_plugin/    # verl 插件（swe_agent_loop.py、reward.py）
├── configs/        # 训练超参（grpo_l20_lora.sh）与 AgentLoop 配置
├── controller/     # 验收门 report_run.py、训练监视器、奖励曲线
├── tests/          # 单元测试（判分鲁棒性回归 × 9）
├── deploy/         # Kubernetes Pod 清单（训练/评估/验证/同步）
├── data/           # 实例元数据、官方协议 task_specs、冻结切分（parquet）
└── docs/           # RL 流水线技术报告
```

## 环境要求

- Linux（训练侧需 K8s 集群 + 2×GPU，如 2×L20 48GB；工具链侧普通机器即可）
- Python 3.11+、Docker（构建沙箱镜像）、kubectl、tccli（含 ags 模块 ≥3.1.164.1）
- 云资源：e2b 协议沙箱服务、容器镜像仓库、K8s 集群与共享存储

## 安装

```bash
python3.11 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
# verl 框架从源码安装（固定版本）
git clone https://github.com/volcengine/verl.git verl-src && pip install -e verl-src
```

## 配置

```bash
cp .env.example .env   # 填入你的沙箱服务地址与 API Key；密钥仅环境变量注入，绝不入库
```

| 变量 | 说明 |
|---|---|
| `E2B_API_KEY` | 沙箱服务 API Key |
| `E2B_DOMAIN` | 沙箱数据面域名 |
| `TCR_REGISTRY` | 镜像仓库地址（含命名空间） |

> 仓库中的 `tcr.example.com` / `ags.example.com` 均为占位符，请替换为你自己的资源地址。

## 测试

```bash
python -m unittest discover -s tests -v
```

## 运行（训练流水线）

```bash
# 1) 环境验证（每题 baseline×2 + golden×2，通过后才可进训练集）
kubectl apply -f deploy/validate-candidates.yaml

# 2) 训练前基线评估（可选）
kubectl apply -f deploy/eval-round0.yaml

# 3) warmup（2 步验证训练信号：组内差异 + 非零梯度 + 检查点）
kubectl apply -f <你的 warmup Pod 清单>

# 4) 正式训练（50 步，每 10 步存档 + 验证）
kubectl apply -f <你的 train Pod 清单>
```

## 判分口径

- **奖励** = F2P（fail-to-pass）测试通过数 / F2P 总数，0~1 连续值
- **resolved** 额外要求 P2P（pass-to-pass）无回归，与 SWE-bench 官方一致

## 轨迹结构（每条训练轨迹落盘）

```
traces/<run>/train/step-N/<instance>/<episode_id>/
├── episode.json        # 逐轮 action/命令/观察/退出码 + token 对齐 + 最终奖励
├── candidate.patch     # 模型产出的补丁
├── agent/execution.json# 该沙箱全部命令与耗时
└── judge/              # 判分原始日志与逐用例状态
```

## 常见问题

**Q：训练指标显示奖励/优势/梯度全为 0？**
GRPO 组内奖励全相同时优势恒 0（算法预期）。排查顺序：`critic/score/max` 是否为 0 → 是则模型未解出任何采样题；确认训练批次覆盖全部题目（`train_batch_size` = 题数）且 `rollout.n ≥ 4`。

**Q：判分器对模型产出的坏补丁抛异常？**
语法/收集/框架级启动失败（如 Django `SystemCheckError`）经无补丁对照后记 0 分（`failure_kind=candidate_collection_or_import_error`）；残余判分异常降级为 `failure_kind=judge_error` 的 0 分样本，均不中断训练。

**Q：沙箱路由错误（Untrusted sandbox route）？**
训练前运行 `python -m sandbox.preflight <train.parquet> <eval.parquet>`，预检 parquet 的 `tool_name` 与实例表一致性。

## 贡献指南

提交前运行 `python -m unittest discover -s tests`；判分逻辑变更必须附带 `tests/test_episode.py` 回归用例。

## 许可证

[MIT](LICENSE) © 2026 sicheng

## 致谢

- [SWE-bench](https://www.swebench.com/) · [verl](https://github.com/volcengine/verl) · [vLLM](https://github.com/vllm-project/vllm)

## 截图

<!-- TODO: 训练奖励曲线 / 流水线架构图 -->
