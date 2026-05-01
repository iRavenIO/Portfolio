# Project Context

Use this file to give Claude Code and OpenCode the same repo-specific connection map.

## Read First

- List the first docs or files to inspect before making assumptions.

## Application Topology

- State the primary app components.
- State the main database type: MySQL, PostgreSQL, Supabase, Redis, etc.
- State the default local or deployment host/port names if known.

## Secrets And Connection Discovery

- State whether app secrets live in `.env.local`, Vault, or both.
- If Vault is used, list the relevant paths.
- If shared infrastructure Vault paths are relevant, point to them explicitly.

## Connection Rules

- Call out any traps, such as:
  - local compose uses MySQL but generic `.env.example` mentions Postgres
  - app-level `.env.example` files are more accurate than the repo root one
  - Supabase staging/production are selected by app-specific env vars

## Useful Files

- Add the specific docs, compose files, and env templates that explain the real topology.
