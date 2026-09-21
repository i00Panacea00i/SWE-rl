#!/bin/bash
# 评估专用：Qwen3-Coder-30B-A3B 的 base vs base+LoRA 对比。
# 编排说明：EVAL_TOTAL_STEPS=1 复刻训练编排（val-only 的 total=0 会跳过 actor 显存释放时序，
# 导致 update_weights 后 vLLM 权重唤醒 OOM）。val_before_train 产出评估数据后即可终止 Pod。
# 公平性锁定：本脚本为唯一评估入口——两组（base/lora）除 EVAL_VARIANT 外所有参数逐字节一致。
# 用法：
#   EVAL_VARIANT=base   （无适配器）
#   EVAL_VARIANT=lora   （加载 swegym-30b-tier0-r1 的 step-50 LoRA，resume 机制）
# 协议（ADR-002）：EVAL_N / EVAL_TEMP 为主/副协议开关（主：1 / 0；副：4 / 0.7）。
set -euo pipefail

DATA=${VERL_DATA:?未配置训练数据（占位，评估不训练）}
EVAL_DATA=${VERL_VAL_DATA:?未配置 held-out 评估数据}
MODEL=${VERL_MODEL:?未配置本地模型路径}
REWARD_PATH=${VERL_REWARD_PATH:?未配置真实 SWE 奖励函数}
AGENT_CONFIG=${VERL_AGENT_LOOP_CONFIG:?未配置真实 SWE AgentLoop}
AGENT_NAME=${VERL_AGENT_NAME:?未配置已注册的 SWE AgentLoop 名称}
VARIANT=${EVAL_VARIANT:?必须为 base 或 lora}
OUT=${VERL_OUT:-/mnt/cfs/swe-rl/checkpoints/eval}
LOG_DIR=${VERL_LOG_DIR:-/mnt/cfs/swe-rl/logs}
REPORT_DIR=${VERL_REPORT_DIR:-/mnt/cfs/swe-rl/eval_reports/eval}
AGENT_WORKERS=${VERL_AGENT_WORKERS:-10}
EVAL_N=${EVAL_N:-1}
EVAL_TEMP=${EVAL_TEMP:-0.0}

if [ "$VARIANT" != "base" ] && [ "$VARIANT" != "lora" ]; then
    echo "EVAL_VARIANT 必须为 base 或 lora（当前: $VARIANT）" >&2; exit 2
fi
for input_file in "$DATA" "$EVAL_DATA" "$REWARD_PATH" "$AGENT_CONFIG"; do
    test -s "$input_file" || { printf '缺少文件: %s\n' "$input_file" >&2; exit 2; }
done
mkdir -p "$OUT" "$LOG_DIR" "$REPORT_DIR"

# ── 变体差异（唯一允许的变量：模型是否为 base+LoRA；resume 仅用于加载适配器）──
LORA_ARGS=()
RESUME_MODE="disable"
if [ "$VARIANT" = "lora" ]; then
    LORA_ARGS=(
        actor_rollout_ref.model.lora_rank=32
        actor_rollout_ref.model.lora_alpha=64
        actor_rollout_ref.model.lora.merge=False
        'actor_rollout_ref.model.target_modules=[q_proj,k_proj,v_proj,o_proj]'
        "+actor_rollout_ref.actor.checkpoint.save_lora_only=True"
    )
    RESUME_MODE="auto"   # 从 VERL_OUT（训练 checkpoint 目录）加载 step-50 LoRA
fi

# ── 双协议参数字符串 ──
DO_SAMPLE="False"; [ "$EVAL_N" != "1" ] && DO_SAMPLE="True"

export RAY_memory_monitor_refresh_ms=250
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export HYDRA_FULL_ERROR=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

echo "=== EVAL $VARIANT | n=$EVAL_N temp=$EVAL_TEMP do_sample=$DO_SAMPLE | resume=$RESUME_MODE ==="

