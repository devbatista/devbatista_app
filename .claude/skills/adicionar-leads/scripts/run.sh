#!/usr/bin/env bash
# Roda leads.rb com o payload JSON no banco local ou no de produção (Railway).
#
#   run.sh local payload.json
#   run.sh production payload.json
set -euo pipefail

env="${1:?informe local ou production}"
payload="${2:?informe o arquivo JSON}"
dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$dir/../../../.." && pwd)"

script="$(mktemp)"
trap 'rm -f "$script"' EXIT
{
  printf 'require "base64"\nrequire "json"\n'
  printf 'PAYLOAD = JSON.parse(Base64.strict_decode64("%s"))\n' "$(base64 < "$payload" | tr -d '\n')"
  cat "$dir/leads.rb"
} > "$script"

case "$env" in
  local)
    cd "$root" && bin/rails runner "$script"
    ;;
  production)
    encoded="$(base64 < "$script" | tr -d '\n')"
    railway ssh -- "echo $encoded | base64 -d > /tmp/adicionar-leads.rb && bin/rails runner /tmp/adicionar-leads.rb; rm -f /tmp/adicionar-leads.rb" 2>&1 |
      grep -v -i -e "railway agent" -e "setup agent" -e "more effectively" -e "SSH key" -e "instance profile" -e '^$' || true
    ;;
  *)
    echo "ambiente inválido: $env (use local ou production)" >&2
    exit 1
    ;;
esac
