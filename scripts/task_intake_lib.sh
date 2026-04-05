#!/usr/bin/env bash

task_intake_issue_json() {
  local issue_number="$1"
  local repo="$2"
  gh issue view "$issue_number" --repo "$repo" --json title,body,number --jq '.'
}

task_intake_issue_title() {
  local issue_json="$1"
  printf '%s' "$issue_json" | jq -r '.title // ""'
}

task_intake_issue_body() {
  local issue_json="$1"
  printf '%s' "$issue_json" | jq -r '.body // ""'
}

task_intake_reply_text() {
  local task_id="$1"
  local codex_dir
  local reply_task

  codex_dir="$(codex_export_state_dir)"
  reply_task="$(cat "${codex_dir}/daemon_user_reply_task_id.txt" 2>/dev/null || true)"
  if [[ "$reply_task" == "$task_id" && -s "${codex_dir}/daemon_user_reply.txt" ]]; then
    cat "${codex_dir}/daemon_user_reply.txt"
  fi
}

task_intake_compose_source_json() {
  local task_id="$1"
  local issue_number="$2"
  local repo="$3"
  local profile_name="$4"
  local issue_json="$5"
  local issue_title="$6"
  local issue_body="$7"
  local reply_text="$8"
  local captured_at
  local source_hash

  captured_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  source_hash="$(
    jq -nc \
      --arg taskId "$task_id" \
      --arg issueNumber "$issue_number" \
      --arg repo "$repo" \
      --arg title "$issue_title" \
      --arg body "$issue_body" \
      --arg replyText "$reply_text" \
      '{taskId:$taskId, issueNumber:$issueNumber, repo:$repo, title:$title, body:$body, replyText:$replyText}' \
      | shasum -a 256 | awk '{print $1}'
  )"

  jq -nc \
    --arg taskId "$task_id" \
    --arg issueNumber "$issue_number" \
    --arg repo "$repo" \
    --arg profileName "$profile_name" \
    --arg title "$issue_title" \
    --arg body "$issue_body" \
    --arg replyText "$reply_text" \
    --arg capturedAt "$captured_at" \
    --arg sourceHash "$source_hash" \
    '{
      kind:"source_definition",
      taskId:$taskId,
      issueNumber:$issueNumber,
      repo:$repo,
      profileName:$profileName,
      title:$title,
      body:$body,
      replyText:$replyText,
      capturedAt:$capturedAt,
      sourceHash:$sourceHash
    }'
}

task_intake_extract_expected_change_lines() {
  local issue_body="${1:-}"
  local in_scope="0"
  local trimmed_line=""
  local item=""

  while IFS= read -r line; do
    trimmed_line="$(micro_profile_trim "$line")"

    if [[ "$trimmed_line" == "Что сделать:" ]]; then
      in_scope="1"
      continue
    fi

    if [[ "$trimmed_line" == "Проверки:" || "$trimmed_line" == "Вне scope:" || "$trimmed_line" == "Вне scope" ]]; then
      break
    fi

    if [[ "$in_scope" != "1" ]]; then
      continue
    fi

    [[ "$trimmed_line" == -[[:space:]]* ]] || continue
    item="${trimmed_line#- }"
    item="$(micro_profile_trim "$item")"
    [[ -n "$item" ]] || continue
    printf '%s\n' "$item"
  done <<< "$issue_body"
}

task_intake_extract_notes_lines() {
  local issue_body="${1:-}"
  local in_notes="0"
  local trimmed_line=""
  local item=""

  while IFS= read -r line; do
    trimmed_line="$(micro_profile_trim "$line")"

    if [[ "$trimmed_line" == "Вне scope:" || "$trimmed_line" == "Вне scope" ]]; then
      in_notes="1"
      continue
    fi

    if [[ "$in_notes" != "1" ]]; then
      continue
    fi

    [[ "$trimmed_line" == -[[:space:]]* ]] || continue
    item="${trimmed_line#- }"
    item="$(micro_profile_trim "$item")"
    [[ -n "$item" ]] || continue
    printf '%s\n' "$item"
  done <<< "$issue_body"
}

task_intake_interpreted_intent() {
  local issue_title="$1"
  local issue_body="$2"
  local reply_text="${3:-}"
  local first_change

  first_change="$(task_intake_extract_expected_change_lines "$reply_text" | head -n1)"
  if [[ -n "$first_change" ]]; then
    printf '%s' "$first_change"
    return 0
  fi

  first_change="$(task_intake_extract_expected_change_lines "$issue_body" | head -n1)"
  if [[ -n "$first_change" ]]; then
    printf '%s' "$first_change"
    return 0
  fi

  if [[ -n "$(micro_profile_trim "$reply_text")" ]]; then
    printf '%s' "$(micro_profile_trim "$reply_text")"
    return 0
  fi

  micro_profile_title_without_task_id "$issue_title"
}

