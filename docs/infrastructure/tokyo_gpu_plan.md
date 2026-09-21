# 训练侧方案（TKE ap-tokyo GPU 适配）

> **⚠️ 本文档已被 `docs/overview/training-architecture-overview.md` 取代**（2026-09-10 确定为
> ap-tokyo-2 固定节点 2×L20 + Qwen3-Coder-30B-A3B + LoRA-GRPO）。
> 本文保留作为跨区链路分析的背景材料（§0 的时延评估仍然有效）。

> 前提：沙箱/数据链路（ap-singapore AGS + TCR）已就绪；GPU 资源在东京 TKE。
> 跨区要点：**镜像跨区拉取（东京←新加坡 TCR）** 与 **AgentLoop 跨区调用沙箱（东京→新加坡 AGS）**。

## 0. 跨区链路与时延评估

| 链路 | 方案 | 影响 |
|---|---|---|
| 东京节点 ← TCR(singapore) | TCR 企业版公网 endpoint + imagePullSecret；节点侧有镜像缓存，仅首次慢 | 仅影响首次拉取（~1GB/镜像） |
| 东京 Pod → AGS(ags.example.com) | 公网直达（AGS 数据面为公网域名） | RTT ~70-100ms/命令；沙箱命令本身秒级，占比可接受；rollout 并发 4 沙箱时影响更小 |
| 东京 Pod → HuggingFace | 直连下载模型/数据到 CFS | 一次性 |
| 沙箱 → TKE 内网 | 不需要（调用方向是 TKE→沙箱；README 已知坑 #6 在 AGS 公网方案下自动满足） | — |

## 1. 集群与存储（ap-tokyo）

1. GPU 节点池：CC ≥ 8.0（A10/4090/L40S；**T4/V100 不可用**），驱动 ≥535、CUDA ≥12.x
2. 组件安装：CFS CSI（建 StorageClass `cfs-ai`）
3. `kubectl apply -f deploy/pvc.yaml`（CFS PVC，存模型+数据+checkpoint）
4. 镜像拉取凭证（跨区）：

```bash
# 用 TCR 临时登录指令（1h 有效）创建 secret
kubectl create secret docker-registry tcr-sg \
  --docker-server=tcr.example.com \
  --docker-username=<临时用户名> --docker-password=<临时密码>
```

5. 训练镜像：`verlai/verl:vllm-latest` 推到 TCR `swe-mirror/verl-train`（叠加 verl_plugin/），
   东京节点经 imagePullSecret 拉取

## 2. 数据与模型（CFS 内目录布局）

```
/mnt/cfs/swe-rl/
├── data/train.parquet        # data/prepare_data.py 产物
├── model/Qwen2.5-Coder-3B-Instruct/
└── traces/                   # episode 存档（验收证据）
```

## 3. GRPO 训练提交

`deploy/train-pod.yaml`（骨架已建）+ `configs/grpo_a10_lora.sh`（超参按 README §4）：

```bash
kubectl apply -f deploy/pvc.yaml
kubectl apply -f deploy/train-pod.yaml
kubectl logs -f swe-rl-train -f
```

关键点（README §4 已定，东京版补充）：
- `rollout.n=4`：每题并发 4 沙箱 → AGS 侧同时 4×10 实例上限，创建前确认配额
- AgentLoop 通过 env `E2B_API_KEY` / `E2B_DOMAIN`（Secret 注入，不落 Pod spec 明文）
  调用 ap-singapore 数据面；沙箱路由 = extra_info.tool_name（1 工具/题）
- reward = `rm_scores`（fail→pass 执行反馈，sandbox/harness.grade 判定）

## 4. 时序与验收（等 GPU 就绪后）

1. Round 0：`val_before_train` 自动产出基线 pass rate（30 题 = 全部 10 题 × 3 次或含 flaky 题单列）
2. 训练 50 steps（reward 曲线 wandb `swe-rl-grpo`）
3. `model_merger` 合并 LoRA → vLLM 评估 pass@1 → 对比报告
4. 注意：sympy-11384 已判 flaky，**不进训练集**，评估报告单列避免污染指标

## 5. 已知风险

- 跨区公网 RTT 使 rollout 有效吞吐下降（预估 10-20%）；若不可接受，
  备选：AGS 是否有东京地域数据面（控制台确认），仅改 `E2B_DOMAIN`
- TCR 跨区拉取走公网带宽，镜像大（verl 全家桶 ~15GB）；建议先在东京节点
  手动 `docker pull` 预热或使用节点池自定义镜像
