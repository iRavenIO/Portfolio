# OpenCode Compatibility Design

## Goal

Make this Claude-first setup installable and usable with OpenCode too, with specific focus on the two user-facing commands `cfactory .` and `cfmode full .`.

## Scope

- Preserve the existing Claude workflow and profile files.
- Add native OpenCode project files instead of relying only on OpenCode's `CLAUDE.md` fallback behavior.
- Ensure install helpers copy OpenCode assets into target projects.
- Ensure profile switching updates both Claude and OpenCode active instruction files.
- Update tests and docs for the new dual-tool behavior.

## Design

### File Model

Keep the current Claude profile system:

- `CLAUDE.light.md`
- `CLAUDE.full.md`
- `CLAUDE.md` as the active Claude profile

Add an equivalent OpenCode profile system:

- `AGENTS.light.md`
- `AGENTS.full.md`
- `AGENTS.md` as the active OpenCode profile

Add install-mode-specific OpenCode config templates at repo root:

- `opencode.full.json`
- `opencode.lite.json`
- `opencode.json` as the active OpenCode config for the installed mode

The active OpenCode config:

- is copied from `opencode.full.json` during `cfactory`
- is copied from `opencode.lite.json` during `cfactorylite`
- mirrors the MCP surface of the corresponding Claude install mode
- provides shared instruction references for OpenCode
- avoids introducing a large `.opencode/` tree unless a concrete gap requires it

The OpenCode profile files must use deterministic first-line markers so status checks can identify the active behavior mode reliably:

- `AGENTS.light.md` starts with `# Claude Factory for OpenCode — LIGHT MODE`
- `AGENTS.full.md` starts with `# Claude Factory for OpenCode — FULL MODE`

### Command Behavior

#### `cfactory`

- Continue installing the current Claude factory files.
- Also install the OpenCode-native files: `AGENTS.md`, `AGENTS.light.md`, `AGENTS.full.md`, `opencode.full.json`, `opencode.lite.json`, and active `opencode.json`.
- Normalize active files after copy so installs are deterministic regardless of the source repo's current state:
  - `CLAUDE.light.md` to `CLAUDE.md`
  - `AGENTS.light.md` to `AGENTS.md`
  - `opencode.full.json` to `opencode.json`
- Update success output so it advertises both `claude` and `opencode` as valid entrypoints.

#### `cfactorylite`

- Include the OpenCode files in lite installs as well.
- Normalize active files after copy so installs are deterministic:
  - `CLAUDE.light.md` to `CLAUDE.md`
  - `AGENTS.light.md` to `AGENTS.md`
  - `opencode.lite.json` to `opencode.json`
- Keep LIGHT as the only supported behavior profile in lite installs.

#### `cfmode`

- `cfmode light` copies:
  - `CLAUDE.light.md` to `CLAUDE.md`
  - `AGENTS.light.md` to `AGENTS.md`
- `cfmode full` copies:
  - `CLAUDE.full.md` to `CLAUDE.md`
  - `AGENTS.full.md` to `AGENTS.md`
- On lite installs, `cfmode full` exits with a clear error explaining that FULL behavior requires a full install.
- `cfmode status` reports both current modes and warns if Claude and OpenCode are out of sync.
- `cfmode` does not change install-mode assets or the active OpenCode MCP config; it switches behavior profiles only.

#### `cunfactory`

- Remove the OpenCode files added by installation in the corresponding install mode.
- Full uninstall removes:
  - `AGENTS.md`
  - `AGENTS.light.md`
  - `AGENTS.full.md`
  - `opencode.json`
  - `opencode.full.json`
  - `opencode.lite.json`
- Lite uninstall removes the same OpenCode files if present.

### Testing

Extend the existing profile test coverage to validate:

- OpenCode profile files exist
- `AGENTS.md` defaults to LIGHT mode
- simulated switching works for both Claude and OpenCode profiles
- active `opencode.json` matches the correct install mode template
- full and lite installs normalize active files after copy
- lite installs reject `cfmode full` with a clear message
- uninstall removes the new OpenCode files in both install modes
- zsh helpers still advertise `cfmode`

### Documentation

Update user-facing docs so they explain that:

- this repository supports both Claude and OpenCode
- `cfactory .` installs both instruction systems
- `cfmode` switches both active profiles together

## Out of Scope

- Building a full custom `.opencode/agents` ecosystem
- Reproducing Claude's complete orchestration model inside OpenCode
- Adding a dedicated OpenCode launcher script unless later proven necessary

## Rationale

This approach keeps one installation path and one profile switch command while making OpenCode a first-class citizen. It avoids a heavy second configuration tree and limits maintenance to a few clear root-level files and helper updates.
