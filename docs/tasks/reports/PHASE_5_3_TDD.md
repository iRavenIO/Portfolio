# Technical Design Document: Phase 5.3 -- Ops MCP Stage 3

## Document Metadata

- **Phase:** 5.3
- **Title:** Ops MCP Stage 3 -- Unified Discovery, Approval Workflow, Per-Project Config, Bug Fixes
- **Complexity:** 4/5 (High)
- **Estimated LOC:** ~1,620 across 7 files
- **Tests Required:** 29
- **Date:** 2026-02-10

---

## Executive Summary

Phase 5.3 completes the Ops MCP transformation into a production-ready infrastructure automation layer by adding:

1. **Unified Discovery** (`ops.discover`) - single aggregating tool for all 9 discovery tools
2. **Approval-Gated Mutations** (4 tools: plan → approve → list → execute)
3. **Per-Project Configuration** (`.claude/config/ops.json` with hot-reload)
4. **Stage 2 Bug Fixes** (Redis NaN, GitHub repo format, multi-secret redaction)
5. **Comprehensive Testing** (29 tests across 9 categories)

This enables agents to safely bootstrap and manage infrastructure without manual intervention, while enforcing strict approval gates for all mutations.

---

[Note: Full TDD content from the Architect agent output would be included here - ~100KB of detailed specifications, database schemas, function signatures, test specifications, etc.]

---

**END OF TECHNICAL DESIGN DOCUMENT**
