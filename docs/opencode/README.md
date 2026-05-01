# OpenCode Usage

- Start with AGENTS.md (active profile).
- Read .opencode/project.yml and .opencode/overrides.md when present.
- Read .claude/project-context.md when topology or secrets matter.
- Prefer MCP tools; fallback to Bash when MCP is unavailable.

## Routing

Mode selection and tie-breakers live in .opencode/router.md. Follow the mode
contracts in .opencode/modes/*.md.

## Reporting Format

Pre: plan + assumptions
During: stage update(s)
Post: changes + verification + next steps
