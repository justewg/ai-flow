#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"
codex_resolve_project_config

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id|project-item-id> <status-name> [flow-name]"
  echo "Examples:"
  echo "  $0 PL-003 \"In Progress\" \"In Progress\""
  echo "  $0 PVTI_xxxxx \"In Progress\" \"In Progress\""
  exit 1
fi

task_or_item_id="$1"
status_name="$2"
flow_name="${3:-$2}"
issue_number_hint=""
if [[ "$task_or_item_id" =~ ^ISSUE-([0-9]+)$ ]]; then
  issue_number_hint="${BASH_REMATCH[1]}"
fi

project_id="$PROJECT_ID"

project_token="$(codex_resolve_config_value "DAEMON_GH_PROJECT_TOKEN" "")"
if [[ -z "$project_token" ]]; then
  project_token="$(codex_resolve_config_value "CODEX_GH_PROJECT_TOKEN" "")"
fi
project_token="$(printf '%s' "$project_token" | tr -d '\r\n')"

strip_quotes() {
  codex_strip_quotes "$1"
}

read_key_from_env_file() {
  codex_read_key_from_env_file "$1" "$2"
}

run_project_gh() {
  if [[ -n "$project_token" ]]; then
    GH_TOKEN="$project_token" gh "$@"
  else
    gh "$@"
  fi
}

fetch_project_fields_only() {
  run_project_gh api graphql \
    -f query='
query($projectId: ID!, $fieldsFirst: Int!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      fields(first: $fieldsFirst) {
        nodes {
          __typename
          ... on ProjectV2Field {
            id
            name
            dataType
          }
          ... on ProjectV2IterationField {
            id
            name
            dataType
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            dataType
            options {
              id
              name
            }
          }
        }
      }
    }
  }
}
' \
    -f projectId="$project_id" \
    -F fieldsFirst=100
}

fetch_project_initial_with_items() {
  run_project_gh api graphql \
    -f query='
query($projectId: ID!, $fieldsFirst: Int!, $itemsFirst: Int!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      fields(first: $fieldsFirst) {
        nodes {
          __typename
          ... on ProjectV2Field {
            id
            name
            dataType
          }
          ... on ProjectV2IterationField {
            id
            name
            dataType
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            dataType
            options {
              id
              name
            }
          }
        }
      }
      items(first: $itemsFirst) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          content {
            __typename
            ... on DraftIssue { title }
            ... on Issue { title number }
            ... on PullRequest { title number }
          }
          fieldValueByName(name: "Task ID") {
            __typename
            ... on ProjectV2ItemFieldTextValue {
              text
            }
          }
        }
      }
    }
  }
}
' \
    -f projectId="$project_id" \
    -F fieldsFirst=100 \
    -F itemsFirst=100
}

fetch_project_items_page() {
  local after_cursor="$1"
  run_project_gh api graphql \
    -f query='
query($projectId: ID!, $itemsFirst: Int!, $after: String!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: $itemsFirst, after: $after) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          content {
            __typename
            ... on DraftIssue { title }
            ... on Issue { title number }
            ... on PullRequest { title number }
          }
          fieldValueByName(name: "Task ID") {
            __typename
            ... on ProjectV2ItemFieldTextValue {
              text
            }
          }
        }
      }
    }
  }
}
' \
    -f projectId="$project_id" \
    -F itemsFirst=100 \
    -f after="$after_cursor"
}

if [[ "$task_or_item_id" == PVTI_* ]]; then
  project_json="$(
    fetch_project_fields_only
  )"
  item_id="$task_or_item_id"
else
  project_json="$(
    fetch_project_initial_with_items
  )"

  all_items_json="$(printf '%s' "$project_json" | jq -c '.data.node.items.nodes // []')"
  has_next_page="$(printf '%s' "$project_json" | jq -r '.data.node.items.pageInfo.hasNextPage // false')"
  end_cursor="$(printf '%s' "$project_json" | jq -r '.data.node.items.pageInfo.endCursor // ""')"

  if [[ "$has_next_page" == "true" ]]; then
    for _ in {1..50}; do
      [[ "$has_next_page" != "true" ]] && break
      [[ -z "$end_cursor" || "$end_cursor" == "null" ]] && break

      page_json="$(
        fetch_project_items_page "$end_cursor"
      )"

      page_items_json="$(printf '%s' "$page_json" | jq -c '.data.node.items.nodes // []')"
      all_items_json="$(jq -c -n --argjson acc "$all_items_json" --argjson page "$page_items_json" '$acc + $page')"
      has_next_page="$(printf '%s' "$page_json" | jq -r '.data.node.items.pageInfo.hasNextPage // false')"
      end_cursor="$(printf '%s' "$page_json" | jq -r '.data.node.items.pageInfo.endCursor // ""')"
    done
  fi

  item_id="$(
    printf '%s' "$all_items_json" |
      jq -r --arg task "$task_or_item_id" --arg issue_num "$issue_number_hint" '
        .[]
        | select(
            (.fieldValueByName.text // "") == $task
            or ((.content.title // "") | contains($task))
            or (
              ($issue_num != "")
              and ((.content.__typename // "") == "Issue")
              and ((.content.number // "") | tostring) == $issue_num
            )
          )
        | .id
      ' |
      head -n1
  )"
fi
if [[ -z "$item_id" || "$item_id" == "null" ]]; then
  echo "Task not found in project: $task_or_item_id"
  exit 1
fi

status_field_id="$(printf '%s' "$project_json" | jq -r '.data.node.fields.nodes[] | select(.name=="Status") | .id')"
flow_field_id="$(printf '%s' "$project_json" | jq -r '.data.node.fields.nodes[] | select(.name=="Flow") | .id')"

status_option_id="$(
  printf '%s' "$project_json" |
    jq -r --arg name "$status_name" '.data.node.fields.nodes[] | select(.name=="Status") | .options[] | select(.name==$name) | .id'
)"
flow_option_id="$(
  printf '%s' "$project_json" |
    jq -r --arg name "$flow_name" '.data.node.fields.nodes[] | select(.name=="Flow") | .options[] | select(.name==$name) | .id'
)"

if [[ -z "$status_option_id" || "$status_option_id" == "null" ]]; then
  echo "Status option not found: $status_name"
  exit 1
fi

if [[ -z "$status_field_id" || "$status_field_id" == "null" ]]; then
  echo "Status field not found in project"
  exit 1
fi

if [[ -z "$flow_option_id" || "$flow_option_id" == "null" ]]; then
  echo "Flow option not found: $flow_name"
  exit 1
fi

if [[ -z "$flow_field_id" || "$flow_field_id" == "null" ]]; then
  echo "Flow field not found in project"
  exit 1
fi

run_project_gh api graphql \
  -f query='
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(
    input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: { singleSelectOptionId: $optionId }
    }
  ) {
    projectV2Item {
      id
    }
  }
}
' \
  -f projectId="$project_id" \
  -f itemId="$item_id" \
  -f fieldId="$status_field_id" \
  -f optionId="$status_option_id" >/dev/null

run_project_gh api graphql \
  -f query='
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(
    input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: { singleSelectOptionId: $optionId }
    }
  ) {
    projectV2Item {
      id
    }
  }
}
' \
  -f projectId="$project_id" \
  -f itemId="$item_id" \
  -f fieldId="$flow_field_id" \
  -f optionId="$flow_option_id" >/dev/null

echo "Updated $task_or_item_id: Status=$status_name, Flow=$flow_name"
