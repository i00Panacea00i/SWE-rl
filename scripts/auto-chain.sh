#!/usr/bin/env bash
# 全自动链（无人值守，可关 IDE）：画像 → 筛选 → 训练池 → 部署 → 冒烟 → 主训练 → 看护
# 幂等：各阶段自带完成判定；中断后原样重跑即可。
# 日志：/tmp/auto-chain.log（每步都有时间戳）
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=/tmp/auto-chain.log
log() { echo "[$(date -u +%H:%M:%S)] $*" >>"$LOG"; }

export AGS_IMAGE_PREFIX="${AGS_IMAGE_PREFIX:-benchmark-upload-sicheng.tencentcloudcr.com/swe-mirror/swe-ags}"
set -a; [ -f .env ] && . ./.env; set +a

SUMMARY=/tmp/profile-summary.json
POOL=/tmp/train-pool
KIT=/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r2/kit
POD_MAIN=swe-rl-swegym-30b-tier0-r2
POD_SMOKE=swe-rl-swegym-30b-tier0-r2-smoke

if [ -f /tmp/auto-chain.pid ] && kill -0 "$(cat /tmp/auto-chain.pid 2>/dev/null)" 2>/dev/null; then
  log "已有实例（pid $(cat /tmp/auto-chain.pid)）运行，本实例退出"; exit 0
fi
echo $$ > /tmp/auto-chain.pid
log "=== 全自动链启动（pid $$）==="

# ── 阶段1: 等画像 summary ──
for i in $(seq 1 360); do
  if kubectl exec swe-rl-sync -- test -f /mnt/cfs/swe-rl/logs/profile-summary.json 2>/dev/null; then
    log "[阶段1] 画像 summary 就绪（等待 ${i} 分钟）"; break
  fi
  [ $((i % 15)) -eq 0 ] && log "[阶段1] 等待画像… ${i} 分钟（画像链: $(pgrep -f profile-chain >/dev/null && echo 运行中 || echo 已停止)）"
  sleep 60
done
kubectl exec swe-rl-sync -- test -f /mnt/cfs/swe-rl/logs/profile-summary.json 2>/dev/null || { log "[阶段1] ❌ 等待超时（6h）退出"; exit 2; }

kubectl exec swe-rl-sync -- cat /mnt/cfs/swe-rl/logs/profile-summary.json > "$SUMMARY"
LEARN=$(venv/bin/python -c "import json;print(len(json.load(open('$SUMMARY')).get('learnable',[])))" 2>/dev/null || echo 0)
HARD=$(venv/bin/python -c "import json;print(len(json.load(open('$SUMMARY')).get('too_hard',[])))" 2>/dev/null || echo 0)
EASY=$(venv/bin/python -c "import json;print(len(json.load(open('$SUMMARY')).get('too_easy',[])))" 2>/dev/null || echo 0)
log "[阶段1] 画像分层: learnable=$LEARN | too_hard=$HARD | too_easy=$EASY"

# ── 阶段2: 构建训练池（learnable≥20 不补齐；否则补到 40）──
if [ "${LEARN:-0}" -ge 20 ]; then TARGET=$LEARN; else TARGET=40; fi
log "[阶段2] 构建训练池（target=$TARGET）"
venv/bin/python scripts/build_train_pool.py --summary "$SUMMARY" \
  --profile-instances data/profile/profile-instances.jsonl \
  --specs-src data/profile/task_specs --out "$POOL" --target "$TARGET" >>"$LOG" 2>&1
venv/bin/python data/prepare_data.py --input "$POOL/instances.jsonl" \
  --output "$POOL/train.parquet" --allow-unvalidated --max-steps-hint 16 >>"$LOG" 2>&1
[ -s "$POOL/train.parquet" ] || { log "[阶段2] ❌ parquet 构建失败，退出"; exit 2; }
POOLN=$(venv/bin/python -c "import pandas as pd;print(len(pd.read_parquet('$POOL/train.parquet')))" 2>/dev/null || echo 0)
log "[阶段2] 训练池 $POOLN 题就绪"

