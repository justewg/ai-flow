#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env/bootstrap.sh
source "${SCRIPT_DIR}/env/bootstrap.sh"

target_repo=""
profile=""
migration_kit=""
shared_url=""
shared_branch=""
shared_revision=""
bootstrap_source="auto"
force="0"
allow_dirty_tracked="0"
dry_run="0"

usage() {
  cat <<'EOF'
Usage: .flow/shared/scripts/bootstrap_repo.sh --target-repo <path> [options]

Bootstrap/materialize `.flow` в целевом repo и подключить `/.flow/shared` как git-submodule.

Options:
  --target-repo <path>        Путь к целевому git-репозиторию (обязательно).
  --profile <name>            PROJECT_PROFILE для target repo. По умолчанию:
                              flow.env -> flow.sample.env -> migration kit -> basename repo.
  --migration-kit <path>      Путь к migration_kit.tgz для распаковки перед bootstrap.
  --bootstrap-source <mode>   auto|submodule|migration_kit (по умолчанию: auto).
  --shared-url <url>          URL toolkit submodule (по умолчанию: origin текущего .flow/shared).
  --shared-branch <name>      Branch для submodule add/update (по умолчанию: origin/HEAD или main).
  --shared-revision <rev>     Commit/tag toolkit, который нужно зафиксировать в target repo.
                              По умолчанию: текущий HEAD toolkit или revision из migration kit manifest.
  --force                     Разрешить overwrite для apply_migration_kit.
  --allow-dirty-tracked       Не блокировать repair/overwrite на tracked diff в управляемых путях.
  --dry-run                   Только показать действия без изменений.
  -h, --help                  Показать справку.

Examples:
  .flow/shared/scripts/bootstrap_repo.sh --target-repo /tmp/acme --profile acme
  .flow/shared/scripts/bootstrap_repo.sh --target-repo /tmp/acme --migration-kit ./migration_kit.tgz
EOF
}

slugify() {
  codex_slugify_value "${1:-}"
}

print_quoted_cmd() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

run_cmd() {
  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN '
    print_quoted_cmd "$@"
    return 0
  fi
  "$@"
}

ensure_dir() {
  local dir_path="$1"
  run_cmd mkdir -p "$dir_path"
}

ensure_file() {
  local file_path="$1"
  if [[ -e "$file_path" ]]; then
    return 0
  fi
  ensure_dir "$(dirname "$file_path")"
  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN touch %s\n' "$file_path"
    return 0
  fi
  : > "$file_path"
}

resolve_abs_path() {
  local path="$1"
  (
    cd "$path" >/dev/null 2>&1
    pwd
  )
}

read_target_env_key() {
  local file_path="$1"
  local key="$2"
  codex_read_key_from_env_file "$file_path" "$key" || true
}

read_manifest_key() {
  local key="$1"
  local manifest_path="${target_repo}/.flow/tmp/migration_kit_manifest.env"
  [[ -f "$manifest_path" ]] || return 1
  codex_read_key_from_env_file "$manifest_path" "$key"
}

path_has_tracked_changes() {
  local repo="$1"
  shift || true
  git -C "$repo" status --porcelain --untracked-files=no -- "$@" 2>/dev/null | grep -q .
}

tracked_changes_summary() {
  local repo="$1"
  shift || true
  git -C "$repo" status --porcelain --untracked-files=no -- "$@" 2>/dev/null || true
}

require_clean_paths_for_write() {
  local reason="$1"
  shift || true
  if [[ "$allow_dirty_tracked" == "1" ]]; then
    return 0
  fi
  if ! path_has_tracked_changes "$target_repo" "$@"; then
    return 0
  fi
  echo "BOOTSTRAP_BLOCKED_DIRTY=${reason}" >&2
  tracked_changes_summary "$target_repo" "$@" >&2
  echo "Use --allow-dirty-tracked if overwrite/repair is intentional." >&2
  exit 1
}

resolve_default_shared_url() {
  local shared_repo_dir
  shared_repo_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"
  git -C "$shared_repo_dir" config --get remote.origin.url 2>/dev/null || true
}

