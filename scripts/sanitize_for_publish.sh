#!/usr/bin/env bash
# 发布前脱敏：把基础设施标识/账号痕迹替换为无害示例值。
#
# 用法：
#   bash scripts/sanitize_for_publish.sh --check   # 只扫描（发布前验证）
#   bash scripts/sanitize_for_publish.sh           # 对 git 跟踪文件执行替换（幂等）
#
# 设计原则：
#   1. 本脚本**不含任何真实值**（纯正则规则，可安全随仓库发布）；
#   2. 占位符采用 `<id>` 形式——不匹配扫描规则，保证幂等与检查干净；
#   3. 只替换"资产标识"；凭证类早已被 .gitignore 隔离，永不入库。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

RULES=(
  's/\bcls-[a-z0-9]{8}\b/cls-<id>/g'
  's/\bvpc-[a-z0-9]{8}\b/vpc-<id>/g'
  's/\bsubnet-[a-z0-9]{8}\b/subnet-<id>/g'
  's/\bcfs-[a-z0-9]{8}\b/cfs-<id>/g'
  's/\bsg-[a-z0-9]{8}\b/sg-<id>/g'
  's/\bnat-[a-z0-9]{8}\b/nat-<id>/g'
  's/\bins-[a-z0-9]{8}\b/ins-<id>/g'
  's/\blhins-[a-z0-9]+/lhins-<id>/g'
  's/\b43\.(167|156)\.[0-9]{1,3}\.[0-9]{1,3}\b/203.0.113.10/g'
  's/\b10\.0\.(16\.9|12\.[0-9]{1,3})\b/10.0.0.x/g'
  's|benchmark-upload-[a-z0-9]+\.tencentcloudcr\.com|registry.example.com|g'
  's|benchmark-upload-[a-z0-9]+|registry.example.com|g'
)

# 扫描规则（与 RULES 一一对应；占位符 `<id>` 不会命中）
SCAN='\b(cls|vpc|subnet|ins|nat|sg|cfs|lhins)-[a-z0-9]{8,}|\b43\.(167|156)\.[0-9]|\b10\.0\.(16\.9|12\.[0-9]{1,3})\b|benchmark-upload-'

apply() {
  local changed=0 f orig
  while IFS= read -r -d '' f; do
    case "$f" in *.png|*.jpg|*.gz|*.tar|*.safetensors) continue ;; esac
    [ -f "$f" ] || continue
    grep -qE "$SCAN" "$f" 2>/dev/null || continue
    orig=$(md5sum "$f" | cut -d' ' -f1)
    local args=()
    for r in "${RULES[@]}"; do args+=(-e "$r"); done
    sed -i -E "${args[@]}" "$f"
    if [ "$(md5sum "$f" | cut -d' ' -f1)" != "$orig" ]; then
      echo "  脱敏: $f"
      changed=$((changed + 1))
    fi
  done < <(git ls-files -z)
  echo "脱敏文件数: $changed"
}

check() {
  echo "=== 残留学检查（应为 0 命中；排除本脚本的正则字面量）==="
  local hits
  hits=$(git ls-files -z | xargs -0 grep -lE "$SCAN" 2>/dev/null \
         | grep -v "^scripts/sanitize_for_publish.sh$")
  if [ -z "$hits" ]; then
    echo "✅ 0 命中——可安全发布"
  else
    echo "⚠️ 以下文件仍有未脱敏内容："
    echo "$hits" | head -20
  fi
}

case "${1:-apply}" in
  --check) check ;;
  *) git add -A >/dev/null 2>&1; echo "=== 执行脱敏 ==="; apply; git add -A >/dev/null 2>&1; check ;;
esac
