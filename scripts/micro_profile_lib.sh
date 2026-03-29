#!/usr/bin/env bash

micro_profile_state_dir() {
  local task_id="$1"
  local issue_number="$2"
  local state_dir="${3:-}"
  local profile="${4:-${PROJECT_PROFILE:-default}}"
  task_worktree_execution_dir "$task_id" "$issue_number" "$state_dir" "$profile"
}

micro_profile_issue_json() {
  local issue_number="$1"
  local repo="$2"
  gh issue view "$issue_number" --repo "$repo" --json title,body,number --jq '.'
}

micro_profile_issue_title() {
  local issue_json="$1"
  printf '%s' "$issue_json" | jq -r '.title // ""'
}

micro_profile_issue_body() {
  local issue_json="$1"
  printf '%s' "$issue_json" | jq -r '.body // ""'
}

micro_profile_trim() {
  local raw="${1:-}"
  printf '%s' "$raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

micro_profile_title_without_task_id() {
  local raw="${1:-}"
  printf '%s' "$raw" | sed -E 's/^\[[^]]+\][[:space:]]*//'
}

micro_profile_slugify_label() {
  local raw="${1:-}"
  printf '%s' "$raw" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

micro_profile_extract_target_files() {
  local issue_text="${1:-}"
  local root_dir="${2:-$ROOT_DIR}"
  local tmp_file

  tmp_file="$(mktemp)"
  printf '%s\n' "$issue_text" \
    | rg -o '`[^`]+`' \
    | sed -E 's/^`//; s/`$//' \
    | while IFS= read -r candidate; do
        [[ -z "$candidate" ]] && continue
        if [[ -e "${root_dir}/${candidate}" ]]; then
          printf '%s\n' "$candidate"
        elif [[ "$candidate" == ./* && -e "${root_dir}/${candidate#./}" ]]; then
          printf '%s\n' "${candidate#./}"
        fi
      done \
    | awk '!seen[$0]++' > "$tmp_file"

  cat "$tmp_file"
  rm -f "$tmp_file"
}

micro_profile_extract_check_commands() {
  local issue_body="${1:-}"
  local in_checks="0"
  local trimmed=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^Проверки: ]]; then
      in_checks="1"
      continue
    fi

    if [[ "$line" =~ ^Вне\ scope: || "$line" =~ ^Вне\ scope ]]; then
      break
    fi

    if [[ "$in_checks" != "1" ]]; then
      continue
    fi

    if [[ "$line" =~ ^-[[:space:]]*\`(.+)\`[[:space:]]*$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      continue
    fi

    if [[ "$line" =~ ^-[[:space:]]*(.+)$ ]]; then
      trimmed="${BASH_REMATCH[1]}"
      trimmed="$(printf '%s' "$trimmed" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [[ -n "$trimmed" ]] || continue
      if [[ "$trimmed" == \`* && "$trimmed" == *\` ]]; then
        trimmed="${trimmed#\`}"
        trimmed="${trimmed%\`}"
      fi
      printf '%s\n' "$trimmed"
    fi
  done <<< "$issue_body"
}

micro_profile_allowlist_verification_command() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || return 1

  case "$cmd" in
    "bash -n "*)
      return 0
      ;;
    "./.flow/shared/scripts/run.sh "*)
      return 0
      ;;
    "rg -n "*)
      return 0
      ;;
    "jq -e "*)
      return 0
      ;;
    "git status --short"|"git diff --name-only"*|"git diff --no-ext-diff "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

micro_profile_file_context_json() {
  local repo_path="$1"
  local relative_path="$2"
  local max_lines="${3:-160}"
  local file_path="${repo_path}/${relative_path}"
  local total_lines
  local content

  if [[ ! -f "$file_path" ]]; then
    jq -nc --arg path "$relative_path" '{path:$path, present:false, lineCount:0, excerpt:""}'
    return 0
  fi

  total_lines="$(wc -l < "$file_path" | tr -d '[:space:]')"
  if (( total_lines > max_lines )); then
    content="$(sed -n "1,${max_lines}p" "$file_path")"
  else
    content="$(cat "$file_path")"
  fi

  jq -nc \
    --arg path "$relative_path" \
    --arg excerpt "$content" \
    --argjson present true \
    --argjson lineCount "${total_lines:-0}" \
    '{path:$path, present:$present, lineCount:$lineCount, excerpt:$excerpt}'
}

micro_profile_budget_init_json() {
  local task_id="$1"
  local issue_number="$2"
  local threshold_tokens="${3:-15000}"
  local enforce="${4:-0}"
  jq -nc \
    --arg taskId "$task_id" \
    --arg issueNumber "$issue_number" \
    --argjson thresholdTokens "$threshold_tokens" \
    --argjson maxCalls 2 \
    --argjson enforceProfileBreach "$( [[ "$enforce" == "1" ]] && printf 'true' || printf 'false' )" \
    '{
      taskId:$taskId,
      issueNumber:$issueNumber,
      profile:"micro",
      callCount:0,
      maxCalls:$maxCalls,
      totalInputTokens:0,
      totalOutputTokens:0,
      totalTokens:0,
      thresholdTokens:$thresholdTokens,
      estimatedCostUsd:null,
      costEstimateMode:"unavailable",
      enforceProfileBreach:$enforceProfileBreach,
      status:"initialized",
      profileBreach:false
    }'
}
