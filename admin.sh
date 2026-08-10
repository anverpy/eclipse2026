#!/usr/bin/env bash
# admin.sh — single entrypoint for infra + ops on the eclipse2026 pipeline.
set -euo pipefail

PROJECT="eclipse2026"
export AWS_REGION="${AWS_REGION:-eu-west-1}"
# CLI v1 only honors AWS_DEFAULT_REGION (AWS_REGION is a v2/SDK-only addition).
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export AWS_PROFILE="${AWS_PROFILE:-default}"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/terraform"

# source registry — single source of truth for lambda function names.
# add a source here and every command below picks it up automatically.
declare -A SOURCES=(
  [ree]="${PROJECT}-ree-poller"
  [aemet]="${PROJECT}-aemet-poller"
  [dgt_traffic]="${PROJECT}-dgt-traffic-poller"
  [trends]="${PROJECT}-trends-poller"
  [dgt_camera]="${PROJECT}-dgt-camera-poller"
  [aggregator]="${PROJECT}-aggregator"
)

usage() {
  cat <<EOF
admin.sh <command> [args]

Infra:
  init                  terraform init
  plan                  terraform plan
  deploy                terraform apply
  destroy               terraform destroy (asks confirmation — irreversible for undownloaded data)
  status                terraform state list

Ops:
  invoke <source>       invoke one lambda with a test payload
  invoke-all            invoke all sources in sequence, print pass/fail summary
  logs <source> [mins]  tail cloudwatch logs for a source (default: last 10 min, follows)
  cost                  current month spend + budget status
  dry-run               full-cycle simulation: invoke all sources once
  local [source]        run handler(s) locally against fixtures — no AWS, no network
                         (omit source to run all; see scripts/local_dev.py)
  preview [port]        serve docs/ at http://localhost:<port>/ (default 8000)
                         — for viewing frontend changes; Ctrl+C to stop

Sources: ${!SOURCES[*]}
EOF
}

require_source() {
  local s="$1"
  if [[ -z "${SOURCES[$s]:-}" ]]; then
    echo "unknown source '$s'. valid: ${!SOURCES[*]}" >&2
    exit 1
  fi
}

cmd_init()   { terraform -chdir="$TF_DIR" init; }
cmd_plan()   { terraform -chdir="$TF_DIR" plan; }
cmd_deploy() { terraform -chdir="$TF_DIR" apply; }
cmd_status() { terraform -chdir="$TF_DIR" state list; }

cmd_destroy() {
  read -rp "destroy ALL infra for ${PROJECT}? data in S3/DynamoDB not yet downloaded will be lost. type 'yes' to confirm: " ans
  [[ "$ans" == "yes" ]] || { echo "aborted"; exit 1; }
  terraform -chdir="$TF_DIR" destroy
}

cmd_invoke() {
  local s="$1"; require_source "$s"
  local fn="${SOURCES[$s]}"
  local out="/tmp/${PROJECT}_${s}_invoke.json"
  echo "invoking $fn..."
  # --cli-binary-format only exists on CLI v2 (v1 doesn't base64-wrap --payload).
  local binfmt_args=()
  aws --version 2>&1 | grep -q '^aws-cli/2' && binfmt_args=(--cli-binary-format raw-in-base64-out)
  aws lambda invoke \
    --function-name "$fn" \
    --payload '{"source":"admin.sh","mode":"test"}' \
    "${binfmt_args[@]}" \
    "$out" >/dev/null
  cat "$out"
}

cmd_invoke_all() {
  local failed=()
  for s in "${!SOURCES[@]}"; do
    echo "--- $s ---"
    cmd_invoke "$s" || failed+=("$s")
  done
  echo
  if [[ ${#failed[@]} -eq 0 ]]; then
    echo "all ${#SOURCES[@]} sources OK"
  else
    echo "FAILED: ${failed[*]}"
    return 1
  fi
}

cmd_logs() {
  local s="$1"; require_source "$s"
  local mins="${2:-10}"
  aws logs tail "/aws/lambda/${SOURCES[$s]}" --since "${mins}m" --follow
}

cmd_cost() {
  local account_id
  account_id="$(aws sts get-caller-identity --query Account --output text)"
  echo "=== budget status ==="
  aws budgets describe-budgets --account-id "$account_id" \
    --query 'Budgets[].{Name:BudgetName,Limit:BudgetLimit.Amount,Spent:CalculatedSpend.ActualSpend.Amount}' \
    --output table 2>/dev/null || echo "no budget found — run './admin.sh deploy' first"

  echo "=== month-to-date cost ==="
  aws ce get-cost-and-usage \
    --time-period Start="$(date -u +%Y-%m-01)",End="$(date -u +%Y-%m-%d)" \
    --granularity MONTHLY \
    --metrics UnblendedCost \
    --output table
}

cmd_dry_run() {
  echo "=== dry run: $(date -u +%FT%TZ) ==="
  cmd_invoke_all
  echo "=== tail logs per-source manually if any failed: ./admin.sh logs <source> ==="
}

cmd_local() {
  local s="${1:-}"
  if [[ -n "$s" ]]; then
    require_source "$s"
    python3 "$(dirname "${BASH_SOURCE[0]}")/scripts/local_dev.py" run "$s"
  else
    python3 "$(dirname "${BASH_SOURCE[0]}")/scripts/local_dev.py" run-all
  fi
}

cmd_preview() {
  local port="${1:-8000}"
  local docs_dir
  docs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/docs" && pwd)"
  echo "serving $docs_dir at http://localhost:${port}/ (Ctrl+C to stop)"
  ( cd "$docs_dir" && python3 -m http.server "$port" )
}

case "${1:-}" in
  init)       cmd_init ;;
  plan)       cmd_plan ;;
  deploy)     cmd_deploy ;;
  destroy)    cmd_destroy ;;
  status)     cmd_status ;;
  invoke)     shift; cmd_invoke "$@" ;;
  invoke-all) cmd_invoke_all ;;
  logs)       shift; cmd_logs "$@" ;;
  cost)       cmd_cost ;;
  dry-run)    cmd_dry_run ;;
  local)      shift; cmd_local "$@" ;;
  preview)    shift; cmd_preview "$@" ;;
  *)          usage; exit 1 ;;
esac