python3 -u -m verl.trainer.main_ppo \
    algorithm.adv_estimator=grpo \
    data.train_files="$DATA" \
    data.val_files="$EVAL_DATA" \
    +data.apply_chat_template_kwargs.enable_thinking=false \
    data.train_batch_size=8 \
    data.val_batch_size="${EVAL_BATCH:-4}" \
    data.dataloader_num_workers=0 \
    data.max_prompt_length="${VERL_MAX_PROMPT_LENGTH:-4096}" \
    data.max_response_length="${VERL_MAX_RESPONSE_LENGTH:-4096}" \
    actor_rollout_ref.model.path="$MODEL" \
    "${LORA_ARGS[@]}" \
    actor_rollout_ref.actor.optim.lr=1e-5 \
    actor_rollout_ref.actor.ppo_mini_batch_size=8 \
    actor_rollout_ref.actor.ppo_micro_batch_size_per_gpu=1 \
    actor_rollout_ref.actor.use_kl_loss=False \
    actor_rollout_ref.actor.kl_loss_coef=0.001 \
    actor_rollout_ref.actor.strategy=fsdp \
    actor_rollout_ref.actor.fsdp_config.model_dtype=bf16 \
    actor_rollout_ref.actor.fsdp_config.param_offload=True \
    actor_rollout_ref.ref.fsdp_config.model_dtype=bf16 \
    actor_rollout_ref.ref.fsdp_config.param_offload=True \
    actor_rollout_ref.ref.log_prob_micro_batch_size_per_gpu=1 \
    actor_rollout_ref.rollout.n=4 actor_rollout_ref.rollout.temperature=0.7 \
    actor_rollout_ref.rollout.mode=async \
    actor_rollout_ref.rollout.name=vllm \
    actor_rollout_ref.rollout.dtype=bfloat16 \
    actor_rollout_ref.rollout.load_format=safetensors \
    actor_rollout_ref.rollout.layered_summon=True \
    actor_rollout_ref.rollout.tensor_model_parallel_size=4 \
    actor_rollout_ref.rollout.free_cache_engine=True \
    actor_rollout_ref.rollout.max_model_len=16384 \
    actor_rollout_ref.rollout.gpu_memory_utilization=0.42 \
    actor_rollout_ref.rollout.enforce_eager=True \
    actor_rollout_ref.rollout.max_num_batched_tokens=8192 \
    actor_rollout_ref.rollout.log_prob_micro_batch_size_per_gpu=1 \
    actor_rollout_ref.rollout.agent.agent_loop_config_path="$AGENT_CONFIG" \
    actor_rollout_ref.rollout.agent.default_agent_loop="$AGENT_NAME" \
    actor_rollout_ref.rollout.agent.num_workers="$AGENT_WORKERS" \
    actor_rollout_ref.rollout.val_kwargs.n="$EVAL_N" \
    actor_rollout_ref.rollout.val_kwargs.do_sample="$DO_SAMPLE" \
    actor_rollout_ref.rollout.val_kwargs.temperature="$EVAL_TEMP" \
    reward.custom_reward_function.path="$REWARD_PATH" \
    reward.custom_reward_function.name="${VERL_REWARD_NAME:-compute_score}" \
    trainer.logger='["console"]' \
    trainer.project_name=swe-rl-eval \
    trainer.experiment_name="eval-${VARIANT}-n${EVAL_N}-t${EVAL_TEMP}-${SWE_RUN_ID:-run}" \
    trainer.validation_data_dir="$REPORT_DIR" \
    trainer.resume_mode="$RESUME_MODE" \
    trainer.val_before_train=True \
    trainer.test_freq=9999 \
    trainer.save_freq=9999 \
    trainer.total_epochs=100 \
    trainer.total_training_steps="${EVAL_TOTAL_STEPS:-1}" \
    trainer.default_local_dir="$OUT" \
    trainer.n_gpus_per_node=4 \
    trainer.nnodes=1 2>&1 | tee "$LOG_DIR/eval-${VARIANT}-$(date -u +%Y%m%dT%H%M%SZ).log"
