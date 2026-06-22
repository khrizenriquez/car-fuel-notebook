#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

branch="main"
workflow="ios-ci.yml"
wait_for_completion="false"
timeout_seconds="900"
poll_interval="15"

usage() {
  cat <<'USAGE'
Usage: Scripts/check_remote_ci.sh [--branch main] [--workflow ios-ci.yml] [--wait] [--timeout-seconds 900] [--poll-interval 15]

Checks the latest GitHub Actions run and verifies Core Coverage plus iPhone App Tests are green.

Options:
  --branch NAME             Branch to inspect. Defaults to main.
  --workflow FILE           Workflow file/name to inspect. Defaults to ios-ci.yml.
  --wait                    Poll until the latest run completes or times out.
  --timeout-seconds VALUE   Maximum wait time for --wait. Defaults to 900.
  --poll-interval VALUE     Seconds between polls for --wait. Defaults to 15.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      branch="${2:-}"
      [[ -n "$branch" ]] || {
        echo "Missing value for --branch" >&2
        exit 2
      }
      shift
      ;;
    --workflow)
      workflow="${2:-}"
      [[ -n "$workflow" ]] || {
        echo "Missing value for --workflow" >&2
        exit 2
      }
      shift
      ;;
    --wait)
      wait_for_completion="true"
      ;;
    --timeout-seconds)
      timeout_seconds="${2:-}"
      [[ "$timeout_seconds" =~ ^[0-9]+$ && "$timeout_seconds" -gt 0 ]] || {
        echo "Missing or invalid value for --timeout-seconds" >&2
        exit 2
      }
      shift
      ;;
    --poll-interval)
      poll_interval="${2:-}"
      [[ "$poll_interval" =~ ^[0-9]+$ && "$poll_interval" -gt 0 ]] || {
        echo "Missing or invalid value for --poll-interval" >&2
        exit 2
      }
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

fail() {
  echo "[remote-ci] ERROR: $*" >&2
  exit 1
}

info() {
  echo "[remote-ci] $*"
}

git remote get-url origin >/dev/null 2>&1 || fail "No origin remote configured. Add the private GitHub remote first."
command -v gh >/dev/null || fail "GitHub CLI is required. Install gh or review Actions manually."
gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated. Run gh auth login."

info "Checking latest ${workflow} run on branch ${branch}"

start_epoch="$(date +%s)"

while true; do
  run_json="$(
    gh run list \
      --workflow "$workflow" \
      --branch "$branch" \
      --limit 1 \
      --json databaseId,status,conclusion,url,headSha
  )"

  run_summary="$(
    python3 - "$run_json" <<'PY'
import json
import sys

runs = json.loads(sys.argv[1])
if not runs:
    print("__missing__\tmissing\t\t")
else:
    run = runs[0]
    print("\t".join([
        str(run["databaseId"]),
        run["status"],
        run.get("conclusion") or "",
        run["url"],
    ]))
PY
  )"

  IFS=$'\t' read -r run_id run_status run_conclusion run_url <<< "$run_summary"

  if [[ "$run_status" == "completed" ]]; then
    break
  fi

  if [[ "$wait_for_completion" != "true" ]]; then
    if [[ "$run_id" == "__missing__" ]]; then
      fail "No workflow run found for ${workflow} on branch ${branch}."
    fi
    fail "Latest workflow run is ${run_status}, not completed yet."
  fi

  now_epoch="$(date +%s)"
  elapsed=$((now_epoch - start_epoch))
  if [[ "$elapsed" -ge "$timeout_seconds" ]]; then
    fail "Timed out after ${timeout_seconds}s waiting for ${workflow} on ${branch}. Last status: ${run_status}."
  fi

  if [[ "$run_id" == "__missing__" ]]; then
    info "No workflow run found yet. Waiting ${poll_interval}s..."
  else
    info "Run ${run_id} is ${run_status}. Waiting ${poll_interval}s..."
  fi

  sleep "$poll_interval"
done

info "Run URL: ${run_url}"

if [[ "$run_conclusion" != "success" ]]; then
  fail "Latest workflow conclusion is ${run_conclusion:-unknown}, expected success."
fi

jobs_json="$(gh run view "$run_id" --json jobs)"

python3 - "$jobs_json" <<'PY'
import json
import sys

expected = {"Core Coverage", "iPhone App Tests"}
jobs = json.loads(sys.argv[1]).get("jobs", [])
by_name = {job.get("name"): job for job in jobs}
missing = sorted(expected - set(by_name))
if missing:
    print(f"[remote-ci] ERROR: Missing expected jobs: {', '.join(missing)}", file=sys.stderr)
    raise SystemExit(1)

failed = []
for name in sorted(expected):
    job = by_name[name]
    if job.get("conclusion") != "success":
        failed.append(f"{name}={job.get('conclusion') or job.get('status') or 'unknown'}")

if failed:
    print(f"[remote-ci] ERROR: Expected jobs are not green: {', '.join(failed)}", file=sys.stderr)
    raise SystemExit(1)
PY

info "Remote CI passed: Core Coverage and iPhone App Tests are green"
