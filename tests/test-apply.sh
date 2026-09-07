#!/usr/bin/env bash
# Tests for bin/hyprpm-apply — the helper the panel runs in a visible terminal
# to enable or disable a plugin. hyprpm itself is stubbed; these tests never
# elevate and never touch the real state store.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APPLY="$HERE/../bin/hyprpm-apply"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0

# Stub records each invocation, one per line, and can be told to fail.
cat > "$TMP/hyprpm" <<'STUB'
#!/bin/sh
echo "$*" >> "$HYPRPM_STUB_LOG"
[ -n "${HYPRPM_STUB_FAIL:-}" ] && [ "$1" = "$HYPRPM_STUB_FAIL" ] && exit 7
exit 0
STUB
chmod +x "$TMP/hyprpm"

check() {
  local name="$1" want_rc="$2" want_log="$3"; shift 3
  : > "$TMP/log"
  HYPRPM_STUB_LOG="$TMP/log" HYPRPM_MGR_HYPRPM="$TMP/hyprpm" "$APPLY" "$@" >/dev/null 2>&1
  local rc=$? got; got=$(paste -sd'|' "$TMP/log" 2>/dev/null)
  local errs=()
  [[ $rc -eq $want_rc ]]     || errs+=("exit $rc want $want_rc")
  [[ $got == "$want_log" ]]  || errs+=("calls [$got] want [$want_log]")
  if [[ ${#errs[@]} -eq 0 ]]; then printf '  ok   %s\n' "$name"; pass=$((pass+1))
  else printf '  FAIL %s\n' "$name"; printf '         %s\n' "${errs[@]}"; fail=$((fail+1)); fi
}

check "no arguments"          2 ""
check "bad action"            2 ""                       frobnicate hyprexpo
check "missing plugin name"   2 ""                       enable
check "enable then reload"    0 "enable hyprexpo|reload" enable hyprexpo
check "disable then reload"   0 "disable hyprbars|reload" disable hyprbars

# A failing enable must NOT go on to reload.
: > "$TMP/log"
HYPRPM_STUB_LOG="$TMP/log" HYPRPM_STUB_FAIL=enable HYPRPM_MGR_HYPRPM="$TMP/hyprpm" \
  "$APPLY" enable hyprexpo >/dev/null 2>&1
rc=$?; got=$(paste -sd'|' "$TMP/log")
if [[ $rc -ne 0 && $got == "enable hyprexpo" ]]; then
  printf '  ok   failed enable does not reload\n'; pass=$((pass+1))
else
  printf '  FAIL failed enable does not reload (exit %s, calls [%s])\n' "$rc" "$got"; fail=$((fail+1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
