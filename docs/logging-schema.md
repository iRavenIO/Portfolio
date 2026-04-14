# Structured Logging Schema

## Overview

The autonomous software factory uses structured JSON logging to track all work
across the multi-agent pipeline. Every execution emits timestamped events to
`.claude/logs/run-YYYYMMDD-HHMMSS.log`.

## Log File Location

```
.claude/logs/run-<YYYYMMDD>-<HHMMSS>.log
```

Each run generates a unique log file named with its start timestamp.

## Schema

Every JSON log line contains these fields:

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | ISO 8601 UTC timestamp (e.g., `2026-02-05T19:30:15Z`) |
| `run_id` | string | Unique run identifier (format: `YYYYMMDD-HHMMSS`) |
| `phase` | string | Pipeline phase (see Phase Values below) |
| `task_id` | string | Task identifier (e.g., `1`, `2`, `3`) or empty for run-level events |
| `event` | string | Event type (see Event Types below) |
| `status` | string | Event outcome: `ok`, `fail`, or `skip` |
| `duration_ms` | number | Duration in milliseconds (0 for instant events) |
| `message` | string | Human-readable event description |

## Event Types

| Event | Description |
|-------|-------------|
| `run_start` | Logging system initialized |
| `run_end` | Entire run completed |
| `phase_start` | Pipeline phase began |
| `phase_end` | Pipeline phase completed |
| `task_start` | Task began |
| `task_end` | Task completed |
| `info` | Informational message |
| `error` | Error occurred |

## Phase Values

Phases correspond to the autonomous pipeline:

- `startup` — Run initialization
- `detection` — Task detection (Phase 0)
- `analysis` — Analyst agent (Phase 1)
- `research` — Researcher agent (Phase 2)
- `architecture` — Architect agent (Phase 3)
- `implementation` — Developer loop (Phase 4)
- `review` — Reviewer agent (Phase 4B)
- `testing` — Tester agent (Phase 4C)
- `reporting` — Reporter agent (Phase 5)
- `batch` — Batch completion (Phase 6, multi-task only)
- `task` — Task-level events (multi-task only)
- `summary` — Final summary

## Status Values

- `ok` — Success or normal completion
- `fail` — Failure or error
- `skip` — Phase skipped (e.g., research not needed)

## RUN SUMMARY Block

At the end of each log, a human-readable summary block is written:

```
========================================
RUN SUMMARY
========================================
Run ID:        20260205-193015
Total Tasks:   3
Succeeded:     2
Failed:        1
Tags Status:   ok
Report:        /path/to/report.md
Duration:      5m 42s
========================================
```

This block is NOT JSON — it's for quick human scanning.

## Parsing Logs

Extract JSON lines only:

```bash
grep '^{' .claude/logs/run-20260205-193015.log | jq .
```

Filter by event type:

```bash
grep '^{' <logfile> | jq 'select(.event == "phase_end")'
```

Calculate total duration:

```bash
grep '^{' <logfile> | jq -s 'map(select(.event == "run_end")) | .[0].duration_ms / 1000'
```

## Helper Function Reference

| Function | Purpose |
|----------|---------|
| `log_init <run_id> <log_file>` | Initialize logging system |
| `log_event <phase> <task_id> <event> <status> <duration_ms> <message>` | Emit a JSON log line |
| `log_phase_start <phase> [task_id]` | Mark phase start and begin duration tracking |
| `log_phase_end <phase> <status> [task_id] [message]` | Mark phase end and emit duration |
| `log_task_start <task_id>` | Mark task start and begin duration tracking |
| `log_task_end <task_id> <status>` | Mark task end and emit duration |
| `log_error <phase> <message> [task_id]` | Emit an error event |
| `log_info <phase> <message> [task_id]` | Emit an informational event |
| `log_summary <total> <succeeded> <failed> <tags_status> <report_path>` | Write final summary and run_end event |
