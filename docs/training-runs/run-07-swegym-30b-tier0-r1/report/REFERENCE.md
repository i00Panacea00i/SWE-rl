# 资产引路（REFERENCE）— swegym-30b-tier0-r1

> 归档包本体（本目录）为文档与指标数据；**大体积资产（权重/轨迹/数据）保存在 CFS 下列路径**。
> CFS: `cfs-<id>`（挂载点 10.0.0.x，VPC vpc-<id>）

## 1. 模型权重

| 资产 | CFS 路径 | 说明 |
|---|---|---|
| **最终 LoRA（step 50，FSDP 分片）** | `/mnt/cfs/swe-rl/checkpoints/swegym-30b-tier0-r1/global_step_50/actor/` | `model_world_size_4_rank_*.pt`（4 分片）+ optim/extra_state（可续训） |
| **最终 LoRA（标准 HF adapter）** ✅ 推荐推理用 | `/mnt/cfs/swe-rl/checkpoints/swegym-30b-tier0-r1/global_step_50/actor/hf-adapter/` | `adapter_model.safetensors`（53.5MB）+ `adapter_config.json`（peft/vLLM 直接加载） |
| 全部中间检查点（每 5 步） | `/mnt/cfs/swe-rl/checkpoints/swegym-30b-tier0-r1/global_step_{5..50}/` | 每个 166MB（LoRA only） |
| 基座模型 | `/mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct/` | 16 shards / 61.1GB（已有 index 对照校验） |
| LoRA 分片 → HF adapter 转换脚本 | `/mnt/cfs/swe-rl/tools/convert_lora_to_hf.py` | `torchrun --nproc_per_node=4 convert_lora_to_hf.py <actor-dir> <out-dir>` |

**本地归档副本**（本目录 `checkpoint-lora/`）：step_50 actor 全套 + hf-adapter（SHA256 已核对）。

## 2. 训练数据

| 资产 | CFS 路径 |
|---|---|
| 训练/评估 parquet | `/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r1/kit/data/tier0-r2/{train,eval}.parquet`（20 训练 / 2 评估） |
| 实例清单（含 image_tcr） | `/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r1/kit/data/instances.jsonl`（22 题） |
| 题面 spec（eval.sh/gold.patch/tests.json） | `/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r1/kit/data/task_specs/`（22 题） |
| 冻结代码包（173 文件 + 校验和） | `/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r1/kit/`（`protocol.sha256`） |
| 题目镜像（22 个） | TCR `registry.example.com/swe-mirror/swe-ags:*` |

## 3. 轨迹与日志

| 资产 | CFS 路径 |
|---|---|
| 完整轨迹（1692 条 episode：步骤/补丁/判分/证据） | `/mnt/cfs/swe-rl/traces/swegym-30b-tier0-r1/`（含 train/step-0..50） |
| 训练日志（原始） | 本目录 `metrics/train-full.log`；CFS: `/mnt/cfs/swe-rl/logs/swegym-30b-tier0-r1/` |

## 4. 云端备份（COS）

| 项 | 值 |
|---|---|
| 存储桶 | `big-data-test-1437615650`（ap-guangzhou） |
| 路径 | `swe-rl-archive/swegym-30b-tier0-r1/` |
| 内容 | **完整归档 36 对象 / 203.54 MB**（文档+图表+指标+LoRA 权重+HF adapter） |
| 上传 | `tccli cos upload --bucket big-data-test-1437615650 --local_path <归档目录> --cos_key swe-rl-archive --recursive true --region ap-guangzhou` |
| 备注 | 大文件（>10MB）建议 `--part_size 1 --retry 10` 提高跨区稳定性 |

> 三副本冗余：**COS**（本表）+ **CFS**（§1-3 路径）+ **本地开发机**（`artifacts/archive/`）。

## 5. 恢复推理（vLLM 示例）

```python
from vllm import LLM
from vllm.lora.request import LoRARequest

llm = LLM(model="/mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct",
          enable_lora=True, max_model_len=16384, tensor_parallel_size=4)
lora = LoRARequest("swe-rl-s50", 1,
                   "/mnt/cfs/swe-rl/checkpoints/swegym-30b-tier0-r1/global_step_50/actor/hf-adapter")
```

或 peft：

```python
from peft import PeftModel
from transformers import AutoModelForCausalLM
base = AutoModelForCausalLM.from_pretrained("/mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct")
model = PeftModel.from_pretrained(base, ".../global_step_50/actor/hf-adapter")
```

## 6. 复现训练

1. 取冻结包：`/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r1/kit/`（`sha256sum -c protocol.sha256`）；
2. 复现环境：见 `README.md` §1（沙箱）与 §2（TKE 部署）；
3. `VERL_RESUME_MODE=auto` 从 step 50 续训 / `disable` 全新训练。
