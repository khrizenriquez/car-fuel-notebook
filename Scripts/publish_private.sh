#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

remote_name="origin"
branch="main"
remote_url=""
dry_run="false"
skip_local_gate="false"
skip_privacy_check="false"

usage() {
  cat <<'USAGE'
Usage: Scripts/publish_private.sh <remote-url> [--remote origin] [--branch main] [--skip-local-gate] [--skip-privacy-check] [--dry-run]

Runs the full private publishing flow:
  1. local verification gate
  2. safe private remote setup
  3. git push
  4. remote GitHub Actions verification

Options:
  --remote NAME          Remote name to configure/use. Defaults to origin.
  --branch NAME          Branch to push and verify. Defaults to main.
  --skip-local-gate      Skip Scripts/verify_local.sh. Use only after a recent passing run.
  --skip-privacy-check   Pass through to setup_private_remote.sh after manually confirming the repo is private.
  --dry-run              Print and validate the plan without changing remotes or pushing.
USAGE
}

fail() {
  echo "[publish] ERROR: $*" >&2
  exit 1
}

info() {
  echo "[publish] $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      remote_name="${2:-}"
      [[ -n "$remote_name" ]] || fail "Missing value for --remote."
      shift
      ;;
    --branch)
      branch="${2:-}"
      [[ -n "$branch" ]] || fail "Missing value for --branch."
      shift
      ;;
    --skip-local-gate)
      skip_local_gate="true"
      ;;
    --skip-privacy-check)
      skip_privacy_check="true"
      ;;
    --dry-run)
      dry_run="true"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      fail "Unknown option: $1"
      ;;
    *)
      if [[ -n "$remote_url" ]]; then
        fail "Only one remote URL is supported."
      fi
      remote_url="$1"
      ;;
  esac
  shift
done

[[ -n "$remote_url" ]] || {
  usage >&2
  exit 2
}

setup_args=("$remote_url" --remote "$remote_name")
if [[ "$skip_privacy_check" == "true" ]]; then
  setup_args+=(--skip-privacy-check)
fi

if [[ "$dry_run" == "true" ]]; then
  info "Dry run: validating remote setup without changing git config."
  Scripts/setup_private_remote.sh "${setup_args[@]}" --dry-run
  if [[ "$skip_local_gate" == "true" ]]; then
    info "Would skip local verification gate."
  else
    info "Would run: Scripts/verify_local.sh"
  fi
  info "Would run: Scripts/setup_private_remote.sh ${remote_url} --remote ${remote_name}"
  info "Would run: git push -u ${remote_name} ${branch}"
  info "Would run: Scripts/check_remote_ci.sh --branch ${branch} --wait"
  exit 0
fi

if [[ "$skip_local_gate" == "true" ]]; then
  info "Skipping local verification gate by request."
else
  Scripts/verify_local.sh
fi

Scripts/setup_private_remote.sh "${setup_args[@]}"

git push -u "$remote_name" "$branch"

Scripts/check_remote_ci.sh --branch "$branch" --wait

info "Private publish flow complete."
