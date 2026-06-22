#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

branch="main"
workflow="ios-ci.yml"

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
    -h|--help)
      echo "Usage: Scripts/check_remote_ci.sh [--branch main] [--workflow ios-ci.yml]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: Scripts/check_remote_ci.sh [--branch main] [--workflow ios-ci.yml]" >&2
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

run_json="$(
  gh run list \
    --workflow "$workflow" \
    --branch "$branch" \
    --limit 1 \
    --json databaseId,status,conclusion,url,headSha
)"

run_id="$(
  python3 - "$run_json" <<'PY'
import json
import sys

runs = json.loads(sys.argv[1])
if not runs:
    raise SystemExit(1)
print(runs[0]["databaseId"])
PY
)" || fail "No workflow run found for ${workflow} on branch ${branch}."

run_status="$(
  python3 - "$run_json" <<'PY'
import json
import sys

run = json.loads(sys.argv[1])[0]
print(run["status"])
PY
)"

run_conclusion="$(
  python3 - "$run_json" <<'PY'
import json
import sys

run = json.loads(sys.argv[1])[0]
print(run.get("conclusion") or "")
PY
)"

run_url="$(
  python3 - "$run_json" <<'PY'
import json
import sys

run = json.loads(sys.argv[1])[0]
print(run["url"])
PY
)"

info "Run URL: ${run_url}"

if [[ "$run_status" != "completed" ]]; then
  fail "Latest workflow run is ${run_status}, not completed yet."
fi

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
