# Shared helpers for Multica Quick Add (Walker/Elephant).
# shellcheck shell=bash

set -euo pipefail

MQA_ROOT="${MQA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MQA_STATE_DIR="${MQA_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/multica-quick-add}"
MQA_CONFIG_PATH="${MQA_CONFIG_PATH:-$HOME/.multica/config.json}"
MQA_CACHE_DIR="${MQA_CACHE_DIR:-$MQA_STATE_DIR/cache}"

# Ensure Elephant + Walker GApplication service are up, then run walker as a
# *client*. Starting a second full instance races for bus name dev.benz.walker
# ("Failed to register: Unable to acquire bus name").
mqa_ensure_walker_service() {
  if ! pgrep -x elephant >/dev/null 2>&1; then
    if command -v uwsm-app >/dev/null 2>&1; then
      setsid uwsm-app -- elephant >/dev/null 2>&1 &
    else
      setsid elephant >/dev/null 2>&1 &
    fi
  fi
  if ! pgrep -f "walker --gapplication-service" >/dev/null 2>&1; then
    if command -v uwsm-app >/dev/null 2>&1; then
      setsid uwsm-app -- env GSK_RENDERER=cairo walker --gapplication-service >/dev/null 2>&1 &
    else
      setsid env GSK_RENDERER=cairo walker --gapplication-service >/dev/null 2>&1 &
    fi
    # Wait briefly for the bus name to appear.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -f "walker --gapplication-service" >/dev/null 2>&1 && break
      sleep 0.1
    done
  fi
}

mqa_walker() {
  command -v walker >/dev/null 2>&1 || mqa_die "walker is not installed"
  mqa_ensure_walker_service
  # Talk to the existing service; --exit ends this dmenu call cleanly.
  # Do NOT use omarchy-launch-walker here: it re-execs a second app instance
  # that often fails to acquire bus name dev.benz.walker.
  local -a args=("$@")
  local has_dmenu=0 has_exit=0 a
  for a in "${args[@]}"; do
    [[ "$a" == "--dmenu" || "$a" == "-d" ]] && has_dmenu=1
    [[ "$a" == "--exit" || "$a" == "-e" ]] && has_exit=1
  done
  if [[ "$has_dmenu" == "1" && "$has_exit" == "0" ]]; then
    args+=(--exit)
  fi
  walker "${args[@]}"
}

# Terminal fallback when Walker is unavailable (SSH, headless, bus race).
mqa_fzf_pick() {
  local placeholder="$1"
  shift
  if ! command -v fzf >/dev/null 2>&1; then
    return 1
  fi
  printf '%s\n' "$@" | fzf --prompt "$placeholder > " --height=40% --reverse || true
}

mqa_read_prompt_tty() {
  local placeholder="${1:-Describe an issue}"
  local hint="${2:-}"
  local full="$placeholder"
  if [[ -n "$hint" ]]; then
    full="$placeholder  ·  $hint"
  fi
  local text=""
  if [[ -t 0 && -t 1 ]]; then
    printf '%s\n' "$full" >&2
    # shellcheck disable=SC2162
    IFS= read -r text || true
  fi
  text="$(printf '%s' "$text" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -n "$text" ]] || return 1
  printf '%s' "$text"
}

mqa_notify() {
  local title="$1"
  local body="${2:-}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send --app-name="Multica Quick Add" "$title" "$body" || true
  else
    printf '%s: %s\n' "$title" "$body" >&2
  fi
}

mqa_die() {
  mqa_notify "Quick add failed" "$*"
  printf 'error: %s\n' "$*" >&2
  return 1
}

mqa_require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || mqa_die "Missing required command: $cmd"
  done
}

mqa_ensure_dirs() {
  mkdir -p "$MQA_STATE_DIR" "$MQA_CACHE_DIR"
}

