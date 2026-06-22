#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

remote_name="origin"
remote_url=""
dry_run="false"
replace_existing="false"
skip_privacy_check="false"

usage() {
  cat <<'USAGE'
Usage: Scripts/setup_private_remote.sh <remote-url> [--remote origin] [--replace-existing] [--dry-run] [--skip-privacy-check]

Adds the private GitHub remote safely, then runs Scripts/preflight_publish.sh --require-remote.

Options:
  --remote NAME            Remote name to configure. Defaults to origin.
  --replace-existing       Replace an existing remote URL instead of failing.
  --dry-run                Print what would happen without changing git config.
  --skip-privacy-check     Allow setup when gh cannot verify repository visibility.
USAGE
}

fail() {
  echo "[remote-setup] ERROR: $*" >&2
  exit 1
}

info() {
  echo "[remote-setup] $*"
}

warn() {
  echo "[remote-setup] WARN: $*" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      remote_name="${2:-}"
      [[ -n "$remote_name" ]] || fail "Missing value for --remote."
      shift
      ;;
    --replace-existing)
      replace_existing="true"
      ;;
    --dry-run)
      dry_run="true"
      ;;
    --skip-privacy-check)
      skip_privacy_check="true"
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

git rev-parse --is-inside-work-tree >/dev/null

if [[ "$dry_run" != "true" && -n "$(git status --porcelain)" ]]; then
  fail "Working tree is not clean. Commit or stash changes before configuring a publish remote."
fi

case "$remote_url" in
  git@github.com:*/*.git|git@github.com:*/*|https://github.com/*/*.git|https://github.com/*/*)
    ;;
  *)
    fail "Remote URL must look like a GitHub SSH or HTTPS repository URL."
    ;;
esac

existing_url=""
if existing_url="$(git remote get-url "$remote_name" 2>/dev/null)"; then
  if [[ "$existing_url" == "$remote_url" ]]; then
    info "Remote ${remote_name} already points to ${remote_url}"
  elif [[ "$replace_existing" == "true" ]]; then
    info "Remote ${remote_name} will be updated from ${existing_url} to ${remote_url}"
  else
    fail "Remote ${remote_name} already exists with a different URL. Use --replace-existing only if that is intentional."
  fi
else
  info "Remote ${remote_name} will be added as ${remote_url}"
fi

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  visibility="$(
    gh repo view "$remote_url" --json visibility --jq .visibility 2>/dev/null || true
  )"
  [[ -n "$visibility" ]] || fail "Could not inspect GitHub repository visibility. Confirm the repository exists and you have access."
  [[ "$visibility" == "PRIVATE" ]] || fail "GitHub reports repository visibility as ${visibility}, expected PRIVATE."
  info "GitHub visibility check passed: PRIVATE"
elif [[ "$skip_privacy_check" == "true" ]]; then
  warn "Skipping automated GitHub privacy check. Confirm the repository is private before pushing."
else
  fail "Cannot verify GitHub repository visibility. Install/authenticate gh or rerun with --skip-privacy-check after manually confirming the repo is private."
fi

if [[ "$dry_run" == "true" ]]; then
  info "Dry run complete. No git remote was changed."
  exit 0
fi

if [[ -n "$existing_url" && "$existing_url" != "$remote_url" ]]; then
  git remote set-url "$remote_name" "$remote_url"
elif [[ -z "$existing_url" ]]; then
  git remote add "$remote_name" "$remote_url"
fi

Scripts/preflight_publish.sh --require-remote

info "Remote setup complete. Next command: git push -u ${remote_name} main"
