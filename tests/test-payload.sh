#!/usr/bin/env bash
# Offline unit checks for payload construction helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/multica-quick-add.sh
source "$ROOT/lib/multica-quick-add.sh"

fail=0
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" != "$want" ]]; then
    printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$name" "$got" "$want"
    fail=1
  else
    printf 'ok   %s\n' "$name"
  fi
}

# Payload with agent + project
payload="$(
  jq -n \
    --arg prompt "fix the thing" \
    --arg kind "agent" \
    --arg id "agent-1" \
    --arg project_id "proj-1" \
    --argjson attachment_ids '["att-1"]' \
    '
      {
        prompt: $prompt
      }
      + (if $kind == "squad" then {squad_id: $id} else {agent_id: $id} end)
      + (if $project_id != "" then {project_id: $project_id} else {} end)
      + (if ($attachment_ids | length) > 0 then {attachment_ids: $attachment_ids} else {} end)
    '
)"
assert_eq "agent_id present" "$(jq -r .agent_id <<<"$payload")" "agent-1"
assert_eq "no squad_id" "$(jq -r 'has("squad_id")' <<<"$payload")" "false"
assert_eq "project_id" "$(jq -r .project_id <<<"$payload")" "proj-1"
assert_eq "attachment" "$(jq -r .attachment_ids[0] <<<"$payload")" "att-1"

payload2="$(
  jq -n \
    --arg prompt "hi" \
    --arg kind "squad" \
    --arg id "squad-9" \
    --arg project_id "" \
    --argjson attachment_ids '[]' \
    '
      {
        prompt: $prompt
      }
      + (if $kind == "squad" then {squad_id: $id} else {agent_id: $id} end)
      + (if $project_id != "" then {project_id: $project_id} else {} end)
      + (if ($attachment_ids | length) > 0 then {attachment_ids: $attachment_ids} else {} end)
    '
)"
assert_eq "squad_id present" "$(jq -r .squad_id <<<"$payload2")" "squad-9"
assert_eq "no agent_id" "$(jq -r 'has("agent_id")' <<<"$payload2")" "false"
assert_eq "no project" "$(jq -r 'has("project_id")' <<<"$payload2")" "false"

# Catalog line helpers
catalog='{"agents":[{"id":"a1","name":"Alpha"}],"squads":[{"id":"s1","name":"Ship"}],"projects":[{"id":"p1","title":"Inbox"}]}'
lines="$(printf '%s' "$catalog" | mqa_created_by_lines | tr '\n' '|')"
assert_eq "created-by lines" "$lines" "🤖 Alpha	agent	a1|👥 Ship	squad	s1|"

proj="$(printf '%s' "$catalog" | mqa_project_lines)"
assert_eq "project line" "$proj" "Inbox	p1"

# normalize "no project" selections
assert_eq "none sentinel" "$(mqa_normalize_project_id '__none__')" ""
assert_eq "none label" "$(mqa_normalize_project_id '— No project')" ""
assert_eq "empty" "$(mqa_normalize_project_id '')" ""
uuid="01234567-89ab-cdef-0123-456789abcdef"
assert_eq "uuid kept" "$(mqa_normalize_project_id "$uuid")" "$uuid"
assert_eq "garbage dropped" "$(mqa_normalize_project_id 'Inbox')" ""

# payload omits project_id when empty after normalize
payload3="$(
  pid="$(mqa_normalize_project_id '__none__')"
  jq -n \
    --arg prompt "hi" \
    --arg kind "agent" \
    --arg id "agent-1" \
    --arg project_id "$pid" \
    '
      {prompt:$prompt}
      + (if $kind == "squad" then {squad_id:$id} else {agent_id:$id} end)
      + (if $project_id != "" then {project_id:$project_id} else {} end)
    '
)"
assert_eq "no project key" "$(jq -r 'has("project_id")' <<<"$payload3")" "false"

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
printf 'all tests passed\n'
