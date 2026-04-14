# Release Checklist

This checklist ensures the Claude Factory pipeline is production-ready before any release. All commands are designed to run without network dependencies and use local validation only.

## 1. Environment Verification

Verify the development environment meets all requirements.

- [ ] **Check installed tools**
  ```bash
  bash .claude/scripts/health-check.sh
  ```
  Expected: All checks pass (optional tools may show warnings)

- [ ] **Verify MCP server availability**
  ```bash
  bash .claude/scripts/verify.sh smoke
  ```
  Expected: All 6 MCP servers available and responding

- [ ] **Check ctags indexing**
  ```bash
  test -f tags && echo "✓ Tags file exists" || echo "✗ Tags missing"
  ```
  Expected: Tags file exists at repository root

- [ ] **Validate database**
  ```bash
  sqlite3 .claude/cache/cache.db '.tables'
  ```
  Expected: Output includes `cache_entries` and `decision_memory`

## 2. Test Suite Execution

Run all automated tests to ensure code quality.

- [ ] **Core verification tests**
  ```bash
  bash test/verify.sh
  ```
  Expected: 28/28 tests passing (100% success rate)

- [ ] **Log observability tests**
  ```bash
  bash .claude/scripts/test-log-observability.sh
  ```
  Expected: 40/40 tests passing

- [ ] **Ops tool dry-run tests**
  ```bash
  bash .claude/scripts/test-ops-dryrun.sh
  ```
  Expected: 13/13 tests passing

- [ ] **Installation tests**
  ```bash
  bash .claude/scripts/test-install.sh
  ```
  Expected: All test suites pass (~20 tests)

- [ ] **Phase 4 integration tests**
  ```bash
  bash .claude/scripts/test-phase4-integration.sh
  ```
  Expected: All 7 test suites pass (~50 tests)

## 3. Documentation Review

Ensure all documentation is complete and accurate.

- [ ] **Verify CHANGELOG.md is up to date**
  ```bash
  test -f CHANGELOG.md && grep -q "## \[Unreleased\]" CHANGELOG.md && echo "✓ CHANGELOG.md exists and has Unreleased section" || echo "✗ CHANGELOG.md issue"
  ```
  Expected: CHANGELOG.md exists with Unreleased section

- [ ] **Verify TROUBLESHOOTING.md exists**
  ```bash
  test -f TROUBLESHOOTING.md && echo "✓ TROUBLESHOOTING.md exists" || echo "✗ TROUBLESHOOTING.md missing"
  ```
  Expected: TROUBLESHOOTING.md exists

- [ ] **Check README completeness**
  ```bash
  grep -q "Installation" README.md && grep -q "Usage" README.md && echo "✓ README has Installation and Usage sections" || echo "✗ README incomplete"
  ```
  Expected: README has Installation and Usage sections

- [ ] **Verify all runbooks exist**
  ```bash
  ls .claude/runbooks/*.md | wc -l
  ```
  Expected: 4 or more runbook files

## 4. Code Quality

Validate policy compliance and code standards.

- [ ] **Policy validation**
  ```bash
  bash .claude/scripts/validate-policies.sh
  ```
  Expected: All 58 policy checks passing

- [ ] **Check for secrets in code**
  ```bash
  bash .claude/scripts/test-secrets-redaction.sh
  ```
  Expected: All redaction tests pass (no secrets leaked)

- [ ] **Verify script permissions**
  ```bash
  find .claude/scripts -name "*.sh" ! -perm -u+x -print | wc -l
  ```
  Expected: 0 (all scripts are executable)

- [ ] **Check .gitignore coverage**
  ```bash
  grep -q ".claude/cache/" .gitignore && grep -q ".claude/logs/" .gitignore && grep -q ".claude/memory/" .gitignore && echo "✓ .gitignore complete" || echo "✗ .gitignore missing entries"
  ```
  Expected: All cache/log/memory directories ignored

## 5. Fresh Repository Test

Validate installation from a clean state.

- [ ] **Clone repository to temp location**
  ```bash
  git clone . /tmp/claude-factory-test-$(date +%s)
  ```
  Expected: Clean clone succeeds

- [ ] **Run install.sh in fresh clone**
  ```bash
  cd /tmp/claude-factory-test-* && bash install.sh
  ```
  Expected: Installation completes with smoke test passing

- [ ] **Verify quick check in fresh clone**
  ```bash
  cd /tmp/claude-factory-test-* && bash .claude/scripts/verify.sh quick
  ```
  Expected: Quick verification passes in <100ms

- [ ] **Clean up test clone**
  ```bash
  rm -rf /tmp/claude-factory-test-*
  ```
  Expected: Temp directory removed

## 6. Upgrade Path Test

Ensure existing installations can upgrade smoothly.

- [ ] **Backup existing cache (if present)**
  ```bash
  test -f .claude/cache/cache.db && cp .claude/cache/cache.db .claude/cache/cache.db.backup || echo "No cache to backup"
  ```
  Expected: Cache backed up or no cache exists

- [ ] **Run install.sh idempotence check**
  ```bash
  bash install.sh && bash install.sh
  ```
  Expected: Second run succeeds with no errors, no duplicate migrations

- [ ] **Verify cache migration (if applicable)**
  ```bash
  test -f .claude/cache/cache.db && sqlite3 .claude/cache/cache.db 'SELECT COUNT(*) FROM cache_entries;' && echo "✓ Cache migration successful" || echo "✗ Cache issue"
  ```
  Expected: Cache accessible with valid schema

- [ ] **Restore cache backup**
  ```bash
  test -f .claude/cache/cache.db.backup && rm .claude/cache/cache.db.backup || echo "No backup to remove"
  ```
  Expected: Backup removed if present

## 7. Final Sign-Off

Review and approve for release.

- [ ] **Review git status**
  ```bash
  git status
  ```
  Expected: Working directory clean (or only expected uncommitted changes)

- [ ] **Verify CI check script**
  ```bash
  bash .claude/scripts/ci-check.sh
  ```
  Expected: All 3 CI checks pass (verify.sh quick + health-check.sh + validate-policies.sh)

- [ ] **Check git log for release commits**
  ```bash
  git log --oneline -10
  ```
  Expected: Recent commits reflect expected changes for this release

- [ ] **Tag release version**
  ```bash
  # After all checks pass:
  # git tag -a v0.5.0 -m "Release version 0.5.0"
  # git push origin v0.5.0
  ```
  Expected: Tag created and pushed (manual step)

---

## Notes

- **No Network Dependencies**: All checks run locally without external API calls
- **Expected Runtime**: Full checklist completion takes ~3-5 minutes
- **Failure Handling**: If any check fails, consult TROUBLESHOOTING.md
- **Automation**: This checklist can be automated via ci-check.sh for CI/CD pipelines

## Troubleshooting

If any checks fail, refer to:
- `TROUBLESHOOTING.md` for common issues
- `.claude/runbooks/bootstrap-new-repo.md` for setup problems
- `docs/policy/failure-recovery.md` for recovery strategies