resolve_default_shared_branch() {
  local shared_repo_dir branch=""
  shared_repo_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"
  branch="$(git -C "$shared_repo_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${branch#origin/}"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    branch="main"
  fi
  printf '%s' "$branch"
}

resolve_default_shared_revision() {
  local shared_repo_dir
  shared_repo_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"
  git -C "$shared_repo_dir" rev-parse HEAD 2>/dev/null || true
}

backup_existing_path() {
  local source_path="$1"
  local backup_label="$2"
  local backup_dir backup_path timestamp
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  backup_dir="${target_repo}/.flow/tmp/bootstrap/backups"
  backup_path="${backup_dir}/${backup_label}-${timestamp}"
  ensure_dir "$backup_dir"
  run_cmd mv "$source_path" "$backup_path"
  echo "BOOTSTRAP_BACKUP=${backup_path}"
}

detect_existing_profile() {
  local env_profile sample_profile manifest_profile

  env_profile="$(read_target_env_key "${target_repo}/.flow/config/flow.env" "PROJECT_PROFILE")"
  if [[ -n "$env_profile" ]]; then
    printf '%s|flow.env' "$env_profile"
    return 0
  fi

  sample_profile="$(read_target_env_key "${target_repo}/.flow/config/flow.sample.env" "PROJECT_PROFILE")"
  if [[ -n "$sample_profile" ]]; then
    printf '%s|flow.sample.env' "$sample_profile"
    return 0
  fi

  manifest_profile="$(read_manifest_key "MIGRATION_KIT_PROJECT" || true)"
  if [[ -n "$manifest_profile" ]]; then
    printf '%s|migration_kit_manifest' "$manifest_profile"
    return 0
  fi

  return 1
}

resolve_target_profile() {
  local detected existing_profile source
  detected="$(detect_existing_profile || true)"
  if [[ -n "$detected" ]]; then
    existing_profile="${detected%%|*}"
    source="${detected#*|}"
    if [[ -n "$profile" && "$(slugify "$profile")" != "$(slugify "$existing_profile")" ]]; then
      echo "BOOTSTRAP_BLOCKED_PROFILE_MISMATCH=${profile}:${existing_profile}:${source}" >&2
      exit 1
    fi
    profile="$(slugify "$existing_profile")"
    echo "BOOTSTRAP_PROFILE_SOURCE=${source}"
    return 0
  fi

  if [[ -z "$profile" ]]; then
    profile="$(basename "$target_repo")"
    echo "BOOTSTRAP_PROFILE_SOURCE=repo_basename"
  else
    echo "BOOTSTRAP_PROFILE_SOURCE=cli"
  fi
  profile="$(slugify "$profile")"
}

resolve_bootstrap_source() {
  if [[ "$bootstrap_source" != "auto" ]]; then
    return 0
  fi
  if [[ -f "${target_repo}/.flow/tmp/migration_kit_manifest.env" ]]; then
    bootstrap_source="migration_kit"
  else
    bootstrap_source="submodule"
  fi
}

resolve_shared_settings() {
  local manifest_url manifest_branch manifest_revision
  manifest_url="$(read_manifest_key "MIGRATION_KIT_SHARED_URL" || true)"
  manifest_branch="$(read_manifest_key "MIGRATION_KIT_SHARED_BRANCH" || true)"
  manifest_revision="$(read_manifest_key "MIGRATION_KIT_SHARED_REVISION" || true)"

  [[ -n "$shared_url" ]] || shared_url="$manifest_url"
  [[ -n "$shared_branch" ]] || shared_branch="$manifest_branch"
  [[ -n "$shared_revision" ]] || shared_revision="$manifest_revision"

  [[ -n "$shared_url" ]] || shared_url="$(resolve_default_shared_url)"
  [[ -n "$shared_branch" ]] || shared_branch="$(resolve_default_shared_branch)"
  [[ -n "$shared_revision" ]] || shared_revision="$(resolve_default_shared_revision)"

  if [[ -z "$shared_url" || -z "$shared_revision" ]]; then
    echo "Could not determine shared toolkit URL/revision. Pass --shared-url/--shared-revision explicitly." >&2
    exit 1
  fi
  if [[ -z "$shared_branch" ]]; then
    shared_branch="main"
  fi
}

shared_is_git_submodule() {
  [[ "$(git -C "$target_repo" ls-files --stage -- .flow/shared 2>/dev/null | awk 'NR == 1 { print $1 }')" == "160000" ]]
}

git_cmd_for_url() {
  local repo="$1"
  shift || true
  if [[ "$shared_url" == /* || "$shared_url" == file://* ]]; then
    git -C "$repo" -c protocol.file.allow=always "$@"
    return 0
  fi
  git -C "$repo" "$@"
}

submodule_action="reused"
submodule_revision_action="reused"

prepare_shared_snapshot_repair() {
  local shared_path="${target_repo}/.flow/shared"
  if [[ ! -e "$shared_path" ]]; then
    return 0
  fi
  if shared_is_git_submodule; then
    return 0
  fi
  require_clean_paths_for_write "shared-snapshot-repair" .flow/shared
  backup_existing_path "$shared_path" "shared-pre-submodule"
  submodule_action="repaired"
}

sync_submodule_config() {
  local current_url current_branch
  current_url="$(git -C "$target_repo" config --file .gitmodules --get submodule..flow/shared.url 2>/dev/null || true)"
  current_branch="$(git -C "$target_repo" config --file .gitmodules --get submodule..flow/shared.branch 2>/dev/null || true)"
  if [[ "$current_url" != "$shared_url" || "$current_branch" != "$shared_branch" ]]; then
    require_clean_paths_for_write "submodule-config" .gitmodules
    run_cmd git -C "$target_repo" config -f .gitmodules submodule..flow/shared.path .flow/shared
    run_cmd git -C "$target_repo" config -f .gitmodules submodule..flow/shared.url "$shared_url"
    run_cmd git -C "$target_repo" config -f .gitmodules submodule..flow/shared.branch "$shared_branch"
    run_cmd git -C "$target_repo" submodule sync -- .flow/shared
    if [[ "$submodule_action" == "reused" ]]; then
      submodule_action="updated"
    fi
  fi
}

ensure_shared_submodule_present() {
  local add_args=()
  ensure_dir "${target_repo}/.flow"
  if ! shared_is_git_submodule; then
    prepare_shared_snapshot_repair
    require_clean_paths_for_write "submodule-add" .gitmodules
    add_args=(submodule add --force)
    if [[ -n "$shared_branch" ]]; then
      add_args+=(-b "$shared_branch")
    fi
    add_args+=("$shared_url" .flow/shared)
    if [[ "$dry_run" == "1" ]]; then
      printf 'DRY_RUN '
      print_quoted_cmd git -C "$target_repo" "${add_args[@]}"
    else
      git_cmd_for_url "$target_repo" "${add_args[@]}"
    fi
    if [[ "$submodule_action" == "reused" ]]; then
      submodule_action="created"
    fi
  else
    sync_submodule_config
  fi

  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN '
    print_quoted_cmd git -C "$target_repo" submodule update --init --checkout .flow/shared
  else
    git_cmd_for_url "$target_repo" submodule update --init --checkout .flow/shared
  fi
}

ensure_shared_revision() {
  local shared_path current_revision
  shared_path="${target_repo}/.flow/shared"
  if [[ ! -d "$shared_path" ]]; then
    return 0
  fi
  current_revision="$(git -C "$shared_path" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$current_revision" == "$shared_revision" ]]; then
    return 0
  fi

  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN '
    print_quoted_cmd git -C "$shared_path" fetch origin "$shared_revision"
    printf 'DRY_RUN '
    print_quoted_cmd git -C "$shared_path" checkout --detach "$shared_revision"
    submodule_revision_action="updated"
    return 0
  fi

  if ! git -C "$shared_path" cat-file -e "${shared_revision}^{commit}" 2>/dev/null; then
    if [[ "$shared_url" == /* || "$shared_url" == file://* ]]; then
      git -C "$shared_path" -c protocol.file.allow=always fetch origin "$shared_revision" >/dev/null 2>&1 || \
        git -C "$shared_path" -c protocol.file.allow=always fetch origin >/dev/null 2>&1
    else
      git -C "$shared_path" fetch origin "$shared_revision" >/dev/null 2>&1 || \
        git -C "$shared_path" fetch origin >/dev/null 2>&1
    fi
  fi

  git -C "$shared_path" checkout --detach "$shared_revision" >/dev/null 2>&1
  submodule_revision_action="updated"
}

prepare_repo_layout() {
  ensure_dir "${target_repo}/.flow"
  ensure_dir "${target_repo}/.flow/config"
  ensure_dir "${target_repo}/.flow/config/profiles"
  ensure_dir "${target_repo}/.flow/config/root"
  ensure_dir "${target_repo}/.flow/tmp"
  ensure_dir "${target_repo}/.flow/tmp/wizard"
  ensure_dir "${target_repo}/.flow/tmp/bootstrap"
  ensure_file "${target_repo}/.flow/config/profiles/.gitkeep"
  ensure_file "${target_repo}/.flow/config/root/github-actions.required-files.txt"
  ensure_file "${target_repo}/.flow/config/root/github-actions.required-secrets.txt"
}

unpack_migration_kit() {
  if [[ -z "$migration_kit" ]]; then
    return 0
  fi
  [[ -f "$migration_kit" ]] || {
    echo "Migration kit archive not found: ${migration_kit}" >&2
    exit 1
  }
  require_clean_paths_for_write "migration-kit-unpack" .flow .github/workflows .github/pull_request_template.md
  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN '
    print_quoted_cmd tar -xzf "$migration_kit" -C "$target_repo"
    return 0
  fi
  tar -xzf "$migration_kit" -C "$target_repo"
}

overlay_missing_from_manifest() {
  local manifest_path overlay_rel_path
  manifest_path="${target_repo}/.flow/config/root/github-actions.required-files.txt"
  [[ -f "$manifest_path" ]] || return 1
  while IFS= read -r overlay_rel_path || [[ -n "$overlay_rel_path" ]]; do
    [[ -n "$overlay_rel_path" ]] || continue
    [[ -e "${target_repo}/${overlay_rel_path}" ]] || return 0
  done < "$manifest_path"
  return 1
}

target_apply_migration_kit() {
  local apply_cmd
  apply_cmd=("${target_repo}/.flow/shared/scripts/apply_migration_kit.sh" --project "$profile")
  if [[ "$force" == "1" ]]; then
    apply_cmd+=(--force)
  fi
  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN ROOT_DIR=%s ' "$target_repo"
    print_quoted_cmd "${apply_cmd[@]}"
    return 0
  fi
  ROOT_DIR="$target_repo" "${apply_cmd[@]}"
}

target_profile_init() {
  local init_cmd
  init_cmd=("${target_repo}/.flow/shared/scripts/profile_init.sh" init --profile "$profile")
  if [[ "$dry_run" == "1" ]]; then
    printf 'DRY_RUN ROOT_DIR=%s ' "$target_repo"
    print_quoted_cmd "${init_cmd[@]}"
    return 0
  fi
  ROOT_DIR="$target_repo" "${init_cmd[@]}"
}

run_materialization() {
  local apply_needed="0"

  if [[ "$bootstrap_source" == "migration_kit" ]]; then
    if [[ ! -f "${target_repo}/.flow/tmp/migration_kit_manifest.env" ]]; then
      echo "BOOTSTRAP_BLOCKED_MISSING_MIGRATION_MANIFEST=1" >&2
      exit 1
    fi
    if [[ "$force" == "1" || ! -f "${target_repo}/.flow/config/flow.env" || ! -f "${target_repo}/.flow/config/flow.sample.env" ]]; then
      apply_needed="1"
    elif overlay_missing_from_manifest; then
      apply_needed="1"
    fi
  fi

  if [[ "$apply_needed" == "1" ]]; then
    echo "MIGRATION_KIT_ACTION=applied"
    target_apply_migration_kit
  else
    echo "MIGRATION_KIT_ACTION=skipped"
  fi

  echo "PROFILE_INIT_ACTION=init"
  target_profile_init
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-repo)
      [[ $# -ge 2 ]] || { echo "Missing value for --target-repo" >&2; exit 1; }
      target_repo="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "Missing value for --profile" >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    --migration-kit)
      [[ $# -ge 2 ]] || { echo "Missing value for --migration-kit" >&2; exit 1; }
      migration_kit="$2"
      shift 2
      ;;
    --bootstrap-source)
      [[ $# -ge 2 ]] || { echo "Missing value for --bootstrap-source" >&2; exit 1; }
      bootstrap_source="$2"
      shift 2
      ;;
    --shared-url)
      [[ $# -ge 2 ]] || { echo "Missing value for --shared-url" >&2; exit 1; }
      shared_url="$2"
      shift 2
      ;;
    --shared-branch)
      [[ $# -ge 2 ]] || { echo "Missing value for --shared-branch" >&2; exit 1; }
      shared_branch="$2"
      shift 2
      ;;
    --shared-revision)
      [[ $# -ge 2 ]] || { echo "Missing value for --shared-revision" >&2; exit 1; }
      shared_revision="$2"
      shift 2
      ;;
    --force)
      force="1"
      shift
      ;;
    --allow-dirty-tracked)
      allow_dirty_tracked="1"
      shift
      ;;
    --dry-run)
      dry_run="1"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$target_repo" ]]; then
  echo "Option --target-repo is required" >&2
  usage
  exit 1
fi

target_repo="$(resolve_abs_path "$target_repo")"
[[ -n "$target_repo" ]] || {
  echo "Could not resolve target repo path." >&2
  exit 1
}
[[ -d "${target_repo}/.git" ]] || {
  echo "Target repo is not a git repository: ${target_repo}" >&2
  exit 1
}

case "$bootstrap_source" in
  auto|submodule|migration_kit) ;;
  *)
    echo "Unsupported --bootstrap-source: ${bootstrap_source}" >&2
    exit 1
    ;;
esac

prepare_repo_layout
unpack_migration_kit
resolve_bootstrap_source
resolve_target_profile
resolve_shared_settings
ensure_shared_submodule_present
ensure_shared_revision
prepare_repo_layout
run_materialization

echo "BOOTSTRAP_TARGET_REPO=${target_repo}"
echo "BOOTSTRAP_PROFILE=${profile}"
echo "BOOTSTRAP_SOURCE=${bootstrap_source}"
echo "BOOTSTRAP_FLOW_DIR=${target_repo}/.flow"
echo "BOOTSTRAP_FLOW_SHARED_DIR=${target_repo}/.flow/shared"
echo "BOOTSTRAP_FLOW_ENV=${target_repo}/.flow/config/flow.env"
echo "BOOTSTRAP_FLOW_SAMPLE_ENV=${target_repo}/.flow/config/flow.sample.env"
echo "BOOTSTRAP_FLOW_STATE=${target_repo}/.flow/state"
echo "BOOTSTRAP_FLOW_LOGS=${target_repo}/.flow/logs"
echo "BOOTSTRAP_FLOW_LAUNCHD=${target_repo}/.flow/launchd"
echo "BOOTSTRAP_WIZARD_STATE_DIR=${target_repo}/.flow/tmp/wizard"
echo "SHARED_SUBMODULE_URL=${shared_url}"
echo "SHARED_SUBMODULE_BRANCH=${shared_branch}"
echo "SHARED_SUBMODULE_REVISION=${shared_revision}"
echo "SHARED_SUBMODULE_ACTION=${submodule_action}"
echo "SHARED_SUBMODULE_REVISION_ACTION=${submodule_revision_action}"
