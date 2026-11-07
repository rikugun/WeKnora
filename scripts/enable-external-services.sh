#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'EOF'
Start WeKnora with SearXNG, Neo4j, Qdrant, and RustFS on 192.168.100.97.

Usage:
  scripts/enable-external-services.sh

The script copies .env.example to .env when needed, appends local overrides,
refreshes the managed external-services block, and validates the merged
Compose configuration.
Run it again after changing .env.local.
EOF
  exit
fi

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env
fi

local_env="$(mktemp)"
managed_env="$(mktemp)"
trap 'rm -f "$local_env" "$local_env.tmp" "$managed_env"' EXIT

grep -v '^# Local external-services profile\.' .env > "$local_env"

# .env.local is authoritative: drop earlier assignments for every key it sets.
keys="$(grep -vE '^\s*(#|$)' .env.local | cut -d= -f1 | tr '\n' '|')"
keys="${keys%|}"
awk -v keys="^(${keys})=" '
  $0 !~ keys { print }
' "$local_env" > "$local_env.tmp" && mv "$local_env.tmp" "$local_env"

awk '
  /^# >>> WeKnora external services \(managed block\) >>>$/ { in_block = 1; next }
  /^# <<< WeKnora external services \(managed block\) <<<$/ { in_block = 0; next }
  !in_block { print }
' "$local_env" > "$managed_env"

printf '\n# >>> WeKnora external services (managed block) >>>\n' >> "$managed_env"
cat .env.local >> "$managed_env"
printf '# <<< WeKnora external services (managed block) <<<\n' >> "$managed_env"
mv "$managed_env" .env

docker compose \
  -f docker-compose.yml \
  -f docker-compose.external-services.yml \
  --profile external-services \
  config >/dev/null

echo "External-services configuration is ready."
echo "SearXNG provider Instance URL: ${SEARXNG_INSTANCE_URL:-http://192.168.100.97:11080}"
