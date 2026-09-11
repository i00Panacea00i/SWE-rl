#!/usr/bin/env python3
"""patch verl fsdp2_load_full_state_dict：绕开 rank0 全量 GPU（61GB 模型单卡 44GB 放不下）。

原实现：rank0 把完整模型 to(device)（单卡需容纳全量 unsharded 权重），再
        broadcast_from_rank0 分发 —— 对 30B MoE + 48GB 卡结构性 OOM。
补丁后：所有 rank to_empty 上卡，各自从本 rank CPU 的 full_state 经
        set_model_state_dict(cpu_offload=True) 流式加载自己的 shard；
        GPU 峰值 = shard 大小（~15.25GB/2卡）而非全量 61GB。
"""
import re
import sys

path = sys.argv[1]
src = open(path).read()

old = """    # To broadcast, it needs to be instantiated in the GPU.
    if dist.get_rank() == 0:
        model = model.to(device=get_device_id(), non_blocking=True)
    else:
        model = model.to_empty(device=get_device_id())

    cpu_offload = cpu_offload is not None
    options = StateDictOptions(full_state_dict=True, cpu_offload=cpu_offload, broadcast_from_rank0=True)
    set_model_state_dict(model, full_state, options=options)"""

new = """    # PATCH(swe-rl): rank0 全量 to(device) 对 >44GB 模型单卡 OOM。
    # 改为各 rank 从本 rank CPU full_state 流式加载自己的 shard（GPU 峰值=shard 大小）。
    # full_state 在每个 rank 的 CPU 上都存在（各自从 HF 加载），无需 broadcast_from_rank0。
    model = model.to_empty(device=get_device_id())
    cpu_offload = True
    options = StateDictOptions(full_state_dict=True, cpu_offload=cpu_offload)
    set_model_state_dict(model, full_state, options=options)
    for buf in model.buffers():
        buf.data = buf.data.to(get_device_id())"""

if old not in src:
    print("PATCH TARGET NOT FOUND — verl 源码可能已更新，请人工核对")
    sys.exit(1)

open(path, "w").write(src.replace(old, new))
print("patched OK:", path)
