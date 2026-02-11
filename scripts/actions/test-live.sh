#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/actions/common.sh
source "$SCRIPT_DIRECTORY/common.sh"

run_preflight_checks

live_filter=""
for specifier in "${OPALBASE_LIVE_TEST_SPECIFIERS[@]}"; do
  if [[ -z "$live_filter" ]]; then
    live_filter="$specifier"
  else
    live_filter="$live_filter|$specifier"
  fi
done

if [[ -z "$live_filter" ]]; then
  echo "error: no live test specifiers configured" >&2
  exit 1
fi

echo "Testing OpalBase (live network lane)"
swift test "${SWIFTPM_SHARED_ARGUMENTS[@]}" --filter "$live_filter"
