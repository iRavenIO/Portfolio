# OpenCode Router

Goal: choose mode, agent pattern, and tool set with minimum risk while keeping
staged reporting consistent.

Read context in this order:
1) .opencode/project.yml
2) .opencode/overrides.md
3) .claude/project-context.md

Mode selection (first match wins):
1) Plan: "design", "architecture", "research", "migration", "risk", "spec"
2) Debug: "error", "failure", "bug", "regression", "stacktrace"
3) Refactor: "refactor", "cleanup", "restructure", "rename"
4) Review: "review", "audit", "check", "assess"
5) Report: "status", "summary", "progress", "post-mortem"
6) Build: default for implementation

Tie-breakers:
- If the request includes both design and implementation, start in Plan and
  confirm before edits.
- If the request is review-only (no change verbs like "fix", "add"), prefer
  Review.
- If the request is status-only, prefer Report.

Agent selection:
- Researcher when external sources are needed
- Reviewer for any non-trivial code change
- Tester when tests exist or code paths change
- Infra agent for ops keywords (k8s, argocd, postgres, supabase)

Tool priority:
- MCP tools first, Bash fallback when MCP is unavailable
- Ops mutations require approval workflow (see docs/policy/mcp-security.md)

Staged reporting (required):
- Pre: mode + plan/assumptions
- During: checkpoints for multi-step work
- Post: changes + verification + next steps

Mode contracts: see .opencode/modes/*.md
