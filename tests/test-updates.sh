#!/usr/bin/env bash
# Tests for bin/hyprpm-updates — the slow, networked half of the plugin.
# git is stubbed; nothing here touches the network or the real state store.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
UPD="$HERE/../bin/hyprpm-updates"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pass=0 fail=0

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n         %s\n' "$1" "$2"; fail=$((fail+1)); }

mkrepo() { # <name> <recorded-hash>
  mkdir -p "$TMP/state/$1"
  printf "[repository]\nname = '%s'\nhash = '%s'\nurl = 'https://example.invalid/%s'\nrev = ''\n" \
    "$1" "$2" "$1" > "$TMP/state/$1/state.toml"
}
cat > "$TMP/git" <<'STUB'
#!/bin/sh
# ls-remote <url> HEAD  ->  "<hash>\tHEAD"
[ -n "${GIT_STUB_FAIL:-}" ] && exit 1
printf '%s\tHEAD\n' "${GIT_STUB_HEAD:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
STUB
chmod +x "$TMP/git"

run() { HYPRPM_MGR_STATE_DIR="$TMP/state" HYPRPM_MGR_GIT="$TMP/git" \
        HYPRPM_MGR_CACHE="$TMP/cache.json" "$UPD" >/dev/null 2>&1; }

# Behind upstream.
mkrepo alpha 1111111111111111111111111111111111111111
run; rc=$?
got=$(jq -r '.repos.alpha.behind' "$TMP/cache.json" 2>/dev/null)
[[ $rc -eq 0 && $got == "true" ]] && ok "repo behind upstream is flagged" \
  || bad "repo behind upstream is flagged" "exit=$rc behind=$got"

# Up to date: recorded hash equals upstream.
rm -f "$TMP/cache.json"; rm -rf "$TMP/state"
mkrepo beta aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
run
got=$(jq -r '.repos.beta.behind' "$TMP/cache.json" 2>/dev/null)
[[ $got == "false" ]] && ok "up-to-date repo is not flagged" || bad "up-to-date repo is not flagged" "behind=$got"

# Several repos in one pass.
rm -f "$TMP/cache.json"; rm -rf "$TMP/state"
mkrepo alpha 1111111111111111111111111111111111111111
mkrepo beta  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
run
got=$(jq -r '[.repos.alpha.behind, .repos.beta.behind] | join(",")' "$TMP/cache.json" 2>/dev/null)
[[ $got == "true,false" ]] && ok "multiple repos checked in one pass" || bad "multiple repos" "got=$got"

# Network down: must still write valid JSON, and must NOT claim anything is behind.
rm -f "$TMP/cache.json"; rm -rf "$TMP/state"
mkrepo alpha 1111111111111111111111111111111111111111
HYPRPM_MGR_STATE_DIR="$TMP/state" HYPRPM_MGR_GIT="$TMP/git" HYPRPM_MGR_CACHE="$TMP/cache.json" \
  GIT_STUB_FAIL=1 "$UPD" >/dev/null 2>&1; rc=$?
if jq -e . "$TMP/cache.json" >/dev/null 2>&1; then
  got=$(jq -r '.repos.alpha.behind' "$TMP/cache.json")
  [[ $rc -eq 0 && $got == "false" ]] && ok "unreachable upstream never claims an update" \
    || bad "unreachable upstream never claims an update" "exit=$rc behind=$got"
else
  bad "unreachable upstream never claims an update" "cache is not valid JSON"
fi

# No repos at all: still valid JSON, empty.
rm -f "$TMP/cache.json"; rm -rf "$TMP/state"; mkdir -p "$TMP/state"
run
got=$(jq -r '.repos | length' "$TMP/cache.json" 2>/dev/null)
[[ $got == "0" ]] && ok "no repos yields an empty cache" || bad "no repos yields an empty cache" "got=$got"

# checkedAt is recorded so staleness can be judged later.
got=$(jq -r '.checkedAt' "$TMP/cache.json" 2>/dev/null)
[[ $got =~ ^[0-9]+$ && $got -gt 0 ]] && ok "records checkedAt" || bad "records checkedAt" "got=$got"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
