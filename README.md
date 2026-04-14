# Autonomous Multi-Agent Software Factory

An autonomous development pipeline powered by [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code). Send any prompt — the factory analyzes, researches, designs, implements, reviews, tests, and reports automatically.

## Requirements

- macOS (for `say` command and Homebrew)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) with access to Claude Opus and Claude Sonnet
- Node.js >= 18
- `gemini` CLI in PATH (for web research): `npm install -g @google/genai-for-devs`

## Setup

### Full Mode (Default)

```bash
chmod +x install.sh && ./install.sh
# or: ./install.sh --mode full
```

This installs ripgrep, Universal Ctags, MCP server dependencies, and generates an initial ctags index. Includes the complete multi-agent workflow pipeline.

### Lite Mode

For MCP-only runtime without workflow automation:

```bash
./install.sh --mode lite
./cf-lite  # Run Claude with lite config
```

**Lite mode includes:**
- 3 MCP servers (factory-ops, factory-git, factory-fs)
- Infrastructure discovery and operations tools
- Minimal overhead, no workflow automation

**Lite mode excludes:**
- Multi-agent workflow pipeline
- Ctags indexing and cache subsystem
- Validation scripts and health checks
- Voice notifications and web research

See [CLAUDE_LITE.md](CLAUDE_LITE.md) for full documentation.

## Usage

Open this repository in Claude Code and send any prompt:

```
> Build a REST API for user authentication with JWT tokens
> Refactor the payment module to use the Strategy pattern
> Fix the race condition in the WebSocket handler
```

Multi-task prompts work too — just describe multiple tasks in one message.

## Configuration

The factory's behavior can be customized via environment variables in `install.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_FACTORY_SKIP_DEPS` | `0` | Set to `1` to skip dependency installation (verify only) |
| `CLAUDE_FACTORY_NOTIFY` | `1` | Set to `0` to disable voice notifications |
| `CLAUDE_FACTORY_TAGS_MODE` | `auto` | Ctags mode: `auto`, `git` (tracked files), or `full` (filesystem scan) |
| `CLAUDE_FACTORY_TAGS_OUT` | `tags` | Output path for the ctags file |
| `CLAUDE_FACTORY_MAX_TAG_FILES` | `200000` | Safety limit for ctags file count |

Example:
```bash
CLAUDE_FACTORY_TAGS_MODE=full ./install.sh
```

### Verification Scripts

Run health checks and policy validation manually:

```bash
.claude/scripts/health-check.sh        # Validate environment and dependencies
.claude/scripts/validate-policies.sh   # Check policy file integrity
```

Both scripts are automatically executed at the end of `install.sh`.

## What Happens

1. The **Manager** (CLAUDE.md) detects single vs. multi-task prompts
2. A "Manager started" audible notification plays via `notify_say`
3. Specialized agents run in sequence: Analyst → Researcher → Architect → Developer ↔ Reviewer ↔ Tester → Reporter
4. The ctags index is automatically refreshed before implementation and after each code change
5. A final report is written to `docs/tasks/reports/` and a voice summary is spoken aloud

## Outputs

| File | Description |
|------|-------------|
| `docs/tasks/reports/TASK_REPORT.md` | Single-task final report |
| `docs/tasks/reports/TASK_REPORT_<i>.md` | Per-task report (multi-task) |
| `docs/tasks/reports/BATCH_REPORT.md` | Batch summary (multi-task) |

## Full Technical Reference

See [README_CLAUDE.md](README_CLAUDE.md) for architecture, agent pipeline, MCP server details, model assignments, and troubleshooting.
