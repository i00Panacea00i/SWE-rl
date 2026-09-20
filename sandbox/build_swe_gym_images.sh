#!/bin/bash
# SWE-Gym 镜像批处理：Docker Hub 公开镜像 → AGS 变体 → TCR。
# 用法: TCR_REGISTRY=<真实仓库地址，含命名空间> bash sandbox/build_swe_gym_images.sh <实例清单.jsonl> [数量上限]
# 特性: 断点续跑（/tmp/swe-gym-image-progress.jsonl）、429 限流退避、逐实例清理本地磁盘。
set -uo pipefail

TCR_REGISTRY=${TCR_REGISTRY:?需设置 TCR_REGISTRY（形如 xxx.tencentcloudcr.com/swe-mirror/swe-ags）}
LIST=${1:?实例清单 jsonl（含 instance_id 与 image 字段）}
LIMIT=${2:-999999}
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROGRESS=/tmp/swe-gym-image-progress.jsonl
touch "$PROGRESS"

done_ids() { cut -d'"' -f4 "$PROGRESS" 2>/dev/null; }

count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  iid=$(echo "$line" | sed -E 's/.*"instance_id": "([^"]+)".*/\1/')
  src=$(echo "$line" | sed -E 's/.*"image": "([^"]+)".*/\1/')
  tag=$(echo "$iid" | tr 'A-Z' 'a-z' | sed 's/__/_s_/g')
  dst="$TCR_REGISTRY:$tag"

  if done_ids | grep -q "^$iid$"; then
    echo "[skip] $iid（已完成）"
    continue
  fi
  count=$((count+1)); [ "$count" -gt "$LIMIT" ] && { echo "达到上限 $LIMIT"; break; }

  echo "=== [$iid] pull $src ==="
  attempt=0
  until docker pull "$src" 2>/tmp/pull-err.log; do
    attempt=$((attempt+1))
    if grep -q "toomanyrequests\|429" /tmp/pull-err.log; then
      echo "[rate-limited] ${attempt} 次，等待 10 分钟后重试: $iid"
      sleep 600
    elif [ "$attempt" -ge 3 ]; then
      echo "[FAIL] $iid pull: $(tail -1 /tmp/pull-err.log | head -c 200)"
      continue 2
    else
      sleep 30
    fi
  done

  echo "=== [$iid] build $dst ==="
  if ! docker build --platform=linux/amd64 --build-arg OFFICIAL="$src" \
       -t "$dst" -f "$KIT_DIR/sandbox/Dockerfile.swe-ags.tmpl" "$KIT_DIR/sandbox" \
       >/tmp/build-$tag.log 2>&1; then
    echo "[FAIL] $iid build: $(tail -2 /tmp/build-$tag.log | head -c 300)"
    docker rmi "$src" >/dev/null 2>&1
    continue
  fi

  echo "=== [$iid] push ==="
  if docker push "$dst" >/dev/null 2>&1; then
    echo "{\"id\": \"$iid\"}" >> "$PROGRESS"
    echo "[done] $iid"
  else
    echo "[FAIL] $iid push"
  fi
  docker rmi "$src" "$dst" >/dev/null 2>&1
  df -h / | tail -1 | awk '{print "[disk] 已用 "$3" 余 "$4}'
done < "$LIST"
echo "=== 批处理结束: $(done_ids | wc -l) 完成 ==="
