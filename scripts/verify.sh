#!/usr/bin/env bash
# Definition of Done for the TradingChart package.
#
#   scripts/verify.sh          build + all tests (blocking), then the demo app if Examples/TradingChartDemo exists
#   scripts/verify.sh --fast   build the package and the demo, without running the tests
#
# The package is iOS-only, so everything runs through xcodebuild on an iOS Simulator.
# Environment overrides:
#   DESTINATION   xcodebuild destination (default: the first booted iPhone, else an available one from scripts/pick-simulator.sh)
#   DEMO_SCHEME   scheme of the demo project (default: TradingChartDemo)
# Exit code: 0 on success, 1 on the first failing step.

set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

FAST=0
for arg in "$@"; do
    case "$arg" in
        --fast) FAST=1 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "verify.sh: unknown argument '$arg' (supported: --fast)" >&2; exit 2 ;;
    esac
done

PACKAGE_SCHEME="TradingChart-Package"
DEMO_DIR="Examples/TradingChartDemo"
DEMO_SCHEME="${DEMO_SCHEME:-TradingChartDemo}"

detect_destination() {
    local udid
    udid="$(xcrun simctl list devices booted 2>/dev/null \
        | grep -m1 'iPhone' \
        | grep -Eo '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' \
        | head -n1)"
    if [ -z "$udid" ]; then
        udid="$("$ROOT/scripts/pick-simulator.sh" 2>/dev/null)" || udid=""
    fi
    [ -n "$udid" ] && echo "platform=iOS Simulator,id=$udid"
}

DESTINATION="${DESTINATION:-$(detect_destination)}"
if [ -z "$DESTINATION" ]; then
    echo "verify: FAIL - no iPhone simulator is booted or available (install one, or set DESTINATION)"
    exit 1
fi
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tradingchart-verify.XXXXXX")"
trap 'rm -rf "$LOG_DIR"' EXIT

HAS_XCBEAUTIFY=0
command -v xcbeautify >/dev/null 2>&1 && HAS_XCBEAUTIFY=1

echo "verify: destination = $DESTINATION"

# run_step <name> <summary-grep-pattern> <command...>
# Streams through xcbeautify when available; otherwise keeps a log and prints only the summary
# on success or the errors plus the log tail on failure.
run_step() {
    local name="$1" summary_pattern="$2"
    shift 2
    local log="$LOG_DIR/$(echo "$name" | tr -c 'A-Za-z0-9' '_').log"

    echo "verify: $name ..."
    local status
    if [ "$HAS_XCBEAUTIFY" -eq 1 ]; then
        "$@" 2>&1 | tee "$log" | xcbeautify --quiet
        status="${PIPESTATUS[0]}"
    else
        "$@" >"$log" 2>&1
        status=$?
    fi

    if [ "$status" -ne 0 ]; then
        echo "verify: FAIL - $name (exit $status)"
        if [ "$HAS_XCBEAUTIFY" -eq 0 ]; then
            grep -E "error:|✘|failed|FAILED" "$log" | sort -u | head -40
            echo "--- last 25 lines of the log ---"
            tail -n 25 "$log"
        fi
        exit 1
    fi

    if [ "$HAS_XCBEAUTIFY" -eq 0 ] && [ -n "$summary_pattern" ]; then
        grep -E "$summary_pattern" "$log" | tail -n 5
    fi
    echo "verify: PASS - $name"
}

if [ "$FAST" -eq 1 ]; then
    run_step "package build" "BUILD (SUCCEEDED|FAILED)" \
        xcodebuild -scheme "$PACKAGE_SCHEME" -destination "$DESTINATION" build
else
    run_step "package build + tests" "Test run with|TEST (SUCCEEDED|FAILED)" \
        xcodebuild -scheme "$PACKAGE_SCHEME" -destination "$DESTINATION" build test
fi

if [ -f "$DEMO_DIR/project.yml" ]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "verify: FAIL - $DEMO_DIR/project.yml exists but xcodegen is not installed (brew install xcodegen)"
        exit 1
    fi
    run_step "demo xcodegen" "" \
        xcodegen generate --spec "$DEMO_DIR/project.yml" --quiet
    run_step "demo build" "BUILD (SUCCEEDED|FAILED)" \
        xcodebuild -project "$DEMO_DIR/$DEMO_SCHEME.xcodeproj" -scheme "$DEMO_SCHEME" \
            -destination "$DESTINATION" build
fi

echo "verify: OK ($([ "$FAST" -eq 1 ] && echo fast || echo full))"
exit 0
