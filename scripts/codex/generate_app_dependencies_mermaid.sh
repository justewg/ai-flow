#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEX_DIR="${ROOT_DIR}/.tmp/codex"

repo="${GITHUB_REPO:-justewg/planka}"
issues_limit="${APP_ISSUES_LIMIT:-200}"
output_file="${1:-${ROOT_DIR}/docs/app-issues-dependency-diagram.md}"

mkdir -p "${CODEX_DIR}"

if ! command -v gh >/dev/null 2>&1; then
  echo "Команда gh не найдена в PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Команда jq не найдена в PATH" >&2
  exit 1
fi

trim() {
  local value="$1"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$value"
}

parse_flow_meta_line() {
  local body="$1"
  local key="$2"
  local value
  value="$(
    printf '%s\n' "$body" |
      awk -v k="$key" '
        BEGIN { IGNORECASE = 1 }
        {
          line=$0
          gsub("\r","",line)
          if (tolower(line) ~ "^" tolower(k) "[[:space:]]*:") {
            sub(/^[^:]*:[[:space:]]*/, "", line)
            print line
            exit
          }
        }
      '
  )"
  trim "$value"
}

tokenize_refs_line() {
  local refs_line="$1"
  local normalized
  local token
  normalized="${refs_line//;/,}"
  IFS=',' read -r -a tokens <<< "$normalized"
  for token in "${tokens[@]}"; do
    token="$(trim "$token")"
    [[ -z "$token" ]] && continue
    if [[ "$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')" == "none" ]]; then
      continue
    fi
    printf '%s\n' "$token"
  done
}

resolve_ref_to_issue_number() {
  local ref_token="$1"
  local apps_json_file="$2"
  local upper_ref mapped_number

  if [[ "$ref_token" =~ ^#([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$ref_token" =~ ^([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if printf '%s' "$ref_token" | grep -Eq '^[Ii][Ss][Ss][Uu][Ee]-[0-9]+$'; then
    printf '%s\n' "$ref_token" | sed -E 's/^[Ii][Ss][Ss][Uu][Ee]-([0-9]+)$/\1/'
    return 0
  fi

  if printf '%s' "$ref_token" | grep -Eq '^https?://[^[:space:]]+/issues/[0-9]+/?$'; then
    printf '%s\n' "$ref_token" | sed -E 's#^.*/issues/([0-9]+)/?$#\1#'
    return 0
  fi

  if printf '%s' "$ref_token" | grep -Eq '^[Aa][Pp][Pp]-[0-9]+$'; then
    upper_ref="$(printf '%s' "$ref_token" | tr '[:lower:]' '[:upper:]')"
    mapped_number="$(
      jq -r --arg app_key "$upper_ref" '.[] | select(.app_key == $app_key) | .number' "$apps_json_file" |
        head -n1
    )"
    if [[ -n "$mapped_number" && "$mapped_number" != "null" ]]; then
      printf '%s\n' "$mapped_number"
      return 0
    fi
    return 3
  fi

  return 1
}

sanitize_mermaid_label() {
  local label="$1"
  label="$(printf '%s' "$label" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
  label="${label//\\/\\\\}"
  label="${label//\"/\'}"
  label="$(trim "$label")"
  printf '%s' "$label"
}

issues_json=""
if issues_json="$(
  "${ROOT_DIR}/scripts/codex/gh_retry.sh" \
    gh issue list \
    --repo "$repo" \
    --state all \
    --limit "$issues_limit" \
    --json number,title,body,state,url
)"; then
  :
else
  rc=$?
  exit "$rc"
fi

