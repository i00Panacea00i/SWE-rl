#!/usr/bin/env python3
"""原生 LoRA 合并 —— 纯 torch + safetensors，不触碰 transformers 建模代码。

为什么要原生实现（而非 peft.merge_and_unload）：
  1. 镜像内 transformers 为 5.5.3（v5 重构版），HybridCache 等 4.x API 已移除，
     AutoModelForCausalLM 实例化 Qwen3-MoE 的路径不可靠；
  2. vLLM 0.24 不支持 Qwen3MoE 的 unpacked k_proj/o_proj LoRA（训练 adapter 为
     attention-only q/k/v/o 全模块）。
故直接做权重代数：W_merged = W_base + (alpha / r) * (B @ A)（fp32 累加，回写原 dtype）。

逐分片流式处理（峰值内存 ~2×分片大小），不依赖 GPU。

用法:
  python controller/merge_lora_native.py \
    --base /mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct \
    --adapter /mnt/cfs/swe-rl/checkpoints/swegym-30b-tier0-r1/global_step_50/actor/hf-adapter \
    --out /mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct-lora-step50
"""
from __future__ import annotations

import argparse
import json
import shutil
import time
from pathlib import Path

import torch
from safetensors import safe_open
from safetensors.torch import load_file, save_file


def log(msg: str):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def norm_module_path(key: str) -> str | None:
    """把任意前缀的 adapter/base key 归一化为 'model.layers....<proj>' 模块路径。

    例: base_model.model.model.layers.0.self_attn.q_proj.lora_A.default.weight
        → model.layers.0.self_attn.q_proj
    """
    if ".layers." not in key and not key.startswith("layers."):
        return None
    k = key[key.index("layers."):]          # layers.0.self_attn.q_proj.lora_A.default.weight
    k = "model." + k
    for tag in (".lora_A.default.weight", ".lora_A.weight",
                ".lora_B.default.weight", ".lora_B.weight"):
        if k.endswith(tag):
            return k[: -len(tag)]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    base, adir, out = Path(args.base), Path(args.adapter), Path(args.out)

    if (out / "model.safetensors.index.json").exists():
        log(f"输出已存在: {out}（如需重做请先删除）")
        print("MERGED_OK", out, flush=True)
        return

    cfg = json.loads((adir / "adapter_config.json").read_text())
    r, alpha = cfg["r"], cfg["lora_alpha"]
    scale = alpha / r
    log(f"adapter r={r} alpha={alpha} scale={scale} targets={cfg['target_modules']}")

    raw = load_file(str(adir / "adapter_model.safetensors"))
    log(f"adapter 张量数: {len(raw)}；样例 key:")
    for k in list(raw)[:2]:
        log(f"  {k}  {tuple(raw[k].shape)}")

    pairs: dict[str, dict] = {}
    for k, v in raw.items():
        mod = norm_module_path(k)
        if mod is None:
            continue
        if ".lora_A" in k:
            pairs.setdefault(mod, {})["A"] = v
        elif ".lora_B" in k:
            pairs.setdefault(mod, {})["B"] = v
    full = {m: p for m, p in pairs.items() if "A" in p and "B" in p}
    log(f"配对模块: {len(full)}（期望 层数×{len(cfg['target_modules'])}）")
    for m in list(full)[:2]:
        log(f"  {m}: A{tuple(full[m]['A'].shape)} B{tuple(full[m]['B'].shape)}")
    if not full:
        raise SystemExit("未配对到任何 LoRA 模块——请检查 adapter key 格式")

    idx = json.loads((base / "model.safetensors.index.json").read_text())
    wmap: dict[str, str] = idx["weight_map"]
    shards: dict[str, list[str]] = {}
    for t, s in wmap.items():
        shards.setdefault(s, []).append(t)

    out.mkdir(parents=True, exist_ok=True)
    merged = total = 0
    t0 = time.time()
    for shard in sorted(shards):
        with safe_open(str(base / shard), framework="pt", device="cpu") as f:
            tens = {}
            for t in shards[shard]:
                w = f.get_tensor(t)
                total += 1
                mod = t[: -len(".weight")] if t.endswith(".weight") else None
                if mod in full:
                    A, B = full[mod]["A"], full[mod]["B"]      # A:[r,in] B:[out,r]
                    delta = (B.to(torch.float32) @ A.to(torch.float32)) * scale
                    w = (w.to(torch.float32) + delta).to(w.dtype)
                    merged += 1
                tens[t] = w
        save_file(tens, str(out / shard), metadata={"format": "pt"})
        log(f"  {shard}（{len(shards[shard])} 张量，累计 {time.time() - t0:.0f}s）")
    log(f"合并张量 {merged}/{total}")
    if merged == 0:
        raise SystemExit("没有任何张量被合并——模块命名不匹配")

    json.dump({"metadata": idx.get("metadata", {}), "weight_map": wmap},
              open(out / "model.safetensors.index.json", "w"))
    for name in ("config.json", "generation_config.json", "chat_template.jinja"):
        if (base / name).exists():
            shutil.copy2(base / name, out / name)
    n_tok = 0
    for p in sorted(base.glob("tokenizer*")):
        shutil.copy2(p, out / p.name)
        n_tok += 1
    log(f"索引 + config + tokenizer({n_tok}) 已复制")
    log(f"输出: {out} | 大小 "
        f"{sum(p.stat().st_size for p in out.glob('*.safetensors')) / 1e9:.1f} GB")
    print("MERGED_OK", out, flush=True)


if __name__ == "__main__":
    main()
