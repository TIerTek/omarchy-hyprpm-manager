#!/usr/bin/env bash
# Fixture-driven tests for bin/hyprpm-status.
#
# The collector takes every external dependency from an environment variable so
# these tests never touch the real hyprpm state store or the running compositor.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
COLLECTOR="$HERE/../bin/hyprpm-status"
pass=0 fail=0

for dir in "$HERE"/fixtures/*/; do
  name=$(basename "$dir")
  [[ -f "$dir/expect" ]] || continue
  # shellcheck disable=SC1091
  source "$dir/expect"   # sets want_state, want_codes, and optionally dep_list

  out=$(
    HYPRPM_MGR_HYPRCTL="$dir/hyprctl" \
    HYPRPM_MGR_STATE_DIR="$dir/state" \
    HYPRPM_MGR_DEP_LIST="${dep_list:-git}" \
    "$COLLECTOR" 2>/dev/null
  )
  rc=$?

  got_state=$(printf '%s' "$out" | jq -r '.state' 2>/dev/null)
  got_codes=$(printf '%s' "$out" | jq -r '[.problems[].code] | sort | join(",")' 2>/dev/null)

  errs=()
  [[ $rc -eq 0 ]]                  || errs+=("exit $rc, want 0")
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || errs+=("stdout is not valid JSON")
  [[ $got_state == "$want_state" ]] || errs+=("state=$got_state want=$want_state")
  [[ $got_codes == "$want_codes" ]] || errs+=("codes=[$got_codes] want=[$want_codes]")

  if [[ ${#errs[@]} -eq 0 ]]; then
    printf '  ok   %s\n' "$name"; pass=$((pass+1))
  else
    printf '  FAIL %s\n' "$name"; printf '         %s\n' "${errs[@]}"; fail=$((fail+1))
  fi
  unset want_state want_codes dep_list
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
