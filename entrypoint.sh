#!/bin/sh
set -e

WORK_DIR="/app/worker-code"
DATA_DIR="/app/data"

mkdir -p "$DATA_DIR"


# === 2. 可选：读取分支/标签（支持空值）===
BRANCH="${GIT_BRANCH:-}"

# === 3. 克隆仓库 ===
echo "📦 Cloning repository: $GIT_REPO"

if [ -n "$BRANCH" ]; then
  echo "🌿 Cloning branch/tag: '$BRANCH'"
  git clone --depth=1 --single-branch --branch "$BRANCH" "$GIT_REPO" "$WORK_DIR"
else
  echo "🌱 Cloning default branch (GIT_BRANCH not set)"
  git clone --depth=1 "$GIT_REPO" "$WORK_DIR"
fi

cd "$WORK_DIR"

# 安装依赖（如果存在 package.json）
if [ -f "package.json" ]; then
  echo "📦 Installing dependencies..."
  npm install
else
  echo "⚠️ No package.json found. Make sure wrangler is available globally."
fi

export WORKER_SCRIPT
export ENV_VARS

# 导出所有可能的绑定变量（供 start.sh 使用）
export $(env | grep -E '^(ENV_|KV_|R2_|D1_|DO_|QUEUE_)' | cut -d= -f1)

exec /app/start.sh