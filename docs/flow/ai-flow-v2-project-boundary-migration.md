# AI Flow v2 Project Boundary Migration

## Purpose

This document fixes the boundary between:

- `ai-flow` as the project-agnostic toolkit/runtime
- a consumer repository such as `PLANKA`

The rule is simple:

- if a file can be reused by another GitHub repository without changing its meaning, it belongs in `ai-flow`
- if a file documents or encodes facts about a specific consumer repository, it stays in that consumer repository

## Move To ai-flow

These assets are platform/runtime assets and should live in `/.flow/shared`:

- `runtime-v2/*`
- provider contracts, routing, telemetry, compare and rollout gate logic
- Claude/Codex adapters and invocation plan builders
- shared shell wrappers:
  - `scripts/claude_provider_run.sh`
  - `scripts/claude_provider_probe.sh`
  - `scripts/claude_provider_health_clear.sh`
  - `scripts/provider_*`
  - `scripts/intake_contract_artifact.sh`
  - `scripts/intake_compare_artifact.sh`
- provider runtime tool:
  - `tools/providers/claude/run_claude_provider.mjs`
  - `tools/providers/claude/package.json`
- generic AI Flow docs:
  - `docs/flow/ai-flow-v2-complete-reference.md`
  - `docs/flow/ai-flow-v2-next-implementation-backlog.md`
  - `docs/flow/ai-flow-v2-claude-delta-01.md`
  - `docs/flow/ai-flow-v2-claude-integration-task.md`

## Keep In Consumer Repo

These assets remain in `PLANKA` because they are project-specific:

- issue-specific or repo-specific findings
- Android kiosk findings and runbooks
- empirical compare notes tied to concrete `PLANKA` issues
- consumer-specific prompts, agents or repo conventions

Current examples that stay in `PLANKA`:

- `docs/flow/ai-flow-v2-claude-shadow-intake-findings.md`
- Android shell / Lenovo test documentation
- `.claude/*` if it encodes `PLANKA` repo knowledge

## Split If Needed

Some docs may need a generic copy in `ai-flow` plus a consumer-specific findings file:

- GraphQL usage audits
- rollout notes that mix platform design and concrete issue examples
- intake mismatch investigations

The generic part belongs in `ai-flow`.
The evidence or issue-by-issue findings stay in the consumer repo.

## Current Migration Status

Already migrated into `/.flow/shared`:

- `runtime-v2`
- Claude provider runner and shell wrappers
- intake compare/contract artifacts
- provider telemetry and rollout gate scripts
- core generic AI Flow v2 docs under `docs/flow/`

Still intentionally left in `PLANKA`:

- `docs/flow/ai-flow-v2-claude-shadow-intake-findings.md`

## Operational Consequence

Further platform work should be done primarily from the live submodule checkout:

- `/var/sites/PLANKA/.flow/shared`

Then pushed and merged in `ai-flow`, after which consumer repositories can pull the submodule update.
