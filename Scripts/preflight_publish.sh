#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

allow_dirty="false"
require_remote="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-dirty)
      allow_dirty="true"
      ;;
    --require-remote)
      require_remote="true"
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: Scripts/preflight_publish.sh [--allow-dirty] [--require-remote]" >&2
      exit 2
      ;;
  esac
  shift
done

info() {
  echo "[preflight] $*"
}

fail() {
  echo "[preflight] ERROR: $*" >&2
  exit 1
}

warn() {
  echo "[preflight] WARN: $*" >&2
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "Required file is missing: $path"
}

require_gitignore_pattern() {
  local pattern="$1"
  rg -q --fixed-strings "$pattern" .gitignore || fail ".gitignore is missing pattern: $pattern"
}

info "Checking git repository state"
git rev-parse --is-inside-work-tree >/dev/null

if [[ "$allow_dirty" != "true" ]] && [[ -n "$(git status --porcelain)" ]]; then
  fail "Working tree is not clean. Commit or stash changes before publishing."
fi

if [[ -z "$(git remote -v)" ]]; then
  if [[ "$require_remote" == "true" ]]; then
    fail "No git remote is configured. Add a private GitHub remote before publishing."
  fi
  warn "No git remote is configured yet. Add a private GitHub remote before the first push."
fi

info "Checking required repository files"
require_file "README.md"
require_file "SECURITY.md"
require_file ".github/workflows/ios-ci.yml"
require_file "Scripts/verify_local.sh"
require_file "Scripts/check_core_coverage.sh"
require_file "Scripts/select_ios_simulator.sh"
require_file "docs/superpowers/specs/2026-06-21-cartrack-ios-design.md"
require_file "docs/testing/ocr-fixtures.md"

for adr in 001 002 003 004 005 006; do
  matches=(docs/adr/ADR-"$adr"-*.md)
  [[ -e "${matches[0]}" ]] || fail "Missing ADR-$adr"
done

info "Checking .gitignore safety rules"
require_gitignore_pattern ".env"
require_gitignore_pattern ".env.*"
require_gitignore_pattern "*.sqlite"
require_gitignore_pattern "*.db"
require_gitignore_pattern "Captures/"
require_gitignore_pattern "Invoices/"
require_gitignore_pattern "Odometer/"
require_gitignore_pattern "FuelLevel/"
require_gitignore_pattern ".build/"
require_gitignore_pattern "xcuserdata/"

info "Checking that private evidence files are not tracked"
if git ls-files | rg -i '(invoice|odometer|fuellevel|capture|receipt|factura).*\.(heic|heif|jpg|jpeg|png|tiff|pdf)$'; then
  fail "Potential private evidence image/PDF is tracked. Remove it before publishing."
fi

info "Running basic secret scan"
if rg -n \
  -g '!/.build/**' \
  -g '!/Cartrack.xcodeproj/project.pbxproj' \
  -g '!/Package.resolved' \
  'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY|API[_-]?KEY\s*=|SECRET\s*=|TOKEN\s*=|PASSWORD\s*=' \
  .; then
  fail "Potential secret found. Review and remove it before publishing."
fi

info "Checking CI workflow posture"
rg -q "permissions:" .github/workflows/ios-ci.yml || fail "CI workflow should declare permissions."
rg -q "contents: read" .github/workflows/ios-ci.yml || fail "CI workflow should use read-only contents permission."
rg -q "CODE_SIGNING_ALLOWED=NO" .github/workflows/ios-ci.yml || fail "CI workflow should not require signing."
rg -q "Scripts/check_core_coverage.sh 90" .github/workflows/ios-ci.yml || fail "CI workflow should enforce 90% core coverage."

info "Publish preflight passed"