apps_file="$(mktemp "${CODEX_DIR}/app_deps_apps.XXXXXX.json")"
nodes_raw_file="$(mktemp "${CODEX_DIR}/app_deps_nodes_raw.XXXXXX.txt")"
nodes_sorted_file="$(mktemp "${CODEX_DIR}/app_deps_nodes_sorted.XXXXXX.txt")"
edges_raw_file="$(mktemp "${CODEX_DIR}/app_deps_edges_raw.XXXXXX.txt")"
edges_sorted_file="$(mktemp "${CODEX_DIR}/app_deps_edges_sorted.XXXXXX.txt")"
warnings_raw_file="$(mktemp "${CODEX_DIR}/app_deps_warnings_raw.XXXXXX.txt")"
warnings_sorted_file="$(mktemp "${CODEX_DIR}/app_deps_warnings_sorted.XXXXXX.txt")"

cleanup() {
  rm -f \
    "$apps_file" \
    "$nodes_raw_file" \
    "$nodes_sorted_file" \
    "$edges_raw_file" \
    "$edges_sorted_file" \
    "$warnings_raw_file" \
    "$warnings_sorted_file"
}
trap cleanup EXIT

printf '%s' "$issues_json" |
  jq -c '
    [
      .[]
      | . + {app_key: (try (.title | capture("(?i)(?<app>APP-[0-9]+)").app | ascii_upcase) catch "")}
      | select(.app_key != "")
    ]
    | sort_by((.app_key | sub("^APP-"; "") | tonumber), .number)
  ' > "$apps_file"

app_count="$(jq 'length' "$apps_file")"

if [[ "$app_count" -gt 0 ]]; then
  while IFS= read -r issue_row; do
    issue_number="$(printf '%s' "$issue_row" | jq -r '.number')"
    issue_body="$(printf '%s' "$issue_row" | jq -r '.body // ""')"

    printf '%s\n' "$issue_number" >> "$nodes_raw_file"

    depends_line="$(parse_flow_meta_line "$issue_body" "Depends-On")"
    blocks_line="$(parse_flow_meta_line "$issue_body" "Blocks")"

    while IFS= read -r ref_token; do
      [[ -z "$ref_token" ]] && continue
      if resolved_issue="$(resolve_ref_to_issue_number "$ref_token" "$apps_file")"; then
        printf '%s\n' "$resolved_issue" >> "$nodes_raw_file"
        printf '%s,%s\n' "$resolved_issue" "$issue_number" >> "$edges_raw_file"
      else
        rc=$?
        if [[ "$rc" -eq 3 ]]; then
          printf 'Issue #%s: Depends-On содержит неизвестный APP-референс "%s"\n' "$issue_number" "$ref_token" >> "$warnings_raw_file"
        else
          printf 'Issue #%s: Depends-On содержит нераспознанный токен "%s"\n' "$issue_number" "$ref_token" >> "$warnings_raw_file"
        fi
      fi
    done < <(tokenize_refs_line "$depends_line")

    while IFS= read -r ref_token; do
      [[ -z "$ref_token" ]] && continue
      if resolved_issue="$(resolve_ref_to_issue_number "$ref_token" "$apps_file")"; then
        printf '%s\n' "$resolved_issue" >> "$nodes_raw_file"
        printf '%s,%s\n' "$issue_number" "$resolved_issue" >> "$edges_raw_file"
      else
        rc=$?
        if [[ "$rc" -eq 3 ]]; then
          printf 'Issue #%s: Blocks содержит неизвестный APP-референс "%s"\n' "$issue_number" "$ref_token" >> "$warnings_raw_file"
        else
          printf 'Issue #%s: Blocks содержит нераспознанный токен "%s"\n' "$issue_number" "$ref_token" >> "$warnings_raw_file"
        fi
      fi
    done < <(tokenize_refs_line "$blocks_line")
  done < <(jq -c '.[]' "$apps_file")
fi

if [[ -s "$nodes_raw_file" ]]; then
  sort -n -u "$nodes_raw_file" > "$nodes_sorted_file"
else
  : > "$nodes_sorted_file"
fi

if [[ -s "$edges_raw_file" ]]; then
  sort -t',' -k1,1n -k2,2n -u "$edges_raw_file" > "$edges_sorted_file"
