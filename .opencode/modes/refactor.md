# Mode: Refactor

Use when: structure changes without behavior change.
Tools: Read/Edit/Write, MCP git/fs/rg.
Tool priority: MCP first, Bash fallback.
Edits: allowed.
Output: diff summary + safety notes + tests.
Required reporting:
- Pre: mode + refactor plan + invariants
- During: progress update after key change
- Post: diff summary + tests + verification
