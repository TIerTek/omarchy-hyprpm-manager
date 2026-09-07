// NotifyModel.js — decides WHETHER to say something, and in what words.
//
// Pure functions: no QML, no I/O, no clock of its own. Service.qml owns
// polling and the notify-send call; everything about *when* a notification is
// warranted lives here so it can be unit tested against a fake clock
// (tests/test-notify-model.cjs) rather than by waiting twelve hours.
//
// The guiding rule is that a status notifier which repeats itself gets muted,
// and a muted notifier is worthless. So: speak on transitions, never on
// steady state.

var REARM_MS = 12 * 3600 * 1000;

function severity(state) {
  if (state === "broken") return 2;
  if (state === "degraded") return 1;
  return 0;                       // ok, unavailable, anything unrecognised
}

function problemTitle(code) {
  switch (code) {
    case "deps_missing":    return "Build tools missing";
    case "headers_missing": return "Hyprland headers not installed";
    case "abi_mismatch":    return "Built against a different Hyprland";
    case "rebuild_pending": return "Rebuild needed before next restart";
    case "not_loaded":      return "Enabled plugin is not loaded";
    case "build_failed":    return "Plugin failed to build";
  }
  return code;
}

function codesOf(doc) {
  var out = [];
  var ps = (doc && doc.problems) ? doc.problems : [];
  for (var i = 0; i < ps.length; i++) out.push(ps[i].code);
  out.sort();                     // order from the collector is not meaningful
  return out;
}

// Identity of a situation. Two polls with the same signature are the same
// news; a changed signature is worth interrupting for even inside the quiet
// window, because it means something new broke.
function signatureOf(doc) {
  if (!doc || severity(doc.state) === 0) return "";
  return doc.state + "|" + codesOf(doc).join(",");
}

function decide(prev, doc, nowMs, rearmMs) {
  var rearm = (typeof rearmMs === "number") ? rearmMs : REARM_MS;
  var sig = signatureOf(doc);

  // Healthy, or hyprpm is not in use. Clear the latch rather than remembering
  // it: if this machine breaks again next week that is news, not a repeat.
  if (sig === "")
    return { notify: false, state: { signature: "", notifiedAtMs: 0 } };

  var same = !!prev && prev.signature === sig;
  if (same && (nowMs - (prev.notifiedAtMs || 0)) < rearm)
    return { notify: false, state: { signature: prev.signature, notifiedAtMs: prev.notifiedAtMs } };

  var broken = doc.state === "broken";
  var ps = (doc.problems && doc.problems.length) ? doc.problems : [];
  var first = ps.length ? ps[0] : null;

  return {
    notify: true,
    // Already failing vs. will fail at the next restart. The second is the
    // more useful warning but must not shout, or it trains people to dismiss.
    urgency: broken ? "critical" : "normal",
    title: broken ? "Hyprland plugins are not loading"
                  : "Hyprland plugins need rebuilding",
    body: first
      ? problemTitle(first.code)
        + (first.detail ? " (" + first.detail + ")" : "")
        + (first.fix ? ". Fix: " + first.fix : "")
      : "Open the hyprpm panel for details.",
    state: { signature: sig, notifiedAtMs: nowMs }
  };
}

if (typeof module !== "undefined") module.exports = {
  decide: decide, signatureOf: signatureOf, problemTitle: problemTitle,
  severity: severity, REARM_MS: REARM_MS
};
