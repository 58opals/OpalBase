#!/bin/sh
set -eu

usage() {
    printf '%s\n' 'usage: scripts/validate.sh [--list] [develop | focused IDENTIFIER | assurance]' \
        'develop runs representative offline contracts; focused uses a literal identifier substring.' \
        'assurance runs the complete offline suite. --list discovers and shows the selection only.'
}
list_only=false
if [ "${1:-}" = --help ] || [ "${1:-}" = -h ]; then usage; exit 0; fi
if [ "${1:-}" = --list ]; then list_only=true; shift; fi
lane=${1:-develop}
[ "$#" -eq 0 ] || shift
case "$lane" in
    develop|assurance) [ "$#" -eq 0 ] || { usage >&2; exit 64; } ;;
    focused)
        [ "$#" -eq 1 ] && [ -n "$1" ] || { usage >&2; exit 64; }
        case "$1" in -*|*[[:cntrl:]]*) usage >&2; exit 64 ;; esac
        literal=$1
        ;;
    *) usage >&2; exit 64 ;;
esac

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$repo_root"
scratch=${OPAL_VALIDATION_SCRATCH_PATH:-"$repo_root/.build/validation"}
case "$scratch" in /*) ;; *) printf '%s\n' 'OPAL_VALIDATION_SCRATCH_PATH must be absolute.' >&2; exit 64 ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/opal-validation.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# SwiftPM must use this candidate's tracked graph; discovery also compiles the test products.
git ls-files --error-unmatch -- Package.resolved >/dev/null
cp Package.resolved "$work/Package.resolved"
test_command() {
    env -u SDKROOT OPAL_RUN_LIVE_NETWORK_TESTS=0 OPAL_RUN_EXTENDED_LIVE_NETWORK_TESTS=0 /usr/bin/xcrun swift test --scratch-path "$scratch" \
        --force-resolved-versions --jobs 2 --no-parallel "$@"
}
test_command list >"$work/discovered"
grep -E '^OpalBase(CoreTests|LocalTests|NetworkTests)[.]' "$work/discovered" >"$work/all"
case "$lane" in
    develop) filter='[.](PublicAPISmokeValidator|BCHDurableContractsTests|WalletSecurityProfileValidator)/'
        grep -E -- "$filter" "$work/all" >"$work/selected" || { printf '%s\n' 'Development selection matched no tests.' >&2; exit 1; } ;;
    focused)
        grep -F -- "$literal" "$work/all" >"$work/selected" || { printf '%s\n' 'Focused identifier matched no tests.' >&2; exit 1; }
        # SwiftPM takes a regular expression; escape the literal used for discovery.
        filter=$(printf '%s' "$literal" | sed 's/[][\\.^$*+?{}()|]/\\&/g')
        ;;
    assurance) cp "$work/all" "$work/selected" ;;
esac
total=$(wc -l <"$work/all" | tr -d ' ')
selected=$(wc -l <"$work/selected" | tr -d ' ')
[ "$selected" -gt 0 ] || { printf '%s\n' 'Refusing an empty test selection.' >&2; exit 1; }
cmp Package.resolved "$work/Package.resolved"
printf '%s\n' "OpalBase validation: $lane; $selected / $total discovered definitions selected; live network disabled."
if [ "$lane" != assurance ]; then
    printf '%s\n' 'This is focused feedback, not full-suite assurance.'
fi
if [ "$list_only" = true ]; then
    cat "$work/selected"
    printf '%s\n' 'Discovery only; no test execution result.'
elif [ "$lane" = assurance ]; then
    test_command --skip-build --xunit-output "$work/results.xml"
else
    test_command --skip-build --filter "$filter" --xunit-output "$work/results.xml"
fi
if [ "$list_only" = false ]; then
    executed=0
    for result in "$work"/results*.xml; do
        [ -f "$result" ] || continue
        count=$(/usr/bin/xmllint --nonet --xpath 'count(//testcase[not(skipped)])' "$result") || exit 65
        case "$count" in ''|*[!0-9]*) printf '%s\n' 'Invalid test execution report.' >&2; exit 65 ;; esac
        executed=$((executed + count))
    done
    [ "$executed" -gt 0 ] || { printf '%s\n' 'No non-skipped test cases executed; refusing a successful result.' >&2; exit 65; }
    printf '%s\n' "Executed $executed non-skipped test cases."
fi
cmp Package.resolved "$work/Package.resolved"
