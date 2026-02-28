#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"
PLAN_FILE="${BACKLOG_SEED_PLAN_FILE:-${CODEX_DIR}/backlog_seed_plan.json}"
PLAN_MD_FILE="${BACKLOG_SEED_PLAN_MD_FILE:-${CODEX_DIR}/backlog_seed_plan.md}"
MAX_PER_TICK_RAW="${BACKLOG_SEED_MAX_PER_TICK:-1}"

mkdir -p "$CODEX_DIR"

if ! [[ "$MAX_PER_TICK_RAW" =~ ^[0-9]+$ ]] || (( MAX_PER_TICK_RAW < 1 )); then
  MAX_PER_TICK=1
else
  MAX_PER_TICK="$MAX_PER_TICK_RAW"
fi

strip_quotes() {
  local value="$1"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "$value"
}

read_key_from_env_file() {
  local file_path="$1"
  local key="$2"
  [[ -f "$file_path" ]] || return 1
  local raw
  raw="$(grep -E "^${key}=" "$file_path" | tail -n1 | cut -d'=' -f2- || true)"
  [[ -n "$raw" ]] || return 1
  strip_quotes "$raw"
}

resolve_config_value() {
  local key="$1"
  local default_value="${2:-}"
  local env_value="${!key:-}"
  if [[ -n "$env_value" ]]; then
    printf '%s' "$env_value"
    return 0
  fi

  local env_candidates=()
  if [[ -n "${DAEMON_GH_ENV_FILE:-}" ]]; then
    env_candidates+=("${DAEMON_GH_ENV_FILE}")
  fi
  env_candidates+=("${ROOT_DIR}/.env")
  env_candidates+=("${ROOT_DIR}/.env.deploy")

  local env_file value
  for env_file in "${env_candidates[@]}"; do
    value="$(read_key_from_env_file "$env_file" "$key" || true)"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done

  printf '%s' "$default_value"
}

project_gh_token="$(resolve_config_value "DAEMON_GH_PROJECT_TOKEN" "")"
if [[ -z "$project_gh_token" ]]; then
  project_gh_token="$(resolve_config_value "CODEX_GH_PROJECT_TOKEN" "")"
fi
project_gh_token="$(printf '%s' "$project_gh_token" | tr -d '\r\n')"

run_gh_retry_capture() {
  local out=""
  local err_file
  err_file="$(mktemp "${CODEX_DIR}/seed_gh_err.XXXXXX")"
  if out="$("${ROOT_DIR}/scripts/codex/gh_retry.sh" "$@" 2>"$err_file")"; then
    if [[ -s "$err_file" ]]; then
      cat "$err_file" >&2
    fi
    rm -f "$err_file"
    printf '%s' "$out"
    return 0
  fi

  local rc=$?
  if [[ -s "$err_file" ]]; then
    cat "$err_file" >&2
  fi
  rm -f "$err_file"
  printf '%s\n' "$out" >&2
  return "$rc"
}

run_gh_retry_capture_project() {
  if [[ -n "$project_gh_token" ]]; then
    GH_TOKEN="$project_gh_token" run_gh_retry_capture "$@"
  else
    run_gh_retry_capture "$@"
  fi
}