task_intake_extract_attribute_literals() {
  local text="${1:-}"

  printf '%s\n' "$text" \
    | grep -Eo '[[:alpha:]_:-][[:alnum:]_:-]*="[^"]+"' \
    | awk '
        {
          split($0, parts, "=")
          name=parts[1]
          if (name ~ /^(aria-[A-Za-z0-9_-]+|alt|role|title)$/) print $0
        }
      ' \
    | awk '!seen[$0]++'
}

task_intake_extract_anchor_tokens() {
  local text="${1:-}"

  {
    printf '%s\n' "$text" | grep -Eo '\.[A-Za-z0-9_-]+' | sed 's/^\.//' | awk '/[-_]/'
    printf '%s\n' "$text" | grep -Eo 'class="[^"]+"' | sed -E 's/^class="|"$//g' | tr ' ' '\n'
    printf '%s\n' "$text" | grep -Eo '>[[:space:]]*[^<][^<]+[[:space:]]*<' | sed -E 's/^>[[:space:]]*//; s/[[:space:]]*<$//'
  } | sed '/^$/d' | awk '!seen[$0]++'
}

task_intake_extract_file_paths() {
  local text="${1:-}"

  printf '%s\n' "$text" \
    | grep -Eo '([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+' \
    | awk '/\.[A-Za-z0-9]+$/ && !seen[$0]++'
}

task_intake_small_change_signal() {
  local combined_text="$1"
  printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]' | rg -q '(alias|readme|docs|documentation|help|label|usage|copy|rename|dispatch|aria-label|alt|role|subtitle|caption|подпись|кнопк|клавиатур|пробел|иконк|крестик|андроид)'
}

task_intake_denied_execution_patterns() {
  cat <<'EOF'
secrets
secret
token rotation
billing
payment
quota top-up
credential
credentials
EOF
}

task_intake_standard_profile_terms() {
  cat <<'EOF'
.flow/shared
.github/
docker
workflow
ci
auth
finalize
watchdog
daemon
executor
submodule
runtime-v2
runtime_v2
infra
toolkit
android
андроид
android app
android-прилож
android прилож
клавиатур
keyboard
space button
пробел
кнопк
toolbar
app bar
mainactivity
activity_main.xml
androidmanifest.xml
kiosk
EOF
}

task_intake_manual_or_dependency_signal() {
  local combined_text="$1"
  printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]' | rg -q \
    '(execution-mode:[[:space:]]*manual|manual-only|manual only|requires physical access|требует физический доступ|depends-on:|depends on|auto-queue-when-unblocked:[[:space:]]*false)'
}

task_intake_structured_spec_signal() {
  local combined_text="$1"
  local downcased
  downcased="$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$downcased" | rg -q '##[[:space:]]*(context|task|scope|expected|problem|requirements|acceptance|evidence|dependencies|flow meta|контекст|задач|что должно получиться|требования|критерии|критерий|dependencies|scope|expected outcome)'; then
    return 0
  fi
  if [[ "$(printf '%s' "$combined_text" | grep -c '^- ' || true)" -ge 4 ]]; then
    return 0
  fi
  return 1
}

task_intake_docs_scoped_micro_signal() {
  local target_files_json="$1"
  local markdown_count non_markdown_count
  markdown_count="$(printf '%s' "$target_files_json" | jq '[.[] | select(test("\\.md$|README\\.md$"))] | length')"
  non_markdown_count="$(printf '%s' "$target_files_json" | jq '[.[] | select((test("\\.md$|README\\.md$") | not) and . != ".flow/shared")] | length')"
  [[ "$markdown_count" -ge 1 && "$non_markdown_count" -eq 0 ]]
}

task_intake_android_fallback_target_files() {
  local combined_text="${1:-}"
  local root_dir="${2:-$ROOT_DIR}"
  local combined_downcased
  local keyboard_signal="false"

  combined_downcased="$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')"
  if ! printf '%s' "$combined_downcased" | rg -q '(андроид|android|клавиатур|keyboard|пробел|space|kiosk|lock task|device owner)'; then
    return 0
  fi

  if printf '%s' "$combined_downcased" | rg -q '(клавиатур|keyboard|пробел|space)'; then
    keyboard_signal="true"
    [[ -f "${root_dir}/app/planka_quick_test_app/app/src/main/assets/index.html" ]] \
      && printf '%s\n' 'app/planka_quick_test_app/app/src/main/assets/index.html'
    [[ -f "${root_dir}/app/planka_quick_test_app/app/src/main/assets/ui-shell-config.default.json" ]] \
      && printf '%s\n' 'app/planka_quick_test_app/app/src/main/assets/ui-shell-config.default.json'
  fi

  if printf '%s' "$combined_downcased" | rg -q '(mainactivity|activity|киоск|kiosk|lock task|device owner|manifest)'; then
    [[ -f "${root_dir}/app/planka_quick_test_app/app/src/main/java/com/planka/quicktest/MainActivity.kt" ]] \
      && printf '%s\n' 'app/planka_quick_test_app/app/src/main/java/com/planka/quicktest/MainActivity.kt'
    [[ -f "${root_dir}/app/planka_quick_test_app/app/src/main/AndroidManifest.xml" ]] \
      && printf '%s\n' 'app/planka_quick_test_app/app/src/main/AndroidManifest.xml'
  fi

  if [[ "$keyboard_signal" != "true" ]] && printf '%s' "$combined_downcased" | rg -q '(подпись|label|кнопк|button|строк|string|текст)'; then
    [[ -f "${root_dir}/app/planka_quick_test_app/app/src/main/res/values/strings.xml" ]] \
      && printf '%s\n' 'app/planka_quick_test_app/app/src/main/res/values/strings.xml'
  fi
}

