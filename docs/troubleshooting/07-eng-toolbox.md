# 07 · 工程工具箱（Eng Toolbox）

> 大文件传输、跨区上传、YAML/heredoc、Pod 运维、兼容性与诊断——可复用的工程技巧沉淀。

---

## 1. kubectl cp 大文件截断 → 1MB 分块 + SHA 校验 ⭐

**现象**：集群 → 开发机传输 ~50MB+ 文件反复失败：
```
error: error reading from error stream: read tcp …: connection reset by peer
```
`kubectl cp` 每次"成功"退出但文件大小不一（36.8MB / 30.1MB / 70.3MB…）——**静默截断**。

**根因**：公网链路对长连接大流量不稳；`kubectl cp` 无断点续传且错误退出码不可靠。

**修复（分块传输协议）**：
```bash
# 远端：切块
remote$ split -b 1m big.safetensors part-
# 本地：逐块拉取（每块重试 3 次 + 大小核对）
for p in part-*; do
  for try in 1 2 3; do
    kubectl cp svc:/path/$p /tmp/parts/$p
    [ "$(stat -c %s /tmp/parts/$p)" = "$(remote_size $p)" ] && break
    sleep 1
  done
done
# 合并 + 终检
cat part-* > big.safetensors && sha256sum big.safetensors   # 与远端比对
```
实测：8MB 块失败率>50%，**1MB 块 52/52 全部成功**。

**沉淀**：
- 跨公网传大文件：**块 ≤ 1MB + 逐块大小校验 + 合并后 SHA256 终检**；
- 永远不要相信 `kubectl cp` 的退出码——**用大小/SHA 说话**。

---

## 2. COS 跨区大文件上传分片失败（同源问题的对象存储版）

**现象**：
```
Error: some upload_part fail after max_retry, please upload_file again
```
跨区（东京→广州）上传 204MB 归档时，29/36 对象成功，7 个大文件（13-53MB）全挂。

**根因**：tccli 默认分片较大 + 默认重试次数少 + 跨区链路抖动。

**修复（降级策略）**：
```bash
# ✅ 有效的参数组合（按文件逐个上传，失败重试 3 轮）
tccli cos upload --bucket <bucket> --local_path <file> --cos_key <key> \
    --part_size 1 --thread_num 3 --retry 10 --region ap-guangzhou
```
- `--part_size 1`（MB 级分片）· `--thread_num 3`（降并发）· `--retry 10`；
- 逐文件循环 + 每文件 3 轮重试（脚本见项目历史）；
- 完成后 `tccli cos list` 对账对象数与大小。

**沉淀**：跨区上传 = 小分片 + 低并发 + 高重试 + **逐文件粒度重试**（整体命令一挂全挂）。

---

## 3. YAML 里的 heredoc 陷阱 → 脚本落盘执行

**现象**：在 K8s Pod 清单 `args` 里嵌 `cat > script.py <<'EOF'`——脚本缩进错误 / heredoc 不闭合 / 命令神秘行为。

**根因**：YAML 块标量要求统一缩进，缩进会**原样进入 heredoc 内容**（Python 顶层缩进 → `IndentationError`）；结束标记 `EOF` 带前导空格 → **heredoc 永不结束**。

**修复**：**脚本落盘 CFS，Pod 直接执行**：
```bash
# 1) 本地写脚本 → 经 sync pod 上传到 CFS
cat controller/convert_lora_to_hf.py | kubectl exec -i swe-rl-sync -- \
    sh -c 'cat > /mnt/cfs/swe-rl/tools/convert_lora_to_hf.py'
# 2) Pod 清单 clean 引用
command: ["torchrun", "--nproc_per_node=4", "/mnt/cfs/swe-rl/tools/convert_lora_to_hf.py", ...]
```

**沉淀**：任何 >5 行的逻辑都不进 YAML——**脚本文本文件化管理**（可 review、可版本控制、可复用）。

---

## 4. Pod 生命周期运维小坑

| 现象 | 根因 | 修复 |
|---|---|---|
| `cannot exec into a container in a completed pod` | sync Pod 是短命 Pod，命令跑完即退出 | 访问前 `delete --wait=true` + `apply` + `wait --for=Ready` 三步重启 |
| apply 后 Pod 没出现 / 立即消失 | `delete`（异步）与 `apply` 竞态 | delete **加 `--wait=true --timeout`** 等确认后再 apply |
| 极简镜像 `exec: "bash": not found` | 镜像只有 `sh`（BusyBox） | 命令改 `sh -c`；需要 python 的运维 Pod 换 `python:3.11-slim` |
| `nvidia-smi` Pod 看不到 GPU | 未声明 `resources.limits: nvidia.com/gpu` | 显式声明 GPU 资源 |

**沉淀**：Pod 运维三原则——**先 wait 后 apply**；**交互容器不等于目标镜像**（选基础镜像要看工具链）；**一切操作幂等化**（脚本可重跑）。

---

## 5. 兼容性验证——"5 分钟冒烟"模式

**场景**：换模型（Qwen3-Coder-30B-A3B）前，要确认 vLLM 支持其架构。

**方法（无 GPU 也能验）**：
```python
# 在已缓存训练镜像的节点上跑一枚小 Pod（cpu only）
from vllm.model_executor.models.registry import ModelRegistry
archs = ModelRegistry.get_supported_archs()
assert "Qwen3MoeForCausalLM" in archs          # 架构级断言
import vllm.lora; print("VLLM_LORA_IMPORT_OK") # LoRA 路径断言
```
一并输出 `vllm.__version__` / `torch` / `transformers` 版本谱系。

**沉淀**：
- **架构兼容性不靠文档猜**——`ModelRegistry` 是唯一权威；
- 同类冒烟还有：镜像功能验（`import vllm`）、模型文件验（index 对照）、沙箱链路验（4.2s 创建+命令）。
- 这些"5 分钟冒烟"把 8 分钟起步的训练失败循环挡在门外。

---

## 6. 诊断脚本化（把排查变成工具）

项目沉淀的诊断工具链（`controller/`）：

| 脚本 | 用途 |
|---|---|
| `parse_metrics.py` | 训练日志 → 逐步指标 CSV（45 步 × 21 字段）|
| `parse_traces.py` | 轨迹批量解析 → 轨迹级 + 分步聚合 CSV（协议质量/奖励）|
| `plot_metrics.py` | matplotlib 报告图（奖励曲线 + 四联仪表盘）|
| `convert_lora_to_hf.py` | FSDP 分片 LoRA → 标准 HF adapter（torchrun 4 进程）|
| `watch_training.py` + 监控脚本 | 后台周期采样（步数/内存/轨迹数）落日志 |

**沉淀**：每次手工排查（数日志、拼命令）之后**立刻固化成脚本**——同一类问题第二次出现时从"小时级"变"分钟级"。

---

## 7. 后台任务模式（长任务的正确姿势）

**模式**（贯穿项目）：
```bash
nohup <长命令> > /tmp/job.log 2>&1 &
# 后续：tail -2 /tmp/job.log 看进度；ps aux | grep 确认存活
```
配合**幂等设计**（重跑自动跳过已完成）+ **落盘进度**（jsonl 追加）。

**反例（踩过的坑）**：前台跑批量命令被终端中断；`kubectl logs` 巨大时忘记 `--tail` 拉全量卡住。

**沉淀**：凡预估 >2 分钟的任务——**后台 + 日志文件 + 幂等重跑**三件套。