# ── 阶段3: 部署到 r2 kit + 校验和 ──
log "[阶段3] 更新 r2 kit"
kubectl exec swe-rl-sync -- sh -c "cp $KIT/data/tier0-r2/train.parquet /mnt/cfs/swe-rl/runs/backup-train-v1-22q.parquet 2>/dev/null || true"
tar cf - -C "$POOL" train.parquet instances.jsonl | kubectl exec -i swe-rl-sync -- tar xf - -C /tmp/
kubectl exec swe-rl-sync -- sh -c "cp /tmp/train.parquet $KIT/data/tier0-r2/train.parquet; cp /tmp/instances.jsonl $KIT/data/instances.jsonl; rm -f /tmp/train.parquet /tmp/instances.jsonl"
tar cf - -C "$POOL" task_specs | kubectl exec -i swe-rl-sync -- tar xf - -C "$KIT/data/"
kubectl exec swe-rl-sync -- sh -c "cd $KIT && find configs controller data sandbox tests verl_plugin -type f ! -name '.nfs*' | sort | xargs sha256sum > protocol.sha256 && wc -l < protocol.sha256 | xargs echo '[阶段3] protocol.sha256 文件数:'"

# ── 阶段4: 冒烟（配额准入门控）──
log "[阶段4] 冒烟 10 步"
for a in $(seq 1 24); do
  venv/bin/python scripts/quota_probe.py >/dev/null 2>&1 && { log "[阶段4] 配额 OK（第 $a 次探测）"; break; }
  log "[阶段4] 配额忙 $a/24，等 5 分钟"; sleep 300
done
kubectl delete pod $POD_SMOKE --wait=false >/dev/null 2>&1 || true
sleep 3
kubectl apply -f deploy/train-30b-v2-smoke.yaml >/dev/null || { log "[阶段4] ❌ 冒烟启动失败"; exit 2; }
PH=""
for w in $(seq 1 240); do
  sleep 60
  PH=$(kubectl get pod $POD_SMOKE -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$PH" = "Succeeded" ] || [ "$PH" = "Failed" ]; then break; fi
  [ $((w % 30)) -eq 0 ] && log "[阶段4] 冒烟运行中 ${w} 分钟"
done
log "[阶段4] 冒烟终态: ${PH:-超时}"
SMOKE_STEPS=$(kubectl exec swe-rl-sync -- sh -c 'ls /mnt/cfs/swe-rl/traces/swegym-30b-tier0-r2-smoke/train 2>/dev/null | wc -l' 2>/dev/null || echo 0)
log "[阶段4] 冒烟轨迹 step 目录数: $SMOKE_STEPS"
kubectl logs $POD_SMOKE 2>/dev/null | grep -E "critic/rewards/mean|timing_s/step|Error executing" | tail -4 >>"$LOG" 2>&1 || true

if [ "${SMOKE_STEPS:-0}" -lt 3 ]; then
  log "[阶段4] ❌ 冒烟无有效产出（<3 步）——暂停，等待人工检查（/tmp/auto-chain.log 与冒烟日志）"
  exit 3
fi
log "[阶段4] ✅ 冒烟有产出，继续主训练"

# ── 阶段5: 主训练 ──
log "[阶段5] 启动主训练（100 步，预计 ~53h）"
kubectl delete pod $POD_MAIN --wait=false >/dev/null 2>&1 || true
sleep 3
kubectl apply -f deploy/train-30b-v2.yaml >/dev/null || { log "[阶段5] ❌ 主训练启动失败"; exit 2; }
sleep 30
kubectl get pod $POD_MAIN --no-headers 2>&1 >>"$LOG"

# ── 阶段6: 看护（每 30 分钟检查，Failed 自动重启续训）──
log "[阶段6] 进入看护模式（每 30 分钟）"
for t in $(seq 1 220); do
  sleep 1800
  PH=$(kubectl get pod $POD_MAIN -o jsonpath='{.status.phase}' 2>/dev/null || echo Missing)
  log "[看护] 训练 Pod: $PH"
  if [ "$PH" = "Succeeded" ]; then log "[看护] 训练完成 ✓"; break; fi
  if [ "$PH" = "Failed" ] || [ "$PH" = "Missing" ]; then
    log "[看护] 训练异常 → 重启续训（resume_mode=auto）"
    kubectl delete pod $POD_MAIN --wait=false >/dev/null 2>&1 || true
    sleep 5
    kubectl apply -f deploy/train-30b-v2.yaml >/dev/null 2>&1 && log "[看护] 已重启" || log "[看护] 重启失败"
  fi
done
log "=== 全自动链结束 ==="