render_plan_md() {
  if [[ ! -f "$PLAN_FILE" ]]; then
    rm -f "$PLAN_MD_FILE"
    return 0
  fi

  local count
  count="$(jq -r '(.tasks // []) | length' "$PLAN_FILE" 2>/dev/null || echo 0)"
  if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count == 0 )); then
    rm -f "$PLAN_MD_FILE"
    return 0
  fi

  jq -r '
    . as $root
    | "# Backlog Seed Plan (runtime)\n"
    + "Source: " + (($root.source_plan // "(not set)")|tostring) + "\n"
    + "Repo: " + (($root.repo // "justewg/planka")|tostring) + "\n"
    + "Project: " + (($root.project_owner // "@me")|tostring) + "/" + (($root.project_number // 2)|tostring) + "\n"
    + "Remaining tasks: " + ((($root.tasks // []) | length)|tostring) + "\n\n"
    + ((($root.tasks // []) | to_entries | map(
        "## " + .value.code + " — " + .value.title + "\n"
        + "- Plan key: `" + ((.value.plan_key // "")|tostring) + "`\n"
        + "- Depends-On-Codes: " + (((.value.depends_on_codes // []) | join(", ")) // "") + "\n"
        + "- Description: " + ((.value.description // "")|tostring) + "\n"
      )) | join("\n"))
  ' "$PLAN_FILE" > "$PLAN_MD_FILE" 2>/dev/null || true
}

find_issue_by_code() {
  local repo="$1"
  local code="$2"
  local out
  if out="$(run_gh_retry_capture gh issue list --repo "$repo" --state all --search "\"[$code]\" in:title" --limit 1 --json number,url,title --jq '.[0] // empty')"; then
    :
  else
    local rc=$?
    return "$rc"
  fi
  printf '%s' "$out"
}

trim_csv_token() {
  local token="$1"
  token="$(printf '%s' "$token" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$token"
}

build_refs_from_codes() {
  local repo="$1"
  local csv_codes="$2"
  local refs=()

  if [[ -z "$csv_codes" || "$csv_codes" == "none" ]]; then
    printf 'none'
    return 0
  fi

  local code_list
  IFS=',' read -r -a code_list <<< "$csv_codes"
  local code raw issue_json issue_num rc
  for raw in "${code_list[@]}"; do
    code="$(trim_csv_token "$raw")"
    [[ -z "$code" ]] && continue

    if ! issue_json="$(find_issue_by_code "$repo" "$code")"; then
      rc=$?
      [[ "$rc" -eq 75 ]] && return 75
      continue
    fi

    issue_num="$(printf '%s' "$issue_json" | jq -r '.number // ""')"
    if [[ -n "$issue_num" && "$issue_num" != "null" ]]; then
      refs+=("#${issue_num}")
    fi
  done

  if (( ${#refs[@]} == 0 )); then
    printf 'none'
  else
    local joined=""
    local idx
    for idx in "${!refs[@]}"; do
      if [[ "$idx" -gt 0 ]]; then
        joined+=", "
      fi
      joined+="${refs[$idx]}"
    done
    printf '%s' "$joined"
  fi
}

write_issue_body() {
  local source_plan="$1"
  local plan_key="$2"
  local description="$3"
  local depends_refs="$4"
  local blocks_refs="$5"
  local body_file="$6"

  cat > "$body_file" <<BODY_EOF
## Context
- Source plan: ${source_plan}
- Plan item: \`${plan_key}\`

## Task
${description}

## Acceptance Criteria
- [ ] Реализовано в соответствии с деталями plan item.
- [ ] Изменения не противоречат текущим ограничениям MVP и narrative.
- [ ] Результат верифицируется в целевом артефакте (web/print/assets/copy).

## Flow Meta
Depends-On: ${depends_refs}
Blocks: ${blocks_refs}
Auto-Queue-When-Unblocked: false
Execution-Mode: daemon
BODY_EOF
}

apply_task_to_project_backlog() {
  local project_number="$1"
  local project_owner="$2"
  local issue_url="$3"
  local issue_number="$4"
  local add_out set_out rc attempt

  if add_out="$(run_gh_retry_capture_project gh project item-add "$project_number" --owner "$project_owner" --url "$issue_url" 2>&1)"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "BACKLOG_SEED_WAIT_GITHUB=1"
      echo "BACKLOG_SEED_WAIT_STAGE=PROJECT_ITEM_ADD"
      return 75
    fi
    if ! printf '%s' "$add_out" | grep -Eiq 'already exists|already in project|item already'; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "BACKLOG_SEED_PROJECT_ADD_WARN: $line"
      done <<< "$add_out"
    fi
  fi

  for attempt in 1 2 3 4 5; do
    if set_out="$("${ROOT_DIR}/scripts/codex/project_set_status.sh" "ISSUE-${issue_number}" "Backlog" "Backlog" 2>&1)"; then
      echo "$set_out"
      return 0
    fi
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "BACKLOG_SEED_WAIT_GITHUB=1"
      echo "BACKLOG_SEED_WAIT_STAGE=PROJECT_SET_STATUS"
      return 75
    fi
    if printf '%s' "$set_out" | grep -Eiq 'error connecting to api\.github\.com|could not resolve host|connection timed out|tls handshake timeout|temporary failure in name resolution'; then
      echo "BACKLOG_SEED_WAIT_GITHUB=1"
      echo "BACKLOG_SEED_WAIT_STAGE=PROJECT_SET_STATUS"
      return 75
    fi
    sleep 2
  done

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "BACKLOG_SEED_PROJECT_STATUS_WARN: $line"
  done <<< "$set_out"
  return 1
}

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "BACKLOG_SEED_PLAN_ABSENT=1"
  exit 0
fi

if ! jq -e '.tasks and (.tasks | type == "array")' "$PLAN_FILE" >/dev/null 2>&1; then
  echo "BACKLOG_SEED_PLAN_INVALID=1"
  echo "BACKLOG_SEED_PLAN_FILE=${PLAN_FILE}"
  exit 0
fi

source_plan="$(jq -r '.source_plan // "PRESENTATION_PATCH_PLAN_v2"' "$PLAN_FILE")"
repo="$(jq -r '.repo // "justewg/planka"' "$PLAN_FILE")"
project_owner="$(jq -r '.project_owner // "@me"' "$PLAN_FILE")"
project_number="$(jq -r '.project_number // 2' "$PLAN_FILE")"

remaining_count="$(jq -r '.tasks | length' "$PLAN_FILE")"
if ! [[ "$remaining_count" =~ ^[0-9]+$ ]]; then
  remaining_count=0
fi

if (( remaining_count == 0 )); then
  rm -f "$PLAN_FILE" "$PLAN_MD_FILE"
  echo "BACKLOG_SEED_PLAN_DONE=1"
  exit 0
fi

processed=0
while (( processed < MAX_PER_TICK )); do
  remaining_count="$(jq -r '.tasks | length' "$PLAN_FILE")"
  if ! [[ "$remaining_count" =~ ^[0-9]+$ ]] || (( remaining_count == 0 )); then
    break
  fi

  task_json="$(jq -c '.tasks[0]' "$PLAN_FILE")"
  code="$(printf '%s' "$task_json" | jq -r '.code // ""')"
  title="$(printf '%s' "$task_json" | jq -r '.title // ""')"
  description="$(printf '%s' "$task_json" | jq -r '.description // ""')"
  plan_key="$(printf '%s' "$task_json" | jq -r '.plan_key // .code // ""')"
  depends_codes_csv="$(printf '%s' "$task_json" | jq -r '(.depends_on_codes // []) | join(",")')"
  blocks_codes_csv="$(printf '%s' "$task_json" | jq -r '(.blocks_codes // []) | join(",")')"

  if [[ -z "$blocks_codes_csv" ]]; then
    blocks_codes_csv="$(jq -r --arg code "$code" '[.tasks[] | select(((.depends_on_codes // []) | index($code)) != null) | .code] | join(",")' "$PLAN_FILE")"
  fi

  if [[ -z "$code" || -z "$title" || -z "$description" ]]; then
    echo "BACKLOG_SEED_PLAN_INVALID_TASK=1"
    echo "BACKLOG_SEED_PLAN_INVALID_CODE=${code}"
    tmp_plan="$(mktemp "${CODEX_DIR}/seed_plan.XXXXXX")"
    jq 'if (.tasks | length) > 0 then .tasks |= .[1:] else . end' "$PLAN_FILE" > "$tmp_plan"
    mv "$tmp_plan" "$PLAN_FILE"
    render_plan_md
    continue
  fi

  issue_json=""
  if issue_json="$(find_issue_by_code "$repo" "$code")"; then
    :
  else
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      echo "BACKLOG_SEED_WAIT_GITHUB=1"
      echo "BACKLOG_SEED_WAIT_STAGE=ISSUE_LOOKUP"
      break
    fi
    echo "BACKLOG_SEED_ISSUE_LOOKUP_WARN=${code}"
    break
  fi

  issue_number="$(printf '%s' "$issue_json" | jq -r '.number // ""')"
  issue_url="$(printf '%s' "$issue_json" | jq -r '.url // ""')"

  if [[ -z "$issue_number" || "$issue_number" == "null" ]]; then
    if depends_refs="$(build_refs_from_codes "$repo" "$depends_codes_csv")"; then
      :
    else
      rc=$?
      if [[ "$rc" -eq 75 ]]; then
        echo "BACKLOG_SEED_WAIT_GITHUB=1"
        echo "BACKLOG_SEED_WAIT_STAGE=DEPENDS_RESOLVE"
        break
      fi
      depends_refs="none"
    fi

    if blocks_refs="$(build_refs_from_codes "$repo" "$blocks_codes_csv")"; then
      :
    else
      rc=$?
      if [[ "$rc" -eq 75 ]]; then
        echo "BACKLOG_SEED_WAIT_GITHUB=1"
        echo "BACKLOG_SEED_WAIT_STAGE=BLOCKS_RESOLVE"
        break
      fi
      blocks_refs="none"
    fi

    if [[ -z "$depends_refs" ]]; then
      depends_refs="none"
    fi
    if [[ -z "$blocks_refs" ]]; then
      blocks_refs="none"
    fi

    body_file="$(mktemp "${CODEX_DIR}/seed_issue_body.XXXXXX")"
    write_issue_body "$source_plan" "$plan_key" "$description" "$depends_refs" "$blocks_refs" "$body_file"

    create_out=""
    if ! create_out="$(run_gh_retry_capture gh issue create --repo "$repo" --title "[${code}] ${title}" --body-file "$body_file")"; then
      rc=$?
      rm -f "$body_file"
      if [[ "$rc" -eq 75 ]]; then
        echo "BACKLOG_SEED_WAIT_GITHUB=1"
        echo "BACKLOG_SEED_WAIT_STAGE=ISSUE_CREATE"
        break
      fi
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "BACKLOG_SEED_ISSUE_CREATE_WARN: $line"
      done <<< "$create_out"
      break
    fi
    rm -f "$body_file"

    issue_url="$(printf '%s\n' "$create_out" | tail -n1 | tr -d '[:space:]')"
    if [[ "$issue_url" =~ /issues/([0-9]+)$ ]]; then
      issue_number="${BASH_REMATCH[1]}"
    else
      echo "BACKLOG_SEED_ISSUE_CREATE_WARN=PARSE_URL_FAILED"
      break
    fi

    echo "BACKLOG_SEED_ISSUE_CREATED=1"
    echo "BACKLOG_SEED_TASK_CODE=${code}"
    echo "BACKLOG_SEED_ISSUE_NUMBER=${issue_number}"
  fi

  if ! apply_task_to_project_backlog "$project_number" "$project_owner" "$issue_url" "$issue_number"; then
    rc=$?
    if [[ "$rc" -eq 75 ]]; then
      break
    fi
    echo "BACKLOG_SEED_PROJECT_APPLY_WARN=${code}"
    break
  fi

  tmp_plan="$(mktemp "${CODEX_DIR}/seed_plan.XXXXXX")"
  jq 'if (.tasks | length) > 0 then .tasks |= .[1:] else . end' "$PLAN_FILE" > "$tmp_plan"
  mv "$tmp_plan" "$PLAN_FILE"

  processed=$(( processed + 1 ))
  echo "BACKLOG_SEED_TASK_APPLIED=1"
  echo "BACKLOG_SEED_TASK_CODE=${code}"
  echo "BACKLOG_SEED_ISSUE_NUMBER=${issue_number}"

done

remaining_count="$(jq -r '.tasks | length' "$PLAN_FILE" 2>/dev/null || echo 0)"
if [[ "$remaining_count" =~ ^[0-9]+$ ]] && (( remaining_count == 0 )); then
  rm -f "$PLAN_FILE" "$PLAN_MD_FILE"
  echo "BACKLOG_SEED_PLAN_DONE=1"
else
  render_plan_md
  echo "BACKLOG_SEED_REMAINING_COUNT=${remaining_count}"
  echo "BACKLOG_SEED_PLAN_FILE=${PLAN_FILE}"
  echo "BACKLOG_SEED_PLAN_MD_FILE=${PLAN_MD_FILE}"
fi

exit 0