else
  : > "$edges_sorted_file"
fi

if [[ -s "$warnings_raw_file" ]]; then
  sort -u "$warnings_raw_file" > "$warnings_sorted_file"
else
  : > "$warnings_sorted_file"
fi

node_count="$(wc -l < "$nodes_sorted_file" | tr -d '[:space:]')"
edge_count="$(wc -l < "$edges_sorted_file" | tr -d '[:space:]')"
warning_count="$(wc -l < "$warnings_sorted_file" | tr -d '[:space:]')"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$(dirname "$output_file")"

{
  echo "# Диаграмма зависимостей APP-issues"
  echo
  echo "Сгенерировано: \`${generated_at}\`."
  echo
  echo "Источник данных:"
  echo "- Репозиторий: \`${repo}\`"
  echo "- Выборка: \`gh issue list --state all --limit ${issues_limit}\`"
  echo "- Найдено APP-issues: \`${app_count}\`"
  echo
  echo '```mermaid'
  echo 'flowchart TD'
  echo '  classDef app fill:#EAF4FF,stroke:#1D4ED8,color:#0F172A;'
  echo '  classDef external fill:#F3F4F6,stroke:#6B7280,color:#111827;'

  if [[ "$node_count" -eq 0 ]]; then
    echo '  %% APP-issues не найдены в текущей выборке.'
  else
    while IFS= read -r node_number; do
      app_meta="$(
        jq -r --argjson issue_number "$node_number" '
          .[] | select(.number == $issue_number) | [.app_key, .title] | @tsv
        ' "$apps_file" | head -n1
      )"

      if [[ -n "$app_meta" ]]; then
        app_key="${app_meta%%$'\t'*}"
        app_title="${app_meta#*$'\t'}"
        short_title="$(printf '%s' "$app_title" | sed -E 's/^[Aa][Pp][Pp]-[0-9]+[[:space:]]*//')"
        if [[ -n "$short_title" && "$short_title" != "$app_title" ]]; then
          node_label="${app_key} · #${node_number} · ${short_title}"
        else
          node_label="${app_key} · #${node_number}"
        fi
        node_label="$(sanitize_mermaid_label "$node_label")"
        printf '  I%s["%s"]\n' "$node_number" "$node_label"
      else
        node_label="$(sanitize_mermaid_label "#${node_number}")"
        printf '  I%s["%s"]\n' "$node_number" "$node_label"
      fi
    done < "$nodes_sorted_file"

    if [[ "$edge_count" -gt 0 ]]; then
      while IFS=',' read -r edge_from edge_to; do
        [[ -z "$edge_from" || -z "$edge_to" ]] && continue
        printf '  I%s --> I%s\n' "$edge_from" "$edge_to"
      done < "$edges_sorted_file"
    fi

    while IFS= read -r node_number; do
      if jq -e --argjson issue_number "$node_number" '.[] | select(.number == $issue_number)' "$apps_file" >/dev/null; then
        printf '  class I%s app;\n' "$node_number"
      else
        printf '  class I%s external;\n' "$node_number"
      fi
    done < "$nodes_sorted_file"
  fi

  echo '```'
  echo
  if [[ "$warning_count" -gt 0 ]]; then
    echo "## Ошибки парсинга"
    while IFS= read -r warning_line; do
      [[ -z "$warning_line" ]] && continue
      echo "- ${warning_line}"
    done < "$warnings_sorted_file"
  else
    echo "Ошибки парсинга: не обнаружены."
  fi
} > "$output_file"

echo "APP_DEPS_DIAGRAM_FILE=$output_file"
echo "APP_DEPS_APP_ISSUES=$app_count"
echo "APP_DEPS_NODES=$node_count"
echo "APP_DEPS_EDGES=$edge_count"
echo "APP_DEPS_WARNINGS=$warning_count"
