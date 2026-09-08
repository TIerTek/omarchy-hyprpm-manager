// PluginName.js — the closed grammar for a hyprpm plugin name.
//
// A plugin name is attacker-influenced input. It is read out of hyprpm's
// state.toml, which is populated from whatever git repository the user added,
// and Panel.qml composes it into a single string handed to
// omarchy-launch-floating-terminal-with-presentation. That launcher collapses
// its arguments with "$*" and lets a shell re-parse the result, so a name
// containing ; $() `` | & > or whitespace would become command execution the
// moment someone clicks the enable/disable toggle.
//
// The panel therefore refuses to build the string at all unless the name
// matches this grammar. bin/hyprpm-apply enforces the identical rule, so the
// helper is also safe when run by hand. Reported by the Omarchy marketplace
// security review of v0.3.0.
//
// Pure and QML-free so it can be unit tested with node
// (tests/test-plugin-name.cjs).

// Anchored, and deliberately narrow: the first character may not be "-" or "."
// so a name can never be read as an option ("--help") or a path by hyprpm
// itself. Every plugin hyprland-plugins ships -- hyprexpo, hyprbars,
// hyprfocus, borders-plus-plus, csgo-vulkan-fix -- satisfies it.
var SAFE_NAME = /^[A-Za-z0-9_][A-Za-z0-9._-]*$/;

function isSafeName(name) {
  if (typeof name !== "string" || name.length === 0) return false;
  return SAFE_NAME.test(name);
}

if (typeof module !== "undefined") module.exports = {
  isSafeName: isSafeName, SAFE_NAME: SAFE_NAME
};
