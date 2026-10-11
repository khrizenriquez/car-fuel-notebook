#!/usr/bin/env bash
set -euo pipefail

# v2 must not accidentally acquire a real Supabase endpoint, project reference, or credential.
# v2.1 receives a new project after the local release candidate is accepted.
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

forbidden='supabase\.co|SUPABASE_(URL|KEY|PROJECT)|service[_-]?role|anon[_-]?key'
if rg -n -i "$forbidden" Cartrack CartrackCore Package.swift project.yml .github 2>/dev/null; then
  echo "Cloud readiness check failed: v2 must not contain a Supabase endpoint, project reference, or credential." >&2
  exit 1
fi

echo "Cloud readiness check passed: no remote Supabase configuration is present."
