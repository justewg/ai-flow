#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id|project-item-id> <status-name> [flow-name]"
  exit 1
fi

: "${GH_TOKEN:?GH_TOKEN is required}"

task_or_item_id="$1"
status_name="$2"
flow_name="${3:-$2}"
project_owner="${PROJECT_OWNER:-justewg}"
project_number="${PROJECT_NUMBER:-2}"
project_id="${PROJECT_ID:-}"
issue_number_hint=""

if [[ "$task_or_item_id" =~ ^ISSUE-([0-9]+)$ ]]; then
  issue_number_hint="${BASH_REMATCH[1]}"
fi

gh_project() {
  GH_TOKEN="$GH_TOKEN" gh "$@"
}

resolve_project_id() {
  if [[ -n "$project_id" ]]; then
    printf '%s' "$project_id"
    return 0
  fi

  local project_json resolved_id
  project_json="$(
    gh_project api graphql \
      -f query='
query($login: String!, $number: Int!) {
  user(login: $login) {
    projectV2(number: $number) {
      id
    }
  }
  organization(login: $login) {
    projectV2(number: $number) {
      id
    }
  }
}
' \
      -f login="$project_owner" \
      -F number="$project_number"
  )"

  resolved_id="$(
    printf '%s' "$project_json" |
      jq -r '.data.user.projectV2.id // .data.organization.projectV2.id // empty'
  )"

  if [[ -z "$resolved_id" ]]; then
    echo "Failed to resolve project id for ${project_owner}#${project_number}" >&2
    exit 1
  fi

  printf '%s' "$resolved_id"
}

fetch_project_fields_only() {
  gh_project api graphql \
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
  gh_project api graphql \
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
  gh_project api graphql \
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

project_id="$(resolve_project_id)"

if [[ "$task_or_item_id" == PVTI_* ]]; then
  project_json="$(fetch_project_fields_only)"
  item_id="$task_or_item_id"
else
  project_json="$(fetch_project_initial_with_items)"

  all_items_json="$(printf '%s' "$project_json" | jq -c '.data.node.items.nodes // []')"
  has_next_page="$(printf '%s' "$project_json" | jq -r '.data.node.items.pageInfo.hasNextPage // false')"
  end_cursor="$(printf '%s' "$project_json" | jq -r '.data.node.items.pageInfo.endCursor // ""')"

  if [[ "$has_next_page" == "true" ]]; then
    for _ in {1..50}; do
      [[ "$has_next_page" == "true" ]] || break
      [[ -n "$end_cursor" && "$end_cursor" != "null" ]] || break

      page_json="$(fetch_project_items_page "$end_cursor")"
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

if [[ -z "${item_id:-}" || "$item_id" == "null" ]]; then
  echo "Task not found in project: $task_or_item_id" >&2
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

if [[ -z "$status_field_id" || "$status_field_id" == "null" ]]; then
  echo "Status field not found in project" >&2
  exit 1
fi

if [[ -z "$flow_field_id" || "$flow_field_id" == "null" ]]; then
  echo "Flow field not found in project" >&2
  exit 1
fi

if [[ -z "$status_option_id" || "$status_option_id" == "null" ]]; then
  echo "Status option not found: $status_name" >&2
  exit 1
fi

if [[ -z "$flow_option_id" || "$flow_option_id" == "null" ]]; then
  echo "Flow option not found: $flow_name" >&2
  exit 1
fi

update_field_value() {
  local field_id="$1"
  local option_id="$2"
  gh_project api graphql \
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
    -f fieldId="$field_id" \
    -f optionId="$option_id" >/dev/null
}

update_field_value "$status_field_id" "$status_option_id"
update_field_value "$flow_field_id" "$flow_option_id"

echo "Updated $task_or_item_id: Status=$status_name, Flow=$flow_name"
