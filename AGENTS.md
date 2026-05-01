# Claude Factory for OpenCode - FULL MODE

This repository supports both Claude Code and OpenCode.

`AGENTS.md` is the active OpenCode profile. In full installs, `cfmode light` and `cfmode full` keep `AGENTS.md` aligned with the matching `CLAUDE.md` profile.

## Working Style

- Use a design-first workflow for non-trivial work: inspect, plan, implement, review, verify, summarize.
- Start in OpenCode plan mode when the task is large, architectural, research-heavy, or asks for a comprehensive solution.
- For complex work, use subagents when they materially improve exploration or focused review.
- Provide more thorough verification and change summaries than LIGHT mode.

## OpenCode Routing

- Read .opencode/router.md for mode and agent selection.
- Load .opencode/project.yml and .opencode/overrides.md when present.
- Load .claude/project-context.md when topology or secrets matter.

## Repo Conventions

- Preserve the existing factory structure and reuse current scripts, policies, and runbooks.
- Keep changes deliberate and well-scoped; avoid unrelated refactors.
- Use the repo's verification scripts under `.claude/scripts/` instead of inventing new helpers.
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
- Read `docs/policy/workflow.md` and `docs/policy/orchestration.md` when a task needs the heavier factory workflow model.
