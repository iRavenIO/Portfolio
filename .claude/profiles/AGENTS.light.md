# Claude Factory for OpenCode - LIGHT MODE

This repository supports both Claude Code and OpenCode.

`AGENTS.md` is the active OpenCode profile. In full installs, `cfmode light` and `cfmode full` keep `AGENTS.md` aligned with the matching `CLAUDE.md` profile.

## Working Style

- Handle most tasks in one pass: inspect, make a brief plan, implement, verify, summarize.
- Prefer the smallest correct change.
- Use OpenCode plan mode when the user explicitly wants design-first work or the task is ambiguous, architectural, or risky.
- For routine tasks, work directly after reading the relevant files.
- Use subagents sparingly; prefer direct work unless focused exploration clearly helps.

## OpenCode Routing

- Read .opencode/router.md for mode and agent selection.
- Load .opencode/project.yml and .opencode/overrides.md when present.
- Load .claude/project-context.md when topology or secrets matter.

## Repo Conventions

- Prefer existing scripts and policies over adding helper files.
- Keep changes local and avoid broad refactors unless they are required by the task.
- Use the repo's focused verification scripts when relevant, especially under `.claude/scripts/`.
- `CLAUDE.md` is the Claude-native profile; `AGENTS.md` is the OpenCode-native profile.

## Environment And Secrets

- Factory and MCP configuration lives in `.claude/env.claude` with local overrides in `.claude/env.claude.local`.
- Before assuming where a project connects, read `.claude/project-context.md` if it exists.
- Treat locator vars in `.claude/env.claude` such as `PROJECT_CONTEXT_FILE`, `PROJECT_DATABASE_KIND`, `VAULT_DOC_PATH`, and `VAULT_SHARED_*` as the first place to discover database, Vault, and service topology.
- Application and per-project secrets live in `.env.local` files inside the relevant project directories.
- Do not introduce a second env model for OpenCode.
- Before any bash or MCP command that depends on factory env, run `. .claude/scripts/load-env-safe.sh`.
- For per-project env scaffolding, use `bash .claude/scripts/bootstrap-env.sh --project <path>`.
- Never print secret values or commit `.claude/env.claude`, `.claude/env.claude.local`, or `.env.local`.

## Safety

- Avoid destructive git commands unless the user explicitly asks for them.
- Prefer non-interactive git commands.
- Do not commit secrets or generated local env files.

## On-Demand References

- Read `.claude/project-context.md` when the task touches database hosts, service discovery, Vault paths, MySQL/Postgres/Supabase, or app connection topology.
- Read `docs/INSTALL.md` when the task touches installation, profile modes, or environment bootstrap.
- Read `docs/policy/secrets-and-env.md` when secret handling or env safety matters.
- Read `docs/policy/git-automation.md` when commit behavior matters.
