#!/usr/bin/env bash
# ci-check.sh - Continuous Integration validation script
#
# Purpose: Run 3 essential checks in sequence for CI/CD pipelines
# Expected runtime: ~3-5 seconds
# Exit codes: 0 = all pass, 1 = any failure
#
# Checks performed:
#   1. verify.sh quick    - Basic file structure validation (target: <100ms)
#   2. health-check.sh    - Tool and environment validation (target: ~1-2s)
#   3. validate-policies.sh - Policy file integrity (target: ~1-2s)

set -uo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track overall status
OVERALL_STATUS=0
START_TIME=$(date +%s)

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Results array (indexed array for Bash 3.2 compatibility)
CHECK_NAMES=()
CHECK_STATUSES=()
CHECK_DURATIONS=()

# Helper function to run a check and track results
run_check() {
    local check_name="$1"
    shift
    local check_args=("$@")
    local check_start check_end check_duration

    echo -e "${BLUE}[CI-CHECK]${NC} Running: $check_name"

    check_start=$(date +%s)

    # Run the check and capture exit code
    set +e
    bash "${check_args[@]}" > /dev/null 2>&1
    local exit_code=$?
    set -e

    check_end=$(date +%s)
    check_duration=$((check_end - check_start))

    if [ $exit_code -eq 0 ]; then
        CHECK_NAMES+=("$check_name")
        CHECK_STATUSES+=("PASS")
        CHECK_DURATIONS+=("$check_duration")

        echo -e "${GREEN}✓${NC} $check_name passed (${check_duration}s)"
        return 0
    else
        CHECK_NAMES+=("$check_name")
        CHECK_STATUSES+=("FAIL")
        CHECK_DURATIONS+=("$check_duration")

        echo -e "${RED}✗${NC} $check_name failed (${check_duration}s)"
        OVERALL_STATUS=1
        return 1
    fi
}

# Print header
echo ""
echo "======================================"
echo "   Claude Factory CI Check Suite"
echo "======================================"
echo ""

# Check 1: verify.sh quick
if [ -f "$SCRIPT_DIR/verify.sh" ]; then
    run_check "verify.sh quick" "$SCRIPT_DIR/verify.sh" "quick"
else
    echo -e "${RED}✗${NC} verify.sh not found at $SCRIPT_DIR/verify.sh"
    OVERALL_STATUS=1
fi

# Check 2: health-check.sh
if [ -f "$SCRIPT_DIR/health-check.sh" ]; then
    run_check "health-check.sh" "$SCRIPT_DIR/health-check.sh"
else
    echo -e "${RED}✗${NC} health-check.sh not found at $SCRIPT_DIR/health-check.sh"
    OVERALL_STATUS=1
fi

# Check 3: validate-policies.sh
if [ -f "$SCRIPT_DIR/validate-policies.sh" ]; then
    run_check "validate-policies.sh" "$SCRIPT_DIR/validate-policies.sh"
else
    echo -e "${RED}✗${NC} validate-policies.sh not found at $SCRIPT_DIR/validate-policies.sh"
    OVERALL_STATUS=1
fi

# Calculate total duration
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Print summary
echo ""
echo "======================================"
echo "   CI Check Summary"
echo "======================================"
echo ""

# Print results table
printf "%-25s %-10s %-10s\n" "Check" "Status" "Duration"
echo "--------------------------------------"

for i in "${!CHECK_NAMES[@]}"; do
    name="${CHECK_NAMES[$i]}"
    status="${CHECK_STATUSES[$i]}"
    duration="${CHECK_DURATIONS[$i]}s"

    if [ "$status" = "PASS" ]; then
        printf "%-25s ${GREEN}%-10s${NC} %-10s\n" "$name" "$status" "$duration"
    else
        printf "%-25s ${RED}%-10s${NC} %-10s\n" "$name" "$status" "$duration"
    fi
done

echo "--------------------------------------"
printf "%-25s %-10s %-10s\n" "TOTAL" "" "${TOTAL_DURATION}s"
echo ""

# Final status
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ All CI checks passed${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some CI checks failed${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  - Review failed check output above"
    echo "  - Run individual scripts with verbose output:"
    echo "    - bash .claude/scripts/verify.sh quick"
    echo "    - bash .claude/scripts/health-check.sh"
    echo "    - bash .claude/scripts/validate-policies.sh"
    echo "  - Consult TROUBLESHOOTING.md for common issues"
    echo ""
    exit 1
fi
