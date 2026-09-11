#!/bin/bash
# Qwen2.5-Coder-7B-Instruct + LoRA-GRPO（2×L20）。正式训练需真实 SWE AgentLoop 与奖励。
set -euo pipefail

DATA=${VERL_DATA:?未配置训练数据}
VAL_DATA=${VERL_VAL_DATA:?未配置独立评估数据}
MODEL=${VERL_MODEL:?未配置本地模型路径}
REWARD_PATH=${VERL_REWARD_PATH:?未配置真实 SWE 奖励函数}
AGENT_CONFIG=${VERL_AGENT_LOOP_CONFIG:?未配置真实 SWE AgentLoop}
AGENT_NAME=${VERL_AGENT_NAME:?未配置已注册的 SWE AgentLoop 名称}
OUT=${VERL_OUT:-/mnt/cfs/swe-rl/checkpoints/round0}
LOG_DIR=${VERL_LOG_DIR:-/mnt/cfs/swe-rl/logs}
REPORT_DIR=${VERL_REPORT_DIR:-/mnt/cfs/swe-rl/eval_reports/round0-train}
AGENT_WORKERS=${VERL_AGENT_WORKERS:-2}
for input_file in "$DATA" "$VAL_DATA" "$REWARD_PATH" "$AGENT_CONFIG"; do
    test -s "$input_file" || { printf '缺少文件: %s\n' "$input_file" >&2; exit 2; }
done
if [ "$(realpath "$DATA")" = "$(realpath "$VAL_DATA")" ] || [[ "$REWARD_PATH" == *mock_reward* ]]; then
    echo '正式验收禁止复用训练集做评估或使用 mock reward' >&2
    exit 2
fi
mkdir -p "$OUT" "$LOG_DIR"
export RAY_memory_monitor_refresh_ms=250
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export HYDRA_FULL_ERROR=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

python3 -u -m verl.trainer.main_ppo \
    algorithm.adv_estimator=grpo \
    data.train_files="$DATA" \
    data.val_files="$VAL_DATA" \
    data.train_batch_size=6 \
    data.dataloader_num_workers=0 \
    data.max_prompt_length="${VERL_MAX_PROMPT_LENGTH:-4096}" \
    data.max_response_length="${VERL_MAX_RESPONSE_LENGTH:-8192}" \
    actor_rollout_ref.model.path="$MODEL" \
    actor_rollout_ref.model.lora_rank=32 \
    actor_rollout_ref.model.lora_alpha=64 \
    actor_rollout_ref.model.lora.merge=False \
    'actor_rollout_ref.model.target_modules=[q_proj,k_proj,v_proj,o_proj,gate_proj,up_proj,down_proj]' \
    actor_rollout_ref.actor.optim.lr=1e-5 \
    actor_rollout_ref.actor.ppo_mini_batch_size=6 +actor_rollout_ref.actor.checkpoint.save_lora_only=True \
    actor_rollout_ref.actor.ppo_micro_batch_size_per_gpu=1 \
    actor_rollout_ref.actor.use_kl_loss=True \
    actor_rollout_ref.actor.kl_loss_coef=0.001 \
    actor_rollout_ref.actor.strategy=fsdp \
    actor_rollout_ref.actor.fsdp_config.model_dtype=bf16 \
    actor_rollout_ref.actor.fsdp_config.param_offload=True \
    actor_rollout_ref.ref.fsdp_config.model_dtype=bf16 \
    actor_rollout_ref.ref.log_prob_micro_batch_size_per_gpu=1 \
    actor_rollout_ref.rollout.n=4 actor_rollout_ref.rollout.temperature=0.7 \
    actor_rollout_ref.rollout.mode=async \
    actor_rollout_ref.rollout.name=vllm \
    actor_rollout_ref.rollout.dtype=bfloat16 \
    actor_rollout_ref.rollout.load_format=safetensors \
    actor_rollout_ref.rollout.layered_summon=True \
    actor_rollout_ref.rollout.tensor_model_parallel_size=2 \
    actor_rollout_ref.rollout.gpu_memory_utilization=0.45 \
    actor_rollout_ref.rollout.enforce_eager=True \
    actor_rollout_ref.rollout.max_num_batched_tokens=8192 \
    actor_rollout_ref.rollout.log_prob_micro_batch_size_per_gpu=1 \
    actor_rollout_ref.rollout.agent.agent_loop_config_path="$AGENT_CONFIG" \
    actor_rollout_ref.rollout.agent.default_agent_loop="$AGENT_NAME" \
    actor_rollout_ref.rollout.agent.num_workers="$AGENT_WORKERS" \
    actor_rollout_ref.rollout.val_kwargs.n=1 \
    actor_rollout_ref.rollout.val_kwargs.do_sample=False \
    actor_rollout_ref.rollout.val_kwargs.temperature=0 \
    reward.custom_reward_function.path="$REWARD_PATH" \
    reward.custom_reward_function.name="${VERL_REWARD_NAME:-compute_score}" \
    trainer.logger='["console"]' \
    trainer.project_name=swe-rl-grpo \
    trainer.experiment_name="${SWE_RUN_ID:-round0-7b-lora}" \
    trainer.validation_data_dir="$REPORT_DIR" \
    trainer.resume_mode="${VERL_RESUME_MODE:-disable}" \
    trainer.val_before_train=True \
    trainer.test_freq="${VERL_TEST_FREQ:-10}" \
    trainer.save_freq="${VERL_SAVE_FREQ:-10}" \
    trainer.total_epochs=100 \
    trainer.total_training_steps="${VERL_TRAIN_STEPS:-50}" \
    trainer.default_local_dir="$OUT" \
    trainer.n_gpus_per_node=2 \
    trainer.nnodes=1 2>&1 | tee "$LOG_DIR/train-$(date -u +%Y%m%dT%H%M%SZ).log"
