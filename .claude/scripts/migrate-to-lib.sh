#!/usr/bin/env bash
set -euo pipefail

# migrate-to-lib.sh — Migrate test scripts to use shared test framework
# This is a one-time migration script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

migrate_test_script() {
  local file="$1"
  echo "Migrating $file..."

  # Create backup
  cp "$file" "${file}.pre-lib-migration"

  # Find the line where test framework functions end
  # Look for the first test function or main test section
  local framework_end=$(grep -n "^# ============================================================" "$file" | head -3 | tail -1 | cut -d: -f1)

  if [[ -z "$framework_end" ]]; then
    echo "  ⚠️  Could not find framework end marker, skipping"
    return 1
  fi

  # Extract header (lines 1 to framework start)
  local header_end=$(grep -n "^# Test counters\|^# Colors" "$file" | head -1 | cut -d: -f1)
  if [[ -z "$header_end" ]]; then
    echo "  ⚠️  Could not find header end, skipping"
    return 1
  fi
  header_end=$((header_end - 1))

  # Create new file with header + library source + rest
  {
    # Header
    head -n "$header_end" "$file"
    echo ""
    echo "# Load shared test framework"
    echo "source \"\$SCRIPT_DIR/lib/test-framework.sh\""
    echo ""
    # Rest of file after framework functions
    tail -n +$((framework_end + 1)) "$file"
  } > "${file}.new"

  # Replace original
  mv "${file}.new" "$file"
  echo "  ✓ Migrated successfully"
}

# Migrate remaining test scripts
for script in test-logging.sh test-install.sh test-secret-surfaces.sh test-direct-run-preflight.sh test-env-claude.sh test-log-observability.sh; do
  if [[ -f "$SCRIPT_DIR/$script" ]]; then
    if grep -q "source.*lib/test-framework.sh" "$SCRIPT_DIR/$script"; then
      echo "Skipping $script (already migrated)"
    else
      migrate_test_script "$SCRIPT_DIR/$script"
    fi
  fi
done

echo ""
echo "Migration complete!"
