# Test Harness — Infrastructure-Free E2E Testing

## Overview

This test harness provides **CLI shims** (mock binaries) for testing Ops MCP tools without requiring real infrastructure (no Kubernetes, Argo CD, PostgreSQL, AWS, etc.).

**Key Features:**
- Deterministic test outputs (no flaky tests)
- Fast execution (<60s for full suite)
- No external dependencies
- Automatic secret redaction testing
- PATH injection for transparent mocking

---

## Architecture

```
Test Script
    ↓
PATH=/path/to/shims:$PATH (inject shims first)
    ↓
server-ops.js calls execSafe("kubectl", [...])
    ↓
Shim receives call: shims/kubectl (bash script)
    ↓
Shim reads fixture: fixtures/kubectl/get-pods.json
    ↓
Shim returns fixture output
    ↓
Test asserts on output
```

---

## Directory Structure

```
.claude/scripts/test-harness/
├── README.md                    ← This file
├── shims/                       ← Mock CLI binaries
│   ├── kubectl                  ← Kubernetes CLI shim
│   ├── argocd                   ← Argo CD CLI shim
│   ├── argo                     ← Argo Workflows CLI shim
│   ├── psql                     ← PostgreSQL CLI shim
│   ├── gh                       ← GitHub CLI shim
│   ├── docker                   ← Docker CLI shim
│   ├── redis-cli                ← Redis CLI shim
│   ├── aws                      ← AWS CLI shim
│   ├── supabase                 ← Supabase CLI shim
│   └── sqlite3                  ← SQLite CLI shim
└── fixtures/                    ← Fixture outputs
    ├── kubectl/
    │   ├── version.json
    │   ├── get-pods.json
    │   ├── get-deployments.json
    │   └── timeout.trigger      ← Special file to simulate timeout
    ├── argocd/
    │   ├── version.txt
    │   ├── app-list.json
    │   └── app-get.json
    ├── secrets/                 ← Test fixtures with secrets
    │   ├── postgres-with-password.txt
    │   ├── aws-credentials.json
    │   └── redis-auth.txt
    └── ...
```

---

## How Shims Work

### Basic Shim Pattern

All shims follow this structure:

```bash
#!/usr/bin/env bash
# Shim: kubectl

SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_DIR="$SHIM_DIR/../fixtures/kubectl"

# Parse command
CMD="$1"
shift

case "$CMD" in
  version)
    cat "$FIXTURE_DIR/version.json"
    ;;
  get)
    RESOURCE="$1"
    if [[ "$RESOURCE" == "pods" ]]; then
      cat "$FIXTURE_DIR/get-pods.json"
    elif [[ "$RESOURCE" == "deployments" ]]; then
      cat "$FIXTURE_DIR/get-deployments.json"
    fi
    ;;
  *)
    echo "Error: Unknown kubectl command: $CMD" >&2
    exit 1
    ;;
esac
```

### Special Behaviors

**Simulating Timeouts:**
```bash
# If timeout.trigger file exists, sleep longer than timeout
if [[ -f "$FIXTURE_DIR/timeout.trigger" ]]; then
  sleep 20  # Longer than typical 10s timeout
fi
```

**Simulating Missing Binary:**
```bash
# If not-found.trigger file exists, don't execute
if [[ -f "$FIXTURE_DIR/not-found.trigger" ]]; then
  exit 127  # Command not found
fi
```

**Simulating Errors:**
```bash
# If error.trigger file exists, return error
if [[ -f "$FIXTURE_DIR/error.trigger" ]]; then
  echo "Error: Connection refused" >&2
  exit 1
fi
```

---

## Adding New Scenarios

### Step 1: Create Fixture

```bash
cat > .claude/scripts/test-harness/fixtures/kubectl/get-services.json <<EOF
{
  "items": [
    {
      "metadata": { "name": "api-service", "namespace": "production" },
      "spec": { "type": "LoadBalancer", "clusterIP": "10.0.0.5" }
    }
  ]
}
EOF
```

### Step 2: Update Shim

```bash
# In shims/kubectl, add new case:
case "$CMD" in
  # ... existing cases ...
  get)
    RESOURCE="$1"
    if [[ "$RESOURCE" == "services" ]]; then
      cat "$FIXTURE_DIR/get-services.json"
    fi
    ;;
esac
```

### Step 3: Write Test

```bash
test_kubectl_get_services() {
  # Run with PATH pointing to shims
  export PATH="$HARNESS_DIR/shims:$PATH"

  # Call MCP tool (which will use shimmed kubectl)
  local result=$(node -e "...")

  # Assert on result
  if echo "$result" | grep -q "api-service"; then
    pass "kubectl get services returns fixture data"
  else
    fail "kubectl get services" "Service not found in output"
  fi
}
```

---

## Secret Redaction Testing

### Fixtures with Secrets

Place test secrets in `fixtures/secrets/`:

```bash
# fixtures/secrets/postgres-with-password.txt
postgres://admin:SuperSecret123@db.example.com:5432/production

# fixtures/secrets/aws-credentials.json
{
  "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
  "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}
```

### Redaction Assertions

```bash
test_secret_redaction() {
  export PATH="$HARNESS_DIR/shims:$PATH"

  # Call tool that returns secret-containing output
  local result=$(node -e "...")

  # Assert secrets are redacted
  if echo "$result" | grep -q "SuperSecret123"; then
    fail "Secret redaction" "Raw password found in output!"
  elif echo "$result" | grep -q "***REDACTED***"; then
    pass "Secret redaction works correctly"
  else
    fail "Secret redaction" "Expected redacted marker not found"
  fi
}
```

