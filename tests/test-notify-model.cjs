const assert = require("node:assert/strict");
const { decide, signatureOf, problemTitle, REARM_MS } = require("../NotifyModel.js");

const H = 3600 * 1000;
const fresh = { signature: "", notifiedAtMs: 0 };
const doc = (state, codes) => ({
  state, problems: codes.map(c => ({ code: c, detail: "", fix: "hyprpm update" }))
});

// Nothing to say: no notification, and the latch is cleared so a LATER break
// still notifies rather than being deduped against a stale signature.
for (const quiet of ["ok", "unavailable"]) {
  const r = decide({ signature: "broken|abi_mismatch", notifiedAtMs: 1000 }, doc(quiet, []), 2000);
  assert.equal(r.notify, false, quiet + " must not notify");
  assert.equal(r.state.signature, "", quiet + " must clear the latch");
}

// First time broken.
let r = decide(fresh, doc("broken", ["abi_mismatch"]), 1000);
assert.equal(r.notify, true);
assert.equal(r.urgency, "critical");
assert.match(r.title, /not loading/i);
assert.equal(r.state.notifiedAtMs, 1000);

// Same problem again shortly after: silent.
const after = r.state;
assert.equal(decide(after, doc("broken", ["abi_mismatch"]), 1000 + H).notify, false);

// Same problem still there much later: re-arms.
assert.equal(decide(after, doc("broken", ["abi_mismatch"]), 1000 + REARM_MS + 1).notify, true);

// A DIFFERENT problem is news even within the quiet window.
assert.equal(decide(after, doc("broken", ["build_failed"]), 1000 + H).notify, true);

// Problem order must not matter.
assert.equal(
  signatureOf(doc("broken", ["not_loaded", "build_failed"])),
  signatureOf(doc("broken", ["build_failed", "not_loaded"])));

// degraded warns, but quietly.
r = decide(fresh, doc("degraded", ["rebuild_pending"]), 5000);
assert.equal(r.notify, true);
assert.equal(r.urgency, "normal");
assert.match(r.title, /rebuild/i);

// Escalation degraded -> broken is news.
assert.equal(decide(r.state, doc("broken", ["abi_mismatch"]), 6000).notify, true);

// Recovery is silent, and breaking again afterwards notifies again.
const recovered = decide(r.state, doc("ok", []), 7000);
assert.equal(recovered.notify, false);
assert.equal(decide(recovered.state, doc("degraded", ["rebuild_pending"]), 8000).notify, true);

// Body names the cause and the fix.
r = decide(fresh, doc("broken", ["deps_missing"]), 1000);
assert.match(r.body, /build tools/i);
assert.match(r.body, /hyprpm update/);

// Every code the collector can emit has human text.
for (const c of ["deps_missing","headers_missing","abi_mismatch","rebuild_pending","not_loaded","build_failed"]) {
  assert.notEqual(problemTitle(c), c, "no human text for " + c);
}

console.log("test-notify-model: all assertions passed");
