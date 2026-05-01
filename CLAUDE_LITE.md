# CLAUDE FACTORY — LITE MODE

## What is Lite Mode?

Lite mode is a **minimal, MCP-only runtime** for Claude Factory. It strips away the full multi-agent workflow pipeline and heavy scripting infrastructure, leaving only:

- **MCP servers** (factory-ops, factory-git, factory-fs)
- **Essential configuration** (.mcp.lite.json, env.claude.sample)
- **Minimal policies** (only what's required for MCP tool usage)

Lite mode is ideal for:
- Projects that only need infrastructure discovery/operations tools
- Environments where you want Claude with strict MCP config but no workflow automation
- Quick prototyping without full factory overhead
- CI/CD scenarios where only specific MCP tools are needed

## What's Included in Lite?

### Files
- `.mcp.lite.json` — MCP configuration (3 servers: ops, git, fs)
- `.claude/mcp/` — MCP server implementations
- `.claude/env.claude.sample` — Environment template
- `CLAUDE_LITE.md` — This file
- `cf-lite` — Runner script
- `install.sh` — Installation script (supports `--mode lite`)

### MCP Servers (3 total)
| Server | Tools | Purpose |
|--------|-------|---------|
| `factory-ops` | 19 ops tools | Infrastructure discovery & operations |
| `factory-git` | 4 git tools | Git status, diff, log, blame |
| `factory-fs` | 3 fs tools | File tree, read ranges, list files |

### What's NOT Included
- Multi-agent workflow pipeline (analyst, researcher, architect, etc.)
- Heavy scripting infrastructure (health-check, validate-policies, etc.)
- Automatic git commits and workflow automation
- Full policy documentation (only essential MCP security policies)
- Task reports and batch processing
- Ctags indexing and cache subsystem
- Voice notifications (notify_say)
- Web research (research_search_web)

## Installation

### From Factory Repository
```bash
# Clone or navigate to factory repo
cd /path/to/claude-factory

# Install lite mode
./install.sh --mode lite

# Or use Zsh helper (if configured)
cfactorylite /path/to/target-project
```

### Manual Installation
```bash
# In your target project
mkdir -p .claude/mcp
cp -r /path/to/claude-factory/.claude/mcp/* .claude/mcp/
cp /path/to/claude-factory/.mcp.lite.json .mcp.lite.json
cp /path/to/claude-factory/.claude/env.claude.sample .claude/env.claude.sample
cp /path/to/claude-factory/cf-lite ./cf-lite
chmod +x ./cf-lite

# Install MCP dependencies
cd .claude/mcp && npm install
```

## Usage

### Running Claude in Lite Mode
```bash
# Using the cf-lite runner
./cf-lite

# Or manually
claude --strict-mcp-config --mcp-config .mcp.lite.json --tools "" --model sonnet
```

### Configuration
```bash
# Copy environment template
cp .claude/env.claude.sample .claude/env.claude

# Edit configuration (optional)
vim .claude/env.claude
```

Configuration in `.claude/env.claude` controls:
- MCP server behavior (timeouts, concurrency)
- Infrastructure connections (Kubernetes, AWS, GitHub, etc.)
- Log levels and observability settings

**IMPORTANT:** Never commit `.claude/env.claude` — it's gitignored by default.

## MCP Tool Reference

### Ops Tools (factory-ops)
See [docs/MVP_OPERATIONS_REFERENCE.md](docs/MVP_OPERATIONS_REFERENCE.md) for complete operations catalog.

Quick reference:
- `ops_discover_k8s` — Kubernetes resources
- `ops_discover_docker` — Docker containers
- `ops_discover_github` — GitHub workflows
- `ops_discover_postgres` — PostgreSQL databases
- `ops_discover` — Unified discovery (all services)
- `ops_plan_mutation` — Plan infrastructure changes
- `ops_approve` / `ops_execute` — Approval workflow
- `ops_health` / `ops_metrics` — Observability

### Git Tools (factory-git)
- `git_status` — Working tree status
- `git_diff_stat` — Diff statistics
- `git_log_oneline` — Commit history
- `git_blame_range` — Line-by-line authorship

### FS Tools (factory-fs)
- `fs_tree` — Directory tree visualization
- `fs_read_range` — Read specific line ranges
- `fs_list_files` — List files with glob patterns

## Security

Lite mode inherits the factory's MCP security model:
- **Input sanitization** — All MCP tool inputs are validated
- **Secret redaction** — Automatic redaction of credentials in logs
- **Permission tiers** — READ/WRITE/INFRASTRUCTURE separation
- **Approval workflow** — Mutating operations require explicit approval

See [docs/policy/mcp-security.md](docs/policy/mcp-security.md) for details.

## Upgrading to Full Mode

To upgrade from lite to full mode:
```bash
# From factory repo
./install.sh --mode full /path/to/target-project

# Or use Zsh helper
cfactory /path/to/target-project
```

This will add:
- Full agent workflow pipeline
- All MCP servers (7 total)
- Complete policy documentation
- Health checks and validation scripts
- Workflow automation and task reports

## Uninstalling

```bash
# Dry-run (preview what will be removed)
cunfactory /path/to/target-project

# Apply removal
cunfactory --apply /path/to/target-project

# Force removal (skip confirmations)
cunfactory --apply --force /path/to/target-project
```

## Troubleshooting

### MCP servers not connecting
```bash
# Check MCP config
cat .mcp.lite.json

# Verify node modules
cd .claude/mcp && npm install

# Check server logs
claude --mcp-debug
```

### Missing dependencies
```bash
# Lite mode requires: node, npm, git
# Optional: kubectl, docker, gh, psql (for ops tools)

# macOS
brew install node git

# Verify
node --version
npm --version
```

### Permission errors
```bash
# Fix MCP directory permissions
chmod -R 755 .claude/mcp
chmod +x cf-lite
```

## Support

- Full documentation: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- Report issues: https://github.com/anthropics/claude-code/issues
- Factory source: /path/to/claude-factory
