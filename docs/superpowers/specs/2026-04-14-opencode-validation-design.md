# OpenCode Validation + Hardening Design

## Goal

Validate and harden the OpenCode overlay so staged reporting and routing are
operational, then verify rollout into two real projects without redesigning the
factory.

## Scope

- Validate .opencode overlay consistency and references
- Strengthen router and mode contracts for staged reporting
- Improve project templates for real project usage
- Roll out with cfactory to two target repos and populate project context
- Validate six scenario classes against router/mode expectations
- Keep changes minimal and preserve copy-based installs

## Non-Goals

- Rewriting Claude Factory policies
- Building a new OpenCode orchestration engine
- Changing cfactory to symlinks

## Current State Summary

- .opencode overlay exists with router and mode files
- AGENTS profiles load .opencode and .claude context
- cfactorylite includes OpenCode assets and generates missing per-project files
- install and validation helpers exist

## Design Decisions

1) Keep .claude policies as the source of truth.
2) Encode staged reporting and routing expectations in .opencode/router.md
3) Expand mode files to include required reporting contracts and tool priority
4) Extend project templates to include real-world fields (commands, rules)
5) Use cfactory copy-based install for rollout validation

## Validation Plan

1) Internal consistency checks
   - Verify .opencode references and AGENTS alignment
   - Confirm no conflicts with Claude policies
2) Function A: staged reporting
   - Ensure router + mode files explicitly require pre/during/post reporting
3) Function B: intelligent selection
   - Clarify routing rules and tie-breakers in router
4) Rollout to two repos
   - Run cfactory in both targets
   - Verify generated files and populate project context
5) Scenario checks
   - Validate Plan/Debug/Build/Refactor/Review/Report mapping

## Acceptance Criteria

- Router and modes encode staged reporting and tool priority
- Mode selection is explicit and unambiguous
- Project templates are usable without rework
- Two target repos have populated .opencode and .claude context files
- No changes to cfactory copy-based behavior

## Risks

- Overfitting router rules to the current projects
- Excess verbosity in mode requirements

## Rollback

- Revert .opencode edits and template changes only
