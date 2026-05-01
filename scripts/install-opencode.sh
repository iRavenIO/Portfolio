#!/usr/bin/env bash
set -euo pipefail

SOURCE="${CLAUDE_FACTORY_SOURCE:-$HOME/Sites/Local/Applications/Network/Claude}"
TARGET="${1:-.}"

if [[ ! -d "$SOURCE" ]]; then
  echo "Source not found: $SOURCE" >&2
  exit 1
fi

mkdir -p "$TARGET"
cd "$TARGET"

rsync -av --exclude='.git' --exclude='node_modules' "$SOURCE/" ./

[[ -f "CLAUDE.light.md" ]] && cp CLAUDE.light.md CLAUDE.md
[[ -f "AGENTS.light.md" ]] && cp AGENTS.light.md AGENTS.md
[[ -f "opencode.full.json" ]] && cp opencode.full.json opencode.json

if [[ -f ".opencode/project.template.yml" ]] && [[ ! -f ".opencode/project.yml" ]]; then
  cp .opencode/project.template.yml .opencode/project.yml
fi
if [[ -f ".opencode/overrides.template.md" ]] && [[ ! -f ".opencode/overrides.md" ]]; then
  cp .opencode/overrides.template.md .opencode/overrides.md
fi
if [[ -f ".claude/project-context.md.sample" ]] && [[ ! -f ".claude/project-context.md" ]]; then
  cp .claude/project-context.md.sample .claude/project-context.md
fi
