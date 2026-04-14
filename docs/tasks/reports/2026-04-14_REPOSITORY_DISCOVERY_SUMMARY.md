# Repository Discovery Summary (2026-04-14)

## Purpose

Document the current architecture and operational structure of this project before migrating/publishing it to a new repository.

## High-level finding

This repository combines:

1. **A production portfolio web app** (Next.js static export)
2. **A Claude Factory/OpenCode automation platform** (policies, scripts, MCP servers, infra/ops utilities)

It is not just a website repository; it is also a tooling and operations framework.

---

## Application architecture (portfolio site)

- **Framework:** Next.js 14 + React 18
- **Build mode:** static export (`output: "export"`, `trailingSlash: true`)
- **Routing:** catch-all page route (`pages/[[...slug]].js`)
- **Content model:** YAML-driven (`content/site.yaml`)
- **Server content builder:** `lib/siteContent.server.js`
  - validates and normalizes content
  - generates page markup by content type
  - assembles SEO/head/script metadata
- **Document shell:** `pages/_document.js`
- **Containerization:** multi-stage Docker build; static output served by Nginx

## Factory/OpenCode architecture

- Active OpenCode profile is governed by `AGENTS.md`
- Mode/routing policies are defined in `.opencode/router.md`
- MCP server manifests:
  - `.mcp.json` (full tool set)
  - `.mcp.lite.json` (reduced/lite tool set)
- OpenCode config variants:
  - `opencode.json`, `opencode.full.json`, `opencode.lite.json`

### MCP servers identified

Under `.claude/mcp/`:

- `server.js` (factory tools: web research, notification/say, git repo diff)
- `server-ctags.js` (code index generation + incremental strategy)
- `server-rg.js` (ripgrep search service)
- `server-fs.js` (tracked file tree/list/range read)
- `server-git.js` (status, diffstat, log, blame range)
- `server-query.js` (jq/yq structured query wrappers)
- `server-ops.js` (infrastructure discovery + mutation planning/approval/execution workflow)

Shared helpers are in `.claude/mcp/lib/` (config/env loading, validation, error handling, bootstrap).

## Scripts and policy ecosystem

- Installer/bootstrap entrypoints: `install.sh`, `cf`, `cf-lite`
- Validation and health scripts under `.claude/scripts/`:
  - `verify.sh`
  - `health-check.sh`
  - `validate-policies.sh`
  - env/bootstrap/cache/ops wrappers
- Policy framework under `docs/policy/` controls workflow, security, tool usage, caching, orchestration, and ops behavior.

## Deployment/infra artifacts

- `.deployment/home` for app deployment chart/manifests
- `.deployment/events` for event hooks/sensors
- `.deployment/workflows` for workflow templates and RBAC/service accounts
- CI workflow present in `.github/workflows/ops-tests.yml`

## Operational notes and caveats

- Working tree contained substantial modified/untracked files at time of discovery.
- Some context/config files appear template-oriented and may require project-specific finalization.
- This migration should preserve both app runtime files and factory automation files unless intentionally splitting repositories.

## Suggested follow-up

1. Keep this report as baseline architecture context.
2. Decide whether long-term target is:
   - single combined repo (app + factory), or
   - split repos (app runtime vs automation framework).
3. Add repository-level onboarding guidance for contributors around profiles, scripts, and verification flow.
