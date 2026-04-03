#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env/bootstrap.sh"

TASK_ID="CLAUDE-PROBE"
ISSUE_NUMBER="0"
REQUEST_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-probe-request.XXXXXX.json")"
RESPONSE_FILE="$(mktemp "${TMPDIR:-/tmp}/claude-probe-response.XXXXXX.json")"

cleanup() {
  rm -f "$REQUEST_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

jq -nc \
  '{
    "module":"intake.interpretation",
    input:{
      taskId:"CLAUDE-PROBE",
      issueNumber:0,
      title:"Probe",
      body:"Confirm the provider can return a small canonical JSON response.",
      replyText:"",
      candidateTargetFiles:["README.md"],
      repositoryContext:{
        repo:"justewg/planka",
        repoRoot:".",
        profileName:"default",
        repoHints:["This is a provider health probe, not a real task."]
      }
    },
    promptText:"Task ID: CLAUDE-PROBE\n\nIssue: #0\n\nTitle: Probe\n\nBody:\nConfirm the provider can return a small canonical JSON response.\n\nReply: <empty>\n\nCandidate target files:\n- README.md\n\nRepository hints:\n- This is a provider health probe, not a real task.\n\nReturn JSON only with fields:\n- decision: micro|standard|human_needed|blocked\n- decisionReason: string\n- interpretedIntent: string\n- confidence: { label, score }\n- candidateTargetFiles: string[]\n- rationale: string[]\n- askHumanQuestion: string|null"
  }' > "$REQUEST_FILE"

/bin/bash "${SCRIPT_DIR}/claude_provider_run.sh" \
  --module "intake.interpretation" \
  --request-file "$REQUEST_FILE" \
  --response-file "$RESPONSE_FILE" \
  --task-id "$TASK_ID" \
  --issue-number "$ISSUE_NUMBER" \
  --task-repo "$ROOT_DIR"
