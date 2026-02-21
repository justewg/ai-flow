#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <task-id> <status-name> [flow-name]"
  echo "Example: $0 PL-003 \"In Progress\" \"In Progress\""
  exit 1
fi

task_id="$1"
status_name="$2"
flow_name="${3:-$2}"

project_id="PVT_kwHOAPt_Q84BPyyr"

project_json="$(
  gh api graphql \
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
        nodes {
          id
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
    -F itemsFirst=200
)"

item_id="$(
  printf '%s' "$project_json" |
    jq -r --arg task "$task_id" '
      .data.node.items.nodes[]
      | select(.fieldValueByName.text == $task)
      | .id
    '
)"
if [[ -z "$item_id" || "$item_id" == "null" ]]; then
  echo "Task not found in project: $task_id"
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

if [[ -z "$flow_option_id" || "$flow_option_id" == "null" ]]; then
  echo "Flow option not found: $flow_name"
  exit 1
fi

gh api graphql \
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

gh api graphql \
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

echo "Updated $task_id: Status=$status_name, Flow=$flow_name"
