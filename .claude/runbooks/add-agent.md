# Runbook: Add a New Agent

## When to Use

Use this runbook when adding a new specialized agent to the factory pipeline. This covers creating the agent definition, assigning a model tier, integrating it into the workflow, and updating all documentation.

## Prerequisites

- You have identified a clear, single-purpose role for the new agent
- You know which phase of the workflow the agent belongs to
- You know which model tier is appropriate (Tier 1: Opus, Tier 2: Sonnet, Tier 3: Haiku)
- You have defined which MCP tools the agent should be allowed to use

## Steps

### 1. Create the Agent Definition File

**File:** `.claude/agents/<agent-name>.md`

Structure the agent definition with these sections:

```markdown
# <AGENT NAME> AGENT

## ROLE

<Single-sentence description of the agent's purpose>

## INPUT

<What the agent receives from the Manager>

## OUTPUT

<What the agent must produce — include format specification>

## INSTRUCTIONS

<Detailed step-by-step instructions for the agent>

## MCP TOOL USAGE

<List the tools the agent is allowed to use and their purpose>

## CONSTRAINTS

<Budget limits, scope boundaries, and behavioral rules>

## OUTPUT FORMAT

<Template or structure the agent must follow in its report>
```

Key conventions:
- Use ALL CAPS for section headers
- Be specific about input/output formats
- Include exact report structures (with markdown headers/sections)
- Define tool usage patterns clearly
- Specify when the agent should escalate to NEEDS_MANAGER_ACTION

### 2. Assign Model Tier

**File:** `docs/policy/agents.md` (MULTI-MODEL ROUTING section)

Add the agent to the appropriate tier table:

- **Tier 1 (Opus):** Planning, design, complex review
- **Tier 2 (Sonnet):** Implementation, analysis, standard testing
- **Tier 3 (Haiku):** File reading, data extraction, simple utilities

### 3. Define MCP Tool Permissions

**File:** `docs/policy/agents.md` (MCP TOOLING POLICY section)

Add a new agent section with tool permissions:

```markdown
#### <Agent Name>

| Tool | Status | Usage |
|------|--------|-------|
| `tool_name` | ✅ / ⚠️ / ❌ | <when and how to use> |
| ... | ... | ... |
```

Legend:
- ✅ Allowed — primary tool for this agent
- ⚠️ Conditional — requires Manager approval or specific context
- ❌ Forbidden — never use

### 4. Update CLAUDE.md — SYSTEM ARCHITECTURE Diagram

**File:** `CLAUDE.md`

Add the new agent file to the `.claude/agents/` tree:

```
├── agents/
│   ├── manager.md
│   ├── analyst.md
│   ├── <new-agent>.md   ← ADD THIS
│   └── ...
```

### 5. Integrate into Workflow

**File:** `CLAUDE.md` (MANDATORY WORKFLOW section)

Determine where the agent fits in the pipeline:
- Is it a new phase (rare)?
- Does it replace or augment an existing phase?
- Is it conditional like Researcher?
- Is it a utility agent spawned on-demand like Reader?

Add spawn instructions to the appropriate phase. Follow this template:

```markdown
### PHASE X: <AGENT NAME>

Spawn the **<Agent Name>** agent to <purpose>.

Task tool call:
  description: "<short description>"
  subagent_type: "general-purpose"
  model: "<opus|sonnet|haiku>"
  prompt: |
    <Read .claude/agents/<agent-name>.md for your full instructions>

    <CONTEXT FROM PREVIOUS AGENTS>

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `tool_name` — <purpose>
    Forbidden:
      ❌ `tool_name` — <reason>
    Before using any tool, state: "Tools I plan to use: ..."
    If you need something outside your scope, output:
      NEEDS_MANAGER_ACTION: <what is needed and why>
    and stop. If MCP is unavailable, fall back to Bash equivalents.

    BUDGET BLOCK:
      Complexity: <LOW|MEDIUM|HIGH>
      Tools: <tiny|small|medium|large>
      File Reads: <tiny|small|medium|large>
      Output Detail: <short|medium|detailed>
    You MUST stay within these budget limits. If you need to exceed them,
    output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

    FILES_ALREADY_READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths>

    <Agent-specific instructions>

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
    See the TOOL-FIRST POLICY section in CLAUDE.md for full rules.
```

### 6. Update QUICK REFERENCE — SPAWN SEQUENCE

**File:** `CLAUDE.md` (QUICK REFERENCE section)

Add the agent to the spawn sequence diagram at the appropriate position.

### 7. Update health-check.sh

**File:** `.claude/scripts/health-check.sh`

Add the new agent file to the `AGENT_FILES` array:

```bash
AGENT_FILES=(
  ".claude/agents/analyst.md"
  ".claude/agents/<new-agent>.md"   # ADD THIS
  # ...
)
```

### 8. Update Manager Reference

**File:** `.claude/agents/manager.md`

Add the agent to the list of available agents and describe when to spawn it.

### 9. Update Documentation

**Files:** `README.md`, `README_CLAUDE.md`, and relevant policy docs

- Add agent to the factory overview
- Document its role in the pipeline
- Note any special conditions for its use

### 10. Test the Agent Integration

Manually test:
1. Spawn the agent via Task tool with sample context
2. Verify it respects tool permissions
3. Verify it produces the expected output format
4. Verify the Manager can parse its output and pass it to the next agent

## Verification Checklist

- [ ] Agent definition file exists at `.claude/agents/<agent-name>.md`
- [ ] Agent is assigned a model tier in `docs/policy/agents.md`
- [ ] Agent has MCP tool permissions defined in `docs/policy/agents.md`
- [ ] SYSTEM ARCHITECTURE diagram in `CLAUDE.md` includes the agent
- [ ] MANDATORY WORKFLOW section in `CLAUDE.md` includes spawn template
- [ ] QUICK REFERENCE spawn sequence includes the agent
- [ ] `health-check.sh` checks for the agent file
- [ ] Manager reference (`manager.md`) mentions the agent
- [ ] Agent produces output in the expected format
- [ ] Manager can successfully pass agent output to subsequent agents
- [ ] Agent respects its tool permissions (test with forbidden tool — should refuse)

## Common Pitfalls

1. **Unclear role definition.** Agents must have a single, well-defined purpose. Avoid multi-purpose agents.
2. **Missing output format specification.** The agent definition must include an exact output template.
3. **Tool permission conflicts.** Ensure the agent's tool permissions align with its role. Don't grant broad access.
4. **Forgetting to update spawn sequence.** The QUICK REFERENCE must show the new agent in context.
5. **No escalation path.** Every agent must define when it outputs NEEDS_MANAGER_ACTION.
6. **Model tier mismatch.** Opus is expensive — only use for complex reasoning. Haiku is for extraction, not analysis.
7. **Context bloat.** Don't pass entire previous outputs to every agent. Use the Evidence Pack pattern for large context.
8. **Missing Budget Block.** Every spawn template must include the Budget Block with complexity classification.

For troubleshooting guidance, see [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md).