task_intake_profile_decision_json() {
  local combined_text="$1"
  local target_count="$2"
  local target_files_json="$3"
  local interpreted_intent="$4"
  local small_change="false"
  local decision="standard"
  local reason="intake_default_standard"
  local confidence_label="medium"
  local confidence_score="0.62"
  local rationale_json='[]'
  local combined_downcased
  local term
  local found=""
  local android_ui_signal="false"

  combined_downcased="$(printf '%s' "$combined_text" | tr '[:upper:]' '[:lower:]')"
  if task_intake_small_change_signal "$combined_text"; then
    small_change="true"
  fi
  if printf '%s' "$combined_downcased" | rg -q '(андроид|android|клавиатур|keyboard|пробел|space button|крестик|кнопк)'; then
    android_ui_signal="true"
  fi

  while IFS= read -r term; do
    [[ -n "$term" ]] || continue
    if [[ "$combined_downcased" == *"$term"* ]]; then
      found="$term"
      break
    fi
  done < <(task_intake_denied_execution_patterns)

  if [[ -n "$found" ]]; then
    decision="blocked"
    reason="intake_blocked_${found//[^a-z0-9]/_}"
    confidence_label="high"
    confidence_score="0.95"
  elif task_intake_manual_or_dependency_signal "$combined_text"; then
    decision="blocked"
    reason="intake_blocked_manual_or_dependency"
    confidence_label="high"
    confidence_score="0.94"
  else
    if [[ "$android_ui_signal" == "true" && "$small_change" == "true" ]] && (( target_count <= 2 )); then
      decision="micro"
      reason="intake_micro_android_ui_small_change"
      confidence_label="high"
      confidence_score="0.91"
    elif [[ "$android_ui_signal" == "true" ]]; then
      decision="standard"
      reason="intake_standard_android_ui"
      confidence_label="high"
      confidence_score="0.89"
    elif [[ "$small_change" == "true" ]] && task_intake_docs_scoped_micro_signal "$target_files_json"; then
      decision="micro"
      reason="intake_docs_scoped_change"
      confidence_label="high"
      confidence_score="0.9"
    else
      found=""
      while IFS= read -r term; do
        [[ -n "$term" ]] || continue
        if [[ "$combined_downcased" == *"$term"* ]]; then
          found="$term"
          break
        fi
      done < <(task_intake_standard_profile_terms)
    fi

    if [[ -n "$found" ]]; then
      decision="standard"
      reason="intake_standard_${found//[^a-z0-9]/_}"
      confidence_label="high"
      confidence_score="0.89"
    elif [[ "$decision" == "micro" ]]; then
      :
    elif [[ "$reason" == "intake_standard_android_ui" ]]; then
      :
    elif (( target_count == 0 )); then
      if task_intake_structured_spec_signal "$combined_text"; then
        decision="standard"
        reason="intake_structured_spec_without_targets"
        confidence_label="medium"
        confidence_score="0.68"
      else
        decision="human_needed"
        reason="intake_target_files_ambiguous"
        confidence_label="low"
        confidence_score="0.31"
      fi
    elif (( target_count > 2 )); then
      decision="standard"
      reason="intake_target_count_${target_count}"
      confidence_label="medium"
      confidence_score="0.66"
    elif [[ "$small_change" == "true" ]]; then
      decision="micro"
      reason="intake_small_scoped_change"
      confidence_label="high"
      confidence_score="0.92"
    else
      decision="standard"
      reason="intake_requires_broader_reasoning"
      confidence_label="medium"
      confidence_score="0.58"
    fi
  fi

  rationale_json="$(
    jq -nc \
      --arg decision "$decision" \
      --arg reason "$reason" \
      --arg intent "$interpreted_intent" \
      --argjson targetCount "$target_count" \
      --argjson targetFiles "$target_files_json" \
      --argjson smallChange "$( [[ "$small_change" == "true" ]] && printf 'true' || printf 'false' )" \
      '[
        ("decision=" + $decision),
        ("reason=" + $reason),
        ("target_count=" + ($targetCount|tostring)),
        ("small_change=" + ($smallChange|tostring)),
        ("intent=" + $intent)
      ] + ($targetFiles | map("target_file=" + .))'
  )"

  jq -nc \
    --arg decision "$decision" \
    --arg reason "$reason" \
    --arg confidenceLabel "$confidence_label" \
    --argjson confidenceScore "$confidence_score" \
    --argjson rationale "$rationale_json" \
    '{
      profileDecision:$decision,
      reason:$reason,
      confidence:{
        label:$confidenceLabel,
        score:$confidenceScore
      },
      rationale:$rationale
    }'
}