---

## Environment Variables

Shims respect these environment variables:

- `TEST_HARNESS_FIXTURE_DIR`: Override fixture directory
- `TEST_HARNESS_SIMULATE_TIMEOUT`: Force all shims to timeout
- `TEST_HARNESS_SIMULATE_ERROR`: Force all shims to return errors
- `TEST_HARNESS_LOG_CALLS`: Log all shim invocations to stderr

Example:

```bash
export TEST_HARNESS_LOG_CALLS=1
export PATH="$HARNESS_DIR/shims:$PATH"
node .claude/mcp/server-ops.js  # Logs: "SHIM kubectl version called"
```

---

## Running Tests

### Run All E2E Tests

```bash
bash .claude/scripts/test-ops-stage4.sh
```

### Run with Verbose Output

```bash
DEBUG=1 bash .claude/scripts/test-ops-stage4.sh
```

### Run Single Test Category

```bash
bash .claude/scripts/test-ops-stage4.sh approval_workflow
bash .claude/scripts/test-ops-stage4.sh redaction
bash .claude/scripts/test-ops-stage4.sh cache
```

---

## CI Integration

The harness is designed for CI environments:

```yaml
# .github/workflows/ops-tests.yml
- name: Run E2E Tests
  run: |
    export PATH="${PWD}/.claude/scripts/test-harness/shims:$PATH"
    bash .claude/scripts/test-ops-stage4.sh
```

**CI Benefits:**
- No infrastructure provisioning required
- Fast execution (<60s)
- Deterministic results (no flaky tests)
- Works in any CI provider (GitHub Actions, GitLab CI, CircleCI, etc.)

---

## Troubleshooting

### Shim Not Found

**Problem:** `command not found: kubectl`

**Solution:**
```bash
# Verify PATH injection
echo $PATH  # Should start with /path/to/shims

# Verify shim is executable
chmod +x .claude/scripts/test-harness/shims/*
```

### Fixture Not Found

**Problem:** `cat: fixtures/kubectl/get-pods.json: No such file or directory`

**Solution:**
```bash
# Verify fixture exists
ls -la .claude/scripts/test-harness/fixtures/kubectl/

# Check shim is looking in correct directory
cat .claude/scripts/test-harness/shims/kubectl | grep FIXTURE_DIR
```

### Secrets Not Redacted

**Problem:** Raw secrets appearing in test output

**Solution:**
```bash
# Verify redactOutput is called
grep -n "redactOutput" .claude/mcp/server-ops.js

# Test redaction function directly
node -e "const text = 'password: SuperSecret123'; console.log(require('./redact.js').redactOutput(text));"
```

### Test Timeout

**Problem:** Test hangs indefinitely

**Solution:**
```bash
# Remove timeout trigger files
rm .claude/scripts/test-harness/fixtures/*/timeout.trigger

# Add timeout to test script
timeout 60s bash .claude/scripts/test-ops-stage4.sh
```

---

## Best Practices

### 1. Keep Fixtures Small

❌ Bad: 10MB JSON file with 10,000 items
✅ Good: 1KB JSON file with 5 representative items

### 2. Use Realistic Data

❌ Bad: `{ "name": "foo" }`
✅ Good: `{ "name": "api-service", "namespace": "production", "status": "Running" }`

### 3. Test Edge Cases

- Empty results (`{ "items": [] }`)
- Partial failures (some tools succeed, some fail)
- Malformed JSON
- Very long strings
- Special characters in names

### 4. Don't Mock Everything

✅ Mock: External CLIs (kubectl, gh, aws)
❌ Don't Mock: Internal functions (redactOutput, validateConfig)

### 5. Verify Redaction

Always assert secrets are redacted in:
- Tool output (JSON)
- Log files (.claude/logs/ops-mcp.log)
- Audit logs (approvals database)
- Error messages

---

## Maintenance

### Adding a New CLI Tool

1. Create shim: `.claude/scripts/test-harness/shims/newtool`
2. Create fixtures: `.claude/scripts/test-harness/fixtures/newtool/`
3. Add test cases in `test-ops-stage4.sh`
4. Update this README with new tool

### Updating Fixtures

When ops tool behavior changes:

1. Identify affected fixtures
2. Update fixture JSON to match new schema
3. Run tests to verify
4. Commit fixture changes with code changes

---

## Security Notes

⚠️ **Never commit real secrets to fixtures!**

All secrets in `fixtures/secrets/` must be:
- Clearly fake/example values
- Marked with comments: `# FAKE SECRET FOR TESTING`
- Different from any real credentials

---

## Performance

Typical execution times:

| Test Suite | Duration | Tests |
|------------|----------|-------|
| Structural (Stage 3) | 2-5s | 29 |
| E2E Approval Workflow | 5-10s | 8 |
| E2E Redaction | 3-5s | 6 |
| E2E Cache | 3-5s | 4 |
| **Total** | **15-30s** | **47** |

Target: All tests complete in <60s

---

## Future Enhancements

- **Stateful Shims:** Track call history for assertion
- **Network Simulation:** Simulate latency, packet loss
- **Chaos Testing:** Random failures, timeouts
- **Coverage Reports:** Track which shims/fixtures are used
- **Parallel Execution:** Run test categories in parallel

---

**Last Updated:** 2026-02-10
**Maintainer:** Factory Team
