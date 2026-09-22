#!/bin/bash
# v2 训练脚本（2026-09-22 全量复盘后的配置）：Qwen3-Coder-30B-A3B + LoRA-GRPO（4×L20）。
# 变更 vs grpo_4l20_30b.sh（逐项依据见 docs/validation/rl-full-retrospective.md §5）：
#   response 8192 → 16384（消除 12.1% token 截断 + 19% clip）        [H1]
#   max_model_len 16384 → 32768；batched_tokens 8192 → 16384        [H2/H3]
#   rollout.n 4 → 8（组内信号捕获 ×2，缓解 70% 全零组）                 [H4]
#   lr 1e-5 → 3e-5（grad_norm 长期 0.02 量级，更新过小）               [H6]
#   +optim.clip_grad=0.5（显式；step 41/44/45 曾发生 grad_norm 8.0）   [H7]
#   kl_loss_coef 0.001 → 0.0005（防全零步 KL-only 漂移）               [H8]
#   target_modules 保持 attention-only（H9 作废：字符串 all-linear 会触发 verl 的
#     list() 拆分 bug——peft 收到字符集报错；且 MoE 专家层被误挂会梯度稀疏，v1 已排除）
#   +algorithm.filter_groups（全对/全错组丢弃重采样，DAPO 式）           [H13]
#   test/save_freq 10 → 25；steps 默认 100（filter_groups 提高步效）    [H11/H12]
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
AGENT_WORKERS=${VERL_AGENT_WORKERS:-16}
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
    algorithm.filter_groups.enable=True \
    algorithm.filter_groups.metric=reward \
    algorithm.filter_groups.max_num_gen_batches="${VERL_FILTER_MAX_GEN:-3}" \
    data.train_files="$DATA" \
    data.val_files="$VAL_DATA" \
    +data.apply_chat_template_kwargs.enable_thinking=false \
    data.train_batch_size=8 \
    data.dataloader_num_workers=0 \
    data.max_prompt_length="${VERL_MAX_PROMPT_LENGTH:-4096}" \
    data.max_response_length="${VERL_MAX_RESPONSE_LENGTH:-16384}" \
    actor_rollout_ref.model.path="$MODEL" \
    actor_rollout_ref.model.lora_rank=32 \
    actor_rollout_ref.model.lora_alpha=64 \
    actor_rollout_ref.model.lora.merge=False \
    actor_rollout_ref.model.target_modules=all-linear \
    actor_rollout_ref.actor.optim.lr="${VERL_LR:-3e-5}" \
    actor_rollout_ref.actor.optim.clip_grad=0.5 \
    actor_rollout_ref.actor.ppo_mini_batch_size=8 +actor_rollout_ref.actor.checkpoint.save_lora_only=True \
    actor_rollout_ref.actor.ppo_micro_batch_size_per_gpu=1 \
    actor_rollout_ref.actor.use_kl_loss=True \
    actor_rollout_ref.actor.kl_loss_coef=0.0005 \
    actor_rollout_ref.actor.strategy=fsdp \
    actor_rollout_ref.actor.fsdp_config.model_dtype=bf16 \
    actor_rollout_ref.actor.fsdp_config.param_offload=True \
    actor_rollout_ref.ref.fsdp_config.model_dtype=bf16 \
    actor_rollout_ref.ref.fsdp_config.param_offload=True \
    actor_rollout_ref.ref.log_prob_micro_batch_size_per_gpu=1 \
    actor_rollout_ref.rollout.n=8 actor_rollout_ref.rollout.temperature=0.7 \
    actor_rollout_ref.rollout.mode=async \
    actor_rollout_ref.rollout.name=vllm \
    actor_rollout_ref.rollout.dtype=bfloat16 \
    actor_rollout_ref.rollout.load_format=safetensors \
    actor_rollout_ref.rollout.layered_summon=True \
    actor_rollout_ref.rollout.tensor_model_parallel_size=4 \
    actor_rollout_ref.rollout.free_cache_engine=True \
    actor_rollout_ref.rollout.max_model_len=32768 \
    actor_rollout_ref.rollout.gpu_memory_utilization="${VERL_VLLM_UTIL:-0.5}" \
    actor_rollout_ref.rollout.enforce_eager=True \
    actor_rollout_ref.rollout.max_num_batched_tokens=16384 \
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
    trainer.experiment_name="${SWE_RUN_ID:-swegym-30b-tier0-r2}" \
    trainer.validation_data_dir="$REPORT_DIR" \
    trainer.resume_mode="${VERL_RESUME_MODE:-disable}" \
    trainer.val_before_train="${VERL_VAL_BEFORE_TRAIN:-False}" \
    trainer.test_freq="${VERL_TEST_FREQ:-25}" \
    trainer.save_freq="${VERL_SAVE_FREQ:-25}" \
    trainer.total_epochs=100 \
    trainer.total_training_steps="${VERL_TRAIN_STEPS:-100}" \
    trainer.default_local_dir="$OUT" \
    trainer.n_gpus_per_node=4 \
    trainer.nnodes=1 2>&1 | tee "$LOG_DIR/train-$(date -u +%Y%m%dT%H%M%SZ).log"
