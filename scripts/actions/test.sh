#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/actions/common.sh
source "$SCRIPT_DIRECTORY/common.sh"

run_preflight_checks

skip_arguments=()
for specifier in "${OPALBASE_LIVE_TEST_SPECIFIERS[@]}"; do
  skip_arguments+=(--skip "$specifier")
done

echo "Testing OpalBase (default lane; skipping live network tests)"
swift test "${SWIFTPM_SHARED_ARGUMENTS[@]}" "${skip_arguments[@]}"