mqa_load_config() {
  # Exports: MQA_SERVER_URL, MQA_TOKEN, MQA_WORKSPACE_ID (optional default)
  # Returns 0 on success, 1 if missing/invalid (no notify when used as soft check).
  if [[ ! -f "$MQA_CONFIG_PATH" ]]; then
    return 1
  fi

  local parsed
  parsed="$(
    jq -r '
      [
        (.server_url // .serverURL // ""),
        (.token // .access_token // .accessToken // ""),
        (.workspace_id // .workspaceID // "")
      ] | @tsv
    ' "$MQA_CONFIG_PATH" 2>/dev/null
  )" || return 1

  IFS=$'\t' read -r MQA_SERVER_URL MQA_TOKEN MQA_DEFAULT_WORKSPACE_ID <<<"$parsed"
  export MQA_SERVER_URL MQA_TOKEN MQA_DEFAULT_WORKSPACE_ID

  if [[ -z "${MQA_SERVER_URL:-}" || -z "${MQA_TOKEN:-}" ]]; then
    return 1
  fi

  # Strip trailing slash
  MQA_SERVER_URL="${MQA_SERVER_URL%/}"
  export MQA_SERVER_URL
  return 0
}

mqa_state_get() {
  local key="$1"
  local file="$MQA_STATE_DIR/selections.json"
  [[ -f "$file" ]] || {
    printf ''
    return 0
  }
  jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null || true
}

mqa_state_set() {
  local key="$1"
  local value="$2"
  local file="$MQA_STATE_DIR/selections.json"
  mqa_ensure_dirs
  if [[ ! -f "$file" ]]; then
    printf '{}\n' >"$file"
  fi
  local tmp
  tmp="$(mktemp)"
  jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$file" >"$tmp"
  mv "$tmp" "$file"
}

mqa_state_set_json() {
  local key="$1"
  local json="$2"
  local file="$MQA_STATE_DIR/selections.json"
  mqa_ensure_dirs
  if [[ ! -f "$file" ]]; then
    printf '{}\n' >"$file"
  fi
  local tmp
  tmp="$(mktemp)"
  jq --arg k "$key" --argjson v "$json" '.[$k] = $v' "$file" >"$tmp"
  mv "$tmp" "$file"
}

mqa_cli_json() {
  # Run multica and return stdout JSON. Extra args after resource.
  # Usage: mqa_cli_json workspace list
  #        mqa_cli_json agent list --workspace-id UUID
  local -a args=("$@")
  local out err
  out="$(mktemp)"
  err="$(mktemp)"
  if ! multica "${args[@]}" --output json >"$out" 2>"$err"; then
    local message
    message="$(tr -d '\r' <"$err" | tail -n 5 | tr '\n' ' ')"
    rm -f "$out" "$err"
    mqa_die "multica ${args[*]} failed: ${message:-unknown error}"
  fi
  cat "$out"
  rm -f "$out" "$err"
}

mqa_list_workspaces() {
  mqa_cli_json workspace list
}

mqa_list_projects() {
  local workspace_id="$1"
  mqa_cli_json project list --workspace-id "$workspace_id"
}

mqa_list_agents() {
  local workspace_id="$1"
  mqa_cli_json agent list --workspace-id "$workspace_id"
}

mqa_list_squads() {
  local workspace_id="$1"
  mqa_cli_json squad list --workspace-id "$workspace_id"
}

mqa_cache_catalog() {
  local workspace_id="$1"
  local file="$MQA_CACHE_DIR/catalog.$workspace_id.json"
  local projects agents squads
  projects="$(mqa_list_projects "$workspace_id")"
  agents="$(mqa_list_agents "$workspace_id")"
  squads="$(mqa_list_squads "$workspace_id" 2>/dev/null || printf '[]\n')"
  jq -n \
    --argjson projects "$projects" \
    --argjson agents "$agents" \
    --argjson squads "$squads" \
    '{projects:$projects, agents:$agents, squads:$squads}' >"$file"
  cat "$file"
}

mqa_get_catalog() {
  local workspace_id="$1"
  local refresh="${2:-0}"
  local file="$MQA_CACHE_DIR/catalog.$workspace_id.json"
  if [[ "$refresh" == "1" || ! -f "$file" ]]; then
    mqa_cache_catalog "$workspace_id"
  else
    cat "$file"
  fi
}

# Pickers: one line per option "label\tid" or freeform.
# Prefers Walker dmenu; falls back to fzf on TTY if Walker fails/cancels with no selection.
# Prints the selected raw line (or empty if cancelled).
mqa_pick_line() {
  local placeholder="$1"
  shift
  local selection=""
  if [[ "$#" -eq 0 ]]; then
    return 1
  fi
  if command -v walker >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
    selection="$(
      printf '%s\n' "$@" | mqa_walker \
        --dmenu \
        --placeholder "$placeholder" \
        --width 640 \
        --minheight 200 \
        --maxheight 360 || true
    )"
  fi
  if [[ -z "${selection// }" ]]; then
    selection="$(mqa_fzf_pick "$placeholder" "$@")"
  fi
  [[ -n "${selection// }" ]] || return 1
  printf '%s\n' "$selection"
}

# True when a Multica project id is usable (UUID). Empty / "none" / labels are not.
mqa_is_project_id() {
  local id="${1:-}"
  [[ "$id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

mqa_normalize_project_id() {
  # Clear "no project" sentinels and non-UUID garbage (Walker often returns only the label).
  local id="${1:-}"
  id="${id#"${id%%[![:space:]]*}"}"
  id="${id%"${id##*[![:space:]]}"}"
  case "$id" in
    "" | __none__ | none | "— No project" | "No project" | "- No project")
      printf ''
      return 0
      ;;
  esac
  if mqa_is_project_id "$id"; then
    printf '%s' "$id"
  else
    # Unknown non-UUID (e.g. label-only pick) → treat as no project.
    printf ''
  fi
}

mqa_pick_id_from_labeled() {
  # Input lines: "Pretty label"$'\t'"id"
  # Walker/fzf may return the full line or only the visible label.
  local placeholder="$1"
  shift
  local line id
  line="$(mqa_pick_line "$placeholder" "$@")" || return 1
  if [[ "$line" == *$'\t'* ]]; then
    id="${line##*$'\t'}"
  else
    # Label-only: match against provided lines to recover the id column.
    id=""
    local candidate label cand_id
    for candidate in "$@"; do
      label="${candidate%%$'\t'*}"
      cand_id="${candidate#*$'\t'}"
      if [[ "$line" == "$label" || "$line" == "$candidate" ]]; then
        id="$cand_id"
        break
      fi
    done
    # Last resort: whole line (may be a raw id typed/pasted).
    [[ -n "$id" ]] || id="$line"
  fi
  printf '%s\n' "$id"
}

mqa_prompt_text() {
  local placeholder="${1:-Describe an issue}"
  local hint="${2:-}"
  local full="$placeholder"
  if [[ -n "$hint" ]]; then
    full="$placeholder  ·  $hint"
  fi
  local text=""
  if command -v walker >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
    # Free-text capture: input-only dmenu (Spotlight-style single field).
    text="$(
      mqa_walker \
        --dmenu \
        --inputonly \
        --placeholder "$full" \
        --width 720 \
        --minheight 80 \
        --maxheight 120 \
        </dev/null || true
    )"
  fi
  text="$(printf '%s' "$text" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [[ -z "$text" ]]; then
    text="$(mqa_read_prompt_tty "$placeholder" "$hint" || true)"
  fi
  [[ -n "$text" ]] || return 1
  printf '%s' "$text"
}

mqa_upload_attachment() {
  local workspace_id="$1"
  local file_path="$2"
  local filename
  filename="$(basename "$file_path")"
  curl -fsS \
    -X POST \
    -H "Authorization: Bearer $MQA_TOKEN" \
    -F "file=@${file_path};filename=${filename}" \
    "${MQA_SERVER_URL}/api/upload-file?workspace_id=${workspace_id}" \
    | jq -r '.id // empty'
}

mqa_quick_create() {
  # Args via env / named locals set by caller:
  # workspace_id, prompt, created_by_kind (agent|squad), created_by_id, project_id (optional)
  # attachment_ids: bash array
  local workspace_id="$1"
  local prompt="$2"
  local created_by_kind="$3"
  local created_by_id="$4"
  local project_id="${5:-}"
  shift 5 || true
  local -a attachment_ids=("$@")

  # Never send labels / empty / __none__ as project_id (API: invalid project_id).
  project_id="$(mqa_normalize_project_id "$project_id")"

  local attachment_json="[]"
  if ((${#attachment_ids[@]} > 0)); then
    attachment_json="$(printf '%s\n' "${attachment_ids[@]}" | jq -R . | jq -s 'map(select(length>0))')"
  fi

  local payload
  payload="$(
    jq -n \
      --arg prompt "$prompt" \
      --arg kind "$created_by_kind" \
      --arg id "$created_by_id" \
      --arg project_id "$project_id" \
      --argjson attachment_ids "$attachment_json" \
      '
        {
          prompt: $prompt
        }
        + (if $kind == "squad" then {squad_id: $id} else {agent_id: $id} end)
        + (if $project_id != "" then {project_id: $project_id} else {} end)
        + (if ($attachment_ids | length) > 0 then {attachment_ids: $attachment_ids} else {} end)
      '
  )"

  local url response http_code body
  url="${MQA_SERVER_URL}/api/issues/quick-create?workspace_id=${workspace_id}"
  response="$(
    curl -sS -w '\n%{http_code}' \
      -X POST \
      -H "Authorization: Bearer $MQA_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$url"
  )" || mqa_die "Network error talking to Multica"

  http_code="$(printf '%s' "$response" | tail -n1)"
  body="$(printf '%s' "$response" | sed '$d')"

  if [[ ! "$http_code" =~ ^2 ]]; then
    local message
    message="$(printf '%s' "$body" | jq -r '.error // .message // empty' 2>/dev/null || true)"
    [[ -n "$message" ]] || message="HTTP $http_code: ${body:0:200}"
    mqa_die "$message"
  fi
}

mqa_created_by_lines() {
  # From catalog JSON on stdin: lines "🤖 Name"$'\t'"agent"$'\t'"id" and squads with 👥
  jq -r '
    ((.agents // [])[] | "🤖 \(.name // .id)\tagent\t\(.id)"),
    ((.squads // [])[] | "👥 \(.name // .id)\tsquad\t\(.id)")
  '
}

mqa_project_lines() {
  jq -r '(.projects // [])[] | "\(.title // .name // .id)\t\(.id)"'
}

mqa_workspace_lines() {
  jq -r '.[] | "\(.name // .id)\t\(.id)"'
}

# --- Selection API (Elephant hub / submenus) ---

mqa_resolve_workspace_id() {
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    id="$(mqa_state_get last_workspace_id)"
  fi
  if [[ -z "$id" && -n "${MQA_DEFAULT_WORKSPACE_ID:-}" ]]; then
    id="$MQA_DEFAULT_WORKSPACE_ID"
  fi
  printf '%s' "$id"
}

mqa_workspace_name() {
  local id="$1"
  mqa_list_workspaces 2>/dev/null | jq -r --arg id "$id" \
    '(.[] | select(.id == $id) | .name) // $id' 2>/dev/null || printf '%s' "$id"
}

mqa_print_selection() {
  local workspace_id project_id kind cb_id cb_name project_title ready catalog
  workspace_id="$(mqa_resolve_workspace_id "")"
  if [[ -z "$workspace_id" ]]; then
    jq -n '{
      ready: false,
      error: "no workspace selected",
      workspace_id: "",
      workspace_name: "",
      project_id: "",
      project_title: "",
      created_by_kind: "",
      created_by_id: "",
      created_by_name: "",
      hint: "Pick a workspace first"
    }'
    return 0
  fi

  project_id="$(mqa_normalize_project_id "$(mqa_state_get "last_project_id.$workspace_id")")"
  kind="$(mqa_state_get "last_created_by_kind.$workspace_id")"
  cb_id="$(mqa_state_get "last_created_by_id.$workspace_id")"
  cb_name="$(mqa_state_get "last_created_by_name.$workspace_id")"

  catalog="$(mqa_get_catalog "$workspace_id" 0 2>/dev/null || printf '{}')"
  project_title=""
  if [[ -n "$project_id" ]]; then
    project_title="$(
      printf '%s' "$catalog" | jq -r --arg id "$project_id" \
        '((.projects // [])[] | select(.id == $id) | .title // .name) // empty' 2>/dev/null || true
    )"
  fi
  if [[ -z "$cb_name" && -n "$cb_id" ]]; then
    cb_name="$(
      printf '%s' "$catalog" | jq -r --arg k "${kind:-agent}" --arg id "$cb_id" '
        if $k == "squad" then
          ((.squads // [])[] | select(.id == $id) | .name) // $id
        else
          ((.agents // [])[] | select(.id == $id) | .name) // $id
        end
      ' 2>/dev/null || printf '%s' "$cb_id"
    )"
  fi

  local ws_name
  ws_name="$(mqa_workspace_name "$workspace_id")"
  ready=false
  [[ -n "$cb_id" && -n "$kind" ]] && ready=true

  local hint="→ ${cb_name:-pick agent}"
  if [[ -n "$project_title" ]]; then
    hint="$hint · $project_title"
  elif [[ -n "$project_id" ]]; then
    hint="$hint · project"
  else
    hint="$hint · no project"
  fi

  jq -n \
    --arg workspace_id "$workspace_id" \
    --arg workspace_name "$ws_name" \
    --arg project_id "$project_id" \
    --arg project_title "${project_title:-}" \
    --arg created_by_kind "${kind:-}" \
    --arg created_by_id "${cb_id:-}" \
    --arg created_by_name "${cb_name:-}" \
    --arg hint "$hint" \
    --argjson ready "$ready" \
    '{
      ready: $ready,
      workspace_id: $workspace_id,
      workspace_name: $workspace_name,
      project_id: $project_id,
      project_title: (if $project_title == "" then (if $project_id == "" then "No project" else $project_id end) else $project_title end),
      created_by_kind: $created_by_kind,
      created_by_id: $created_by_id,
      created_by_name: (if $created_by_name == "" then "Not set" else $created_by_name end),
      hint: $hint
    }'
}

mqa_set_workspace() {
  local id="${1:?workspace id required}"
  mqa_state_set last_workspace_id "$id"
  # Refresh catalog once when workspace changes (not on every menu paint).
  mqa_get_catalog "$id" 1 >/dev/null 2>&1 || true
  touch "$MQA_STATE_DIR/selections.json" 2>/dev/null || true
}

mqa_set_project() {
  local workspace_id project_id
  workspace_id="$(mqa_resolve_workspace_id "${1:-}")"
  [[ -n "$workspace_id" ]] || mqa_die "No workspace selected"
  project_id="$(mqa_normalize_project_id "${2-}")"
  mqa_state_set "last_project_id.$workspace_id" "$project_id"
  touch "$MQA_STATE_DIR/selections.json" 2>/dev/null || true
}

mqa_set_created_by() {
  local kind="${1:?}" id="${2:?}" name="${3:-}"
  local workspace_id
  workspace_id="$(mqa_resolve_workspace_id "")"
  [[ -n "$workspace_id" ]] || mqa_die "No workspace selected"
  if [[ -z "$name" ]]; then
    local catalog
    catalog="$(mqa_get_catalog "$workspace_id" 0 2>/dev/null || printf '{}')"
    name="$(
      printf '%s' "$catalog" | jq -r --arg k "$kind" --arg id "$id" '
        if $k == "squad" then
          ((.squads // [])[] | select(.id == $id) | .name) // $id
        else
          ((.agents // [])[] | select(.id == $id) | .name) // $id
        end
      ' 2>/dev/null || printf '%s' "$id"
    )"
  fi
  mqa_state_set "last_created_by_kind.$workspace_id" "$kind"
  mqa_state_set "last_created_by_id.$workspace_id" "$id"
  mqa_state_set "last_created_by_name.$workspace_id" "$name"
  touch "$MQA_STATE_DIR/selections.json" 2>/dev/null || true
}

mqa_open_hub() {
  mqa_ensure_walker_service
  # Prefer exclusive Multica hub; fall back to elephant menu protocol.
  if command -v walker >/dev/null 2>&1; then
    # Don't --exit; keep normal provider session for browsing hub/submenus.
    walker -m menus:multicaquickadd --width 720 --minheight 280 --maxheight 480 &
  elif command -v elephant >/dev/null 2>&1; then
    elephant menu multicaquickadd &
  else
    mqa_die "walker (or elephant) is required to open the Multica hub"
  fi
}

mqa_reopen_hub() {
  # Bounce back to hub after a submenu selection (best-effort, single shot).
  # Prefer Elephant's menu protocol so we don't spawn stacked Walker clients.
  if command -v elephant >/dev/null 2>&1; then
    elephant menu multicaquickadd >/dev/null 2>&1 || true
    return 0
  fi
  if command -v walker >/dev/null 2>&1; then
    walker --close >/dev/null 2>&1 || true
    sleep 0.05
    walker -m menus:multicaquickadd --width 720 --minheight 280 --maxheight 480 >/dev/null 2>&1 &
  fi
}
