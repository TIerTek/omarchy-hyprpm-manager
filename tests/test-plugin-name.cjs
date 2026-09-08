// Tests for PluginName.js — the closed grammar applied to a plugin name at the
// QML boundary, before it is composed into the string that the floating
// terminal launcher re-parses as a shell command.
//
// This mirrors the identical check in bin/hyprpm-apply (tests/test-apply.sh).
// Both exist deliberately: the helper must be safe when run by hand, and the
// panel must never build the hostile string in the first place.
const assert = require("node:assert/strict");
const { isSafeName } = require("../PluginName.js");

// Names hyprpm legitimately produces must all survive.
for (const ok of [
  "hyprexpo", "hyprbars", "hyprfocus",
  "borders-plus-plus", "csgo-vulkan-fix",
  "my_plug.in-2", "a", "A1", "_leading_underscore",
]) {
  assert.equal(isSafeName(ok), true, "must accept: " + ok);
}

// Anything that can reach a shell parser must not.
for (const bad of [
  "hyprexpo; touch /tmp/pwned",
  "hyprexpo$(id)",
  "hyprexpo`id`",
  "hyprexpo|id",
  "hyprexpo&&id",
  "hyprexpo>/tmp/x",
  "hyprexpo <in",
  "hypr expo",
  "hyprexpo\nid",
  "hyprexpo\tid",
  "hyprexpo*",
  "hyprexpo?",
  "hyprexpo[a]",
  "hyprexpo'",
  'hyprexpo"',
  "hyprexpo\\",
  "hyprexpo$HOME",
  "../../etc/passwd",
  "/abs/path",
]) {
  assert.equal(isSafeName(bad), false, "must reject: " + JSON.stringify(bad));
}

// A name may never be mistaken for an option by hyprpm itself.
for (const flag of ["--help", "-rf", "-", "--"]) {
  assert.equal(isSafeName(flag), false, "must reject flag-like: " + flag);
}

// Absent, empty and non-string input are all unsafe, never a crash.
for (const junk of ["", undefined, null, 0, 42, {}, [], ["hyprexpo"], true]) {
  assert.equal(isSafeName(junk), false, "must reject: " + JSON.stringify(junk));
}

// The grammar must be anchored — a hostile name is not rescued by a safe tail.
assert.equal(isSafeName("hyprexpo\nhyprbars"), false, "must be anchored, not per-line");
assert.equal(isSafeName("hyprexpo\n"), false, "trailing newline must not slip past $");
assert.equal(isSafeName("\nhyprexpo"), false, "leading newline must not slip past ^");

console.log("test-plugin-name: all assertions passed");
