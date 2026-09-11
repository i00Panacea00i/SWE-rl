#!/bin/bash
# GRPO 训练启动（1×A10 24GB + Qwen2.5-Coder-3B + LoRA；超参见 README §4）
# 前置：VERL_DATA / VERL_MODEL / E2B_DOMAIN / E2B_API_KEY 已注入（deploy/train-pod.yaml）
set -euo pipefail

DATA=${VERL_DATA:?}
MODEL=${VERL_MODEL:?}
OUT=/mnt/cfs/swe-rl/checkpoints/round0

python3 -m verl.trainer.main \
    algorithm.adv_estimator=grpo \
    data.train_files="$DATA" \
    data.val_files="$DATA" \
    data.train_batch_size=8 \
    data.micro_batch_size_per_gpu=1 \
    data.max_prompt_length=4096 \
    data.max_response_length=8192 \
    actor_rollout_ref.model.path="$MODEL" \
    actor_rollout_ref.actor.optim.lr=1e-6 \
    actor_rollout_ref.rollout.n=4 \
    actor_rollout_ref.rollout.mode=async \
    actor_rollout_ref.rollout.name=vllm \
    actor_rollout_ref.rollout.gpu_memory_utilization=0.5 \
    actor_rollout_ref.actor.use_kl_loss=True \
    actor_rollout_ref.actor.kl_loss_coef=0.001 \
    actor_rollout_ref.actor.lora.rank=32 \
    actor_rollout_ref.actor.lora.alpha=64 \
    trainer.project_name=swe-rl-grpo \
    trainer.experiment_name=round0 \
    trainer.val_before_train=True \
    trainer.test_freq=5 \
    trainer.total_epochs=1 \
    trainer.max_steps=50 \
    trainer.default_local_dir="$OUT" \
    trainer.n_gpus_per_node=1 \
    trainer.nnodes=1
