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
  local line
  local trimmed_line
  local candidate

  tmp_file="$(mktemp)"

  while IFS= read -r line; do
    trimmed_line="$(micro_profile_trim "$line")"

    if [[ "$trimmed_line" == "Проверки:" || "$trimmed_line" == "Вне scope:" || "$trimmed_line" == "Вне scope" ]]; then
      break
    fi

    if [[ "$trimmed_line" == -[[:space:]]Не\ * || "$trimmed_line" == -[[:space:]]не\ * ]]; then
      continue
    fi
    if [[ "$trimmed_line" == *"не трогать"* || "$trimmed_line" == *"не менять"* || "$trimmed_line" == *"любые изменения"* ]]; then
      continue
    fi

    while IFS= read -r candidate; do
      [[ -z "$candidate" ]] && continue
      [[ "$candidate" == *" "* ]] && continue
      candidate="$(printf '%s' "$candidate" | sed -E 's/^`//; s/`$//')"
      if [[ -e "${root_dir}/${candidate}" ]]; then
        printf '%s\n' "$candidate"
      elif [[ "$candidate" == ./* && -e "${root_dir}/${candidate#./}" ]]; then
        printf '%s\n' "${candidate#./}"
      fi
    done < <(printf '%s\n' "$trimmed_line" | rg -o '`[^`]+`')
  done <<< "$issue_text" | awk '!seen[$0]++' > "$tmp_file"

  cat "$tmp_file"
  rm -f "$tmp_file"
}

micro_profile_extract_check_commands() {
  local issue_body="${1:-}"
  local in_checks="0"
  local trimmed_line=""
  local item=""
  local trimmed=""

  while IFS= read -r line; do
    trimmed_line="$(micro_profile_trim "$line")"

    if [[ "$trimmed_line" == "Проверки:" ]]; then
      in_checks="1"
      continue
    fi

    if [[ "$trimmed_line" == "Вне scope:" || "$trimmed_line" == "Вне scope" ]]; then
      break
    fi

    if [[ "$in_checks" != "1" ]]; then
      continue
    fi

    if [[ "$trimmed_line" != -[[:space:]]* ]]; then
      continue
    fi

    item="${trimmed_line#- }"
    item="$(micro_profile_trim "$item")"
    [[ -n "$item" ]] || continue

    if [[ "$item" == \`* && "$item" == *\` ]]; then
      item="${item#\`}"
      item="${item%\`}"
      printf '%s\n' "$item"
      continue
    fi

    trimmed="$item"
    printf '%s\n' "$trimmed"
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
    "git status --short"|"git diff --name-only"*|"git diff --no-ext-diff "*|"git diff -- "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

micro_profile_extract_context_anchors() {
  local issue_text="${1:-}"
  local token
  local cleaned

  {
    while IFS= read -r token; do
      [[ -n "$token" ]] || continue
      cleaned="$(printf '%s' "$token" | sed -E 's/^`//; s/`$//')"
      [[ -n "$cleaned" ]] || continue
      if [[ "$cleaned" == */* || "$cleaned" == ./* || "$cleaned" == *" "* || "$cleaned" =~ ^PL-[0-9]+$ ]]; then
        continue
      fi
      printf '%s\n' "$cleaned"
    done < <(printf '%s\n' "$issue_text" | rg -o '`[^`]+`' || true)

    while IFS= read -r token; do
      [[ -n "$token" ]] || continue
      case "$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')" in
        narrative|index|html|scope|checks|issue|task|block|frame|device|screen|pl-[0-9]*)
          continue
          ;;
        *)
          if [[ "$token" == *- && "$token" != *[_-]*[[:alnum:]] ]]; then
            continue
          fi
          if [[ "$token" == *[_-]* ]]; then
            printf '%s\n' "$token"
          elif [[ "$token" == "hero" || "$token" == "caption" || "$token" == "subtitle" || "$token" == "overlay" || "$token" == "aria-label" ]]; then
            printf '%s\n' "$token"
          elif (( ${#token} >= 7 )); then
            printf '%s\n' "$token"
          fi
          ;;
      esac
    done < <(
      printf '%s\n' "$issue_text" \
        | rg -o '[A-Za-z][A-Za-z0-9_-]{3,}' \
        | tr '[:upper:]' '[:lower:]' \
        || true
    )
  } | awk 'NF && !seen[$0]++'
}

micro_profile_extract_excerpt_ranges() {
  local file_path="$1"
  local issue_text="${2:-}"
  local max_lines="${3:-140}"
  local before_context="${4:-12}"
  local after_context="${5:-20}"
  local total_lines
  local anchor_count="0"
  local anchor

  total_lines="$(wc -l < "$file_path" | tr -d '[:space:]')"

  if (( total_lines <= max_lines )); then
    printf '1:%s\n' "${total_lines:-1}"
    return 0
  fi

  while IFS= read -r anchor; do
    [[ -n "$anchor" ]] || continue
    anchor_count=$((anchor_count + 1))
    awk \
      -v needle="$anchor" \
      -v before="$before_context" \
      -v after="$after_context" \
      '
        BEGIN {
          needle_lc = tolower(needle)
          matches = 0
          max_matches = (needle_lc == "aria-label" || needle_lc == "alt" || needle_lc == "role") ? 1 : 2
        }
        {
          line_lc = tolower($0)
          if (index(line_lc, needle_lc) > 0) {
            start = NR - before
            end = NR + after
            if (start < 1) start = 1
            print start ":" end
            matches++
            if (matches >= max_matches) exit
          }
        }
      ' "$file_path"
  done < <(micro_profile_extract_context_anchors "$issue_text")
}

micro_profile_merge_excerpt_ranges() {
  local total_lines="$1"
  shift || true

  if (( $# == 0 )); then
    printf '1:%s\n' "$(( total_lines > 120 ? 120 : total_lines ))"
    return 0
  fi

  printf '%s\n' "$@" \
    | sort -t: -k1,1n -k2,2n \
    | awk -F: -v total="$total_lines" '
        NF != 2 { next }
        {
          start = $1 + 0
          end = $2 + 0
          if (start < 1) start = 1
          if (end > total) end = total
          if (end < start) next
          ranges[++n] = start ":" end
        }
        END {
          if (n == 0) {
            print "1:" (total > 120 ? 120 : total)
            exit
          }
          split(ranges[1], parts, ":")
          current_start = parts[1] + 0
          current_end = parts[2] + 0
          for (i = 2; i <= n; i++) {
            split(ranges[i], parts, ":")
            start = parts[1] + 0
            end = parts[2] + 0
            if (start <= current_end + 1) {
              if (end > current_end) current_end = end
            } else {
              print current_start ":" current_end
              current_start = start
              current_end = end
            }
          }
          print current_start ":" current_end
        }
      '
}

micro_profile_file_context_json() {
  local repo_path="$1"
  local relative_path="$2"
  local issue_text="${3:-}"
  local max_lines="${4:-140}"
  local file_path="${repo_path}/${relative_path}"
  local total_lines
  local content
  local content_file
  local range
  local start_line
  local end_line
  local raw_ranges=()
  local merged_ranges=()
  local excerpt_lines="0"

  if [[ ! -f "$file_path" ]]; then
    jq -nc --arg path "$relative_path" '{path:$path, present:false, lineCount:0, excerpt:""}'
    return 0
  fi

  total_lines="$(wc -l < "$file_path" | tr -d '[:space:]')"
  while IFS= read -r range; do
    [[ -n "$range" ]] || continue
    raw_ranges+=("$range")
  done < <(micro_profile_extract_excerpt_ranges "$file_path" "$issue_text" "$max_lines" || true)

  while IFS= read -r range; do
    [[ -n "$range" ]] || continue
    merged_ranges+=("$range")
  done < <(micro_profile_merge_excerpt_ranges "$total_lines" "${raw_ranges[@]}")

  if (( ${#merged_ranges[@]} == 0 )); then
    merged_ranges=("1:$(( total_lines > max_lines ? max_lines : total_lines ))")
  fi

  content_file="$(mktemp)"
  for range in "${merged_ranges[@]}"; do
    start_line="${range%%:*}"
    end_line="${range##*:}"
    [[ -n "$start_line" && -n "$end_line" ]] || continue
    if (( excerpt_lines > 0 )); then
      printf '\n' >> "$content_file"
    fi
    printf '@@ lines %s-%s @@\n' "$start_line" "$end_line" >> "$content_file"
    sed -n "${start_line},${end_line}p" "$file_path" >> "$content_file"
    excerpt_lines=$((excerpt_lines + end_line - start_line + 1))
  done
  content="$(cat "$content_file")"
  rm -f "$content_file"

  jq -nc \
    --arg path "$relative_path" \
    --arg excerpt "$content" \
    --argjson present true \
    --argjson lineCount "${total_lines:-0}" \
    --argjson excerptLineCount "${excerpt_lines:-0}" \
    '{path:$path, present:$present, lineCount:$lineCount, excerptLineCount:$excerptLineCount, excerpt:$excerpt}'
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
