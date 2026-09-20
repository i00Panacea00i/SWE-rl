"""将 verl FSDP LoRA checkpoint（4-rank DTensor 分片）转为标准 HuggingFace/peft adapter。

用法（4 进程）:
  torchrun --nproc_per_node=4 convert_lora_to_hf.py <actor-dir> <out-dir>

输出: adapter_model.safetensors + adapter_config.json + tokenizer 文件
"""
import glob
import json
import os
import sys

import torch
import torch.distributed as dist
from safetensors.torch import save_file


def main():
    dist.init_process_group("gloo")
    rank, world = dist.get_rank(), dist.get_world_size()
    actor_dir, out_dir = sys.argv[1], sys.argv[2]

    files = sorted(glob.glob(os.path.join(actor_dir, "model_world_size_*_rank_*.pt")))
    f = files[rank]
    sd = torch.load(f, map_location="cpu", weights_only=False)

    local = {}
    for k, v in sd.items():
        t = v.to_local() if hasattr(v, "to_local") else v
        local[k] = t.contiguous().clone()
    first = sorted(local)[0]
    print(f"rank{rank}: keys={len(local)} first={first} "
          f"local_shape={tuple(local[first].shape)}", flush=True)

    gather = "/tmp/lora-gather"
    os.makedirs(gather, exist_ok=True)
    torch.save(local, f"{gather}/rank{rank}.pt")
    dist.barrier()

    if rank == 0:
        parts = [torch.load(f"{gather}/rank{r}.pt", map_location="cpu") for r in range(world)]
        out = {}
        n_cat = n_rep = 0
        for k in sorted(local):
            ts = [p[k] for p in parts]
            same_shape = all(t.shape == ts[0].shape for t in ts)
            if same_shape and all(torch.equal(ts[0], t) for t in ts[1:]):
                out[k] = ts[0]
                n_rep += 1
            else:
                out[k] = torch.cat(ts, dim=0)
                n_cat += 1
        os.makedirs(out_dir, exist_ok=True)
        save_file(out, os.path.join(out_dir, "adapter_model.safetensors"))
        cfg = {
            "peft_type": "LORA", "task_type": "CAUSAL_LM",
            "r": 32, "lora_alpha": 64, "lora_dropout": 0.0,
            "target_modules": ["q_proj", "k_proj", "v_proj", "o_proj"],
            "bias": "none", "inference_mode": True,
            "base_model_name_or_path": "/mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct",
        }
        json.dump(cfg, open(os.path.join(out_dir, "adapter_config.json"), "w"), indent=2)
        hf = os.path.join(actor_dir, "huggingface")
        for fn in ["chat_template.jinja", "tokenizer.json", "tokenizer_config.json",
                   "generation_config.json"]:
            src = os.path.join(hf, fn)
            if os.path.exists(src):
                os.system(f"cp {src} {out_dir}/")
        sz = os.path.getsize(os.path.join(out_dir, "adapter_model.safetensors"))
        print(f"ADAPTER_OK | replicated={n_rep} concat={n_cat} | "
              f"{sz / 1e6:.1f} MB -> {out_dir}", flush=True)
    dist.barrier()


if __name__ == "__main__":
    main()
