#!/usr/bin/env bash
# 冒烟 → 主训练 → 看护（不含筛选阶段；训练池已由人工决策就绪）。
# 用法：bash scripts/smoke-to-train.sh 或 setsid nohup 启动。
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=/tmp/smoke-to-train.log
log() { echo "[$(date -u +%H:%M:%S)] $*" >>"$LOG"; }

POD_SMOKE=swe-rl-swegym-30b-tier0-r2-smoke
POD_MAIN=swe-rl-swegym-30b-tier0-r2

if [ -f /tmp/smoke-to-train.pid ] && kill -0 "$(cat /tmp/smoke-to-train.pid 2>/dev/null)" 2>/dev/null; then
  log "已有实例运行，退出"; exit 0
fi
echo $$ > /tmp/smoke-to-train.pid
log "=== 冒烟→主训练链启动（pid $$）==="

log "等待冒烟完成"
PH=""
for w in $(seq 1 180); do
  sleep 60
  PH=$(kubectl get pod "$POD_SMOKE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$PH" = "Succeeded" ] || [ "$PH" = "Failed" ]; then break; fi
  [ $((w % 10)) -eq 0 ] && log "  冒烟运行中 ${w} 分钟"
done
log "冒烟终态: ${PH:-超时}"

STEPS=$(kubectl exec swe-rl-sync -- sh -c 'ls /mnt/cfs/swe-rl/traces/swegym-30b-tier0-r2-smoke/train 2>/dev/null | wc -l' 2>/dev/null || echo 0)
log "冒烟 step 目录数: $STEPS"
kubectl logs "$POD_SMOKE" 2>/dev/null | grep -E "critic/rewards/mean|timing_s/step|response_length/mean" | tail -3 >>"$LOG" 2>&1 || true

if [ "${STEPS:-0}" -lt 3 ]; then
  log "❌ 冒烟无有效产出（$STEPS < 3）——暂停等待人工检查"
  exit 3
fi
log "✅ 冒烟有产出 → 启动主训练"

kubectl delete pod "$POD_MAIN" --wait=false >/dev/null 2>&1 || true
sleep 3
kubectl apply -f deploy/train-30b-v2.yaml >/dev/null || { log "❌ 主训练启动失败"; exit 2; }
sleep 30
kubectl get pod "$POD_MAIN" --no-headers 2>&1 >>"$LOG" || true
log "主训练已启动（100 步，预计 ~53h）"
log "=== 进入看护模式（每 30 分钟检查，Failed 自动重启续训）==="
for t in $(seq 1 220); do
  sleep 1800
  PH=$(kubectl get pod "$POD_MAIN" -o jsonpath='{.status.phase}' 2>/dev/null || echo Missing)
  log "[看护] 训练 Pod: $PH"
  if [ "$PH" = "Succeeded" ]; then log "[看护] 训练完成 ✓"; break; fi
  if [ "$PH" = "Failed" ] || [ "$PH" = "Missing" ]; then
    log "[看护] 异常 → 重启续训（resume_mode=auto）"
    kubectl delete pod "$POD_MAIN" --wait=false >/dev/null 2>&1 || true
    sleep 5
    kubectl apply -f deploy/train-30b-v2.yaml >/dev/null 2>&1 && log "[看护] 已重启" || log "[看护] 重启失败"
  fi
done
log "=== 链结束 ==="
