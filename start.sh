#!/bin/sh
set -e

WORKER_SCRIPT="${WORKER_SCRIPT:-_worker.js}"
ENV_VARS="${ENV_VARS:-}"
PORT="${PORT:-8080}"  # 👈 从环境变量读取，缺省为 8080

if [ ! -f "$WORKER_SCRIPT" ]; then
  echo "❌ ERROR: Worker script '$WORKER_SCRIPT' not found!" >&2
  exit 1
fi

[ -f wrangler.toml ] && rm wrangler.toml

# ==============================
# 构建 TOML 内容
# ==============================
TOML_CONTENT="name = \"dynamic-worker\"
main = \"$WORKER_SCRIPT\"
compatibility_date = \"2025-01-01\"
compatibility_flags = [\"nodejs_compat\"]"

# ---- [vars] for plain text env vars ----
VARS=""
# 来自 ENV_VARS="a=b,c=d"
if [ -n "$ENV_VARS" ]; then
  printf '%s\n' "$ENV_VARS" | tr ',' '\n' | while IFS= read -r pair; do
    case "$pair" in *=*) ;; *) continue ;; esac
    key="${pair%%=*}"; val="${pair#*=}"
    trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r\n'; }
    key="$(trim "$key")"; val="$(trim "$val")"
    val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
    VARS="$VARS
$key = \"$val\""
  done
fi

# 来自 ENV_XXX=yyy
for var in $(env | grep '^ENV_' | cut -d= -f1); do
  val=$(eval echo \$"$var")
  if [ -n "$val" ]; then
    key="${var#ENV_}"
    trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r\n'; }
    key="$(trim "$key")"
    val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
    VARS="$VARS
$key = \"$val\""
  fi
done

if [ -n "$VARS" ]; then
  TOML_CONTENT="$TOML_CONTENT

[vars]$VARS"
fi

# ---- KV Namespaces ----
KV=""
for var in $(env | grep '^KV_' | cut -d= -f1); do
  id=$(eval echo \$"$var")
  if [ -n "$id" ]; then
    binding="${var#KV_}"
    KV="$KV

[[kv_namespaces]]
binding = \"$binding\"
id = \"$id\""
  fi
done
TOML_CONTENT="$TOML_CONTENT$KV"

# ---- R2 Buckets ----
R2=""
for var in $(env | grep '^R2_' | cut -d= -f1); do
  bucket=$(eval echo \$"$var")
  if [ -n "$bucket" ]; then
    binding="${var#R2_}"
    R2="$R2

[[r2_buckets]]
binding = \"$binding\"
bucket_name = \"$bucket\""
  fi
done
TOML_CONTENT="$TOML_CONTENT$R2"

# ---- D1 Databases ----
D1=""
for var in $(env | grep '^D1_' | cut -d= -f1); do
  db_id=$(eval echo \$"$var")
  if [ -n "$db_id" ]; then
    binding="${var#D1_}"
    D1="$D1

[[d1_databases]]
binding = \"$binding\"
database_id = \"$db_id\""
  fi
done
TOML_CONTENT="$TOML_CONTENT$D1"

# ---- Durable Objects ----
DO=""
for var in $(env | grep '^DO_' | cut -d= -f1); do
  class_name=$(eval echo \$"$var")
  if [ -n "$class_name" ]; then
    binding="${var#DO_}"
    DO="$DO

[[durable_objects.bindings]]
name = \"$binding\"
class_name = \"$class_name\""
  fi
done
TOML_CONTENT="$TOML_CONTENT$DO"

# ---- Queues (Producers) ----
QUEUES=""
for var in $(env | grep '^QUEUE_' | cut -d= -f1); do
  queue_name=$(eval echo \$"$var")
  if [ -n "$queue_name" ]; then
    binding="${var#QUEUE_}"
    QUEUES="$QUEUES

[[queues.producers]]
binding = \"$binding\"
queue = \"$queue_name\""
  fi
done
TOML_CONTENT="$TOML_CONTENT$QUEUES"

# ==============================
# Write to file and start
# ==============================
echo "$TOML_CONTENT" > wrangler.toml

echo "✅ Generated wrangler.toml:" >&2
cat wrangler.toml >&2

echo "🚀 Starting Wrangler on port $PORT..." >&2
exec npx wrangler dev "$WORKER_SCRIPT" --port "$PORT" --host 0.0.0.0 --local