#!/usr/bin/env bash
# pass@4 无人值守链（AGS 配额 100 → 分 4 批，每批 80 沙箱）。
#
#   base-p4a (n=2,off=0) → base-p4b (n=2,off=2)
#   → lora-p4a (n=2,off=0) → lora-p4b (n=2,off=2) → 汇总
#
# 特性：
#   1. 每批启动前做配额探针（AGS 无删除 API，STOPPED 实例靠 TTL 回收）
#   2. 幂等：已存在的 Pod 不重启；可重复执行
#   3. 脱离终端（setsid 启动），IDE 关闭不影响
#   4. 全程日志 /tmp/pass4-chain.log；结束自动汇总到 CFS
#
# 启动：
#   cd /root/swe-rl-kit && setsid nohup bash scripts/pass4-chain.sh \
#     >/tmp/pass4-chain.out 2>&1 </dev/null &
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LOG=/tmp/pass4-chain.log
SYNC_POD=swe-rl-sync
RUN_KIT=/mnt/cfs/swe-rl/runs/eval-30b-base-vs-lora/kit
BATCHES="base-p4a base-p4b lora-p4a lora-p4b"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG"; }

wait_quota() {          # 最多等 3 小时（36 × 5 分钟）
  local n=0
  while [ "$n" -lt 36 ]; do
    if venv/bin/python scripts/quota_probe.py >>"$LOG" 2>&1; then
      log "配额可用（第 $((n + 1)) 次探测）"
      return 0
    fi
    n=$((n + 1))
    log "配额繁忙，300s 后重试（$n/36）"
    sleep 300
  done
  log "WARN: 配额等待超时，仍继续尝试"
  return 1
}

wait_terminal() {       # $1=pod → 打印终态（最多 4 小时）
  local pod=$1 phase=""
  for _ in $(seq 1 240); do
    phase=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null)
    case "$phase" in
      Succeeded|Failed) echo "$phase"; return 0 ;;
      "")               echo "MISSING"; return 0 ;;
    esac
    sleep 60
  done
  echo "TIMEOUT"
}

ensure_pod() {          # $1=pod $2=yaml
  local pod=$1 yaml=$2 phase
  phase=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null)
  if [ -n "$phase" ]; then
    log "$pod 已存在（$phase），跳过创建"
    return 0
  fi
  log "创建 $pod"
  kubectl apply -f "$yaml" >>"$LOG" 2>&1 || log "WARN: apply $yaml 失败"
}

log "==================== pass@4 链启动（pid $$，4 批）===================="

for b in $BATCHES; do
  log "-------- 批次 $b --------"
  wait_quota
  ensure_pod "swe-rl-vllm-eval-$b" "deploy/eval-30b/vllm-eval-$b.yaml"
  ST=$(wait_terminal "swe-rl-vllm-eval-$b")
  log "$b 终态: $ST"
  log "等待 90s 让平台回收沙箱配额…"
  sleep 90
done

log "-------- 汇总 --------"
kubectl exec "$SYNC_POD" -- python3 "$RUN_KIT/scripts/summarize_pass4.py" \
  --base /mnt/cfs/swe-rl/traces/eval-base-t0/vllm-pass4 \
  --lora /mnt/cfs/swe-rl/traces/eval-lora-t0/vllm-pass4 \
  --out /mnt/cfs/swe-rl/logs/pass4-summary.json >>"$LOG" 2>&1 \
  || log "WARN: 汇总失败（可后补：见 summarize_pass4.py 用法）"

log "==================== 链结束 ===================="
log "结果：/mnt/cfs/swe-rl/traces/eval-{base,lora}-t0/vllm-pass4/"
log "汇总：/mnt/cfs/swe-rl/logs/pass4-summary.json"
