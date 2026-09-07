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

# Stub sudo. "-n true" reports whether a credential is cached; SUDO_STUB_CACHED
# controls that, and SUDO_STUB_VFAIL makes the interactive "-v" refuse.
cat > "$TMP/sudo" <<'STUB'
#!/bin/sh
echo "sudo $*" >> "$HYPRPM_STUB_LOG"
case "$1" in
  -n) [ -n "${SUDO_STUB_CACHED:-}" ] && exit 0 || exit 1 ;;
  -v) [ -n "${SUDO_STUB_VFAIL:-}" ] && exit 1 || exit 0 ;;
esac
exit 0
STUB
chmod +x "$TMP/sudo"

check() {
  local name="$1" want_rc="$2" want_log="$3"; shift 3
  : > "$TMP/log"
  HYPRPM_STUB_LOG="$TMP/log" HYPRPM_MGR_HYPRPM="$TMP/hyprpm" HYPRPM_MGR_SUDO="$TMP/sudo" \
    SUDO_STUB_CACHED=1 "$APPLY" "$@" >/dev/null 2>&1
  local rc=$? got; got=$(paste -sd'|' "$TMP/log" 2>/dev/null)
  local errs=()
  [[ $rc -eq $want_rc ]]     || errs+=("exit $rc want $want_rc")
  [[ $got == "$want_log" ]]  || errs+=("calls [$got] want [$want_log]")
  if [[ ${#errs[@]} -eq 0 ]]; then printf '  ok   %s\n' "$name"; pass=$((pass+1))
  else printf '  FAIL %s\n' "$name"; printf '         %s\n' "${errs[@]}"; fail=$((fail+1)); fi
}

# With a cached credential the preflight makes one "sudo -n" probe and no more.
check "no arguments"          2 ""
check "bad action"            2 ""                       frobnicate hyprexpo
check "missing plugin name"   2 ""                       enable
check "enable then reload"    0 "sudo -n true|enable hyprexpo|reload" enable hyprexpo
check "disable then reload"   0 "sudo -n true|disable hyprbars|reload" disable hyprbars

# A failing enable must NOT go on to reload.
: > "$TMP/log"
HYPRPM_STUB_LOG="$TMP/log" HYPRPM_STUB_FAIL=enable HYPRPM_MGR_HYPRPM="$TMP/hyprpm" \
  HYPRPM_MGR_SUDO="$TMP/sudo" SUDO_STUB_CACHED=1 "$APPLY" enable hyprexpo >/dev/null 2>&1
rc=$?; got=$(paste -sd'|' "$TMP/log")
if [[ $rc -ne 0 && $got == "sudo -n true|enable hyprexpo" ]]; then
  printf '  ok   failed enable does not reload\n'; pass=$((pass+1))
else
  printf '  FAIL failed enable does not reload (exit %s, calls [%s])\n' "$rc" "$got"; fail=$((fail+1))
fi

# Uncached credential: prompt once via "sudo -v". If that is refused, hyprpm
# must never run - otherwise it retries sudo four times and burns four
# pam_faillock attempts per click, which is what locked the account for real.
: > "$TMP/log"
HYPRPM_STUB_LOG="$TMP/log" HYPRPM_MGR_HYPRPM="$TMP/hyprpm" HYPRPM_MGR_SUDO="$TMP/sudo" \
  SUDO_STUB_VFAIL=1 "$APPLY" enable hyprexpo >/dev/null 2>&1
rc=$?; got=$(paste -sd'|' "$TMP/log")
if [[ $rc -eq 1 && $got == "sudo -n true|sudo -v" ]]; then
  printf '  ok   refused auth never reaches hyprpm\n'; pass=$((pass+1))
else
  printf '  FAIL refused auth never reaches hyprpm (exit %s, calls [%s])\n' "$rc" "$got"; fail=$((fail+1))
fi

# Uncached but accepted: prompt, then proceed.
: > "$TMP/log"
HYPRPM_STUB_LOG="$TMP/log" HYPRPM_MGR_HYPRPM="$TMP/hyprpm" HYPRPM_MGR_SUDO="$TMP/sudo" \
  "$APPLY" enable hyprexpo >/dev/null 2>&1
rc=$?; got=$(paste -sd'|' "$TMP/log")
if [[ $rc -eq 0 && $got == "sudo -n true|sudo -v|enable hyprexpo|reload" ]]; then
  printf '  ok   uncached auth prompts once then proceeds\n'; pass=$((pass+1))
else
  printf '  FAIL uncached auth prompts once then proceeds (exit %s, calls [%s])\n' "$rc" "$got"; fail=$((fail+1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
