import QtQuick
import Quickshell
import Quickshell.Io
import "NotifyModel.js" as NotifyModel

// Headless watcher. The bar widget can only tell you something is wrong if you
// happen to open it; this is what makes the plugin actually warn you.
//
// Shares bin/hyprpm-status with the widget rather than re-implementing
// detection, so the two can never disagree about what "broken" means.
Item {
  id: root

  property var shell: null

  // Slow on purpose. Nothing here changes minute to minute, and every poll
  // shells out to hyprctl.
  readonly property int pollMs: 15 * 60 * 1000

  // Login is when post-update breakage actually surfaces - you restart, the
  // plugins silently do not load, and nothing says so. Check shortly after
  // start, but not instantly: the session is still coming up.
  readonly property int startupDelayMs: 45 * 1000

  // Asking six remotes whether they have moved on is not urgent and costs
  // network, so it runs far less often than the local health check and never
  // during the login rush. Its answer reaches the UI only through the cache.
  readonly property int updateCheckMs: 6 * 3600 * 1000
  readonly property int updateStartupDelayMs: 90 * 1000

  // Survives a shell reload, so `omarchy restart shell` (which happens during
  // updates - exactly when things break) does not re-announce old news.
  PersistentProperties {
    id: persisted
    reloadableId: "tiertek-hyprpm-manager-notify"
    property string signature: ""
    property double notifiedAtMs: 0
  }

  function check() {
    if (!statusProc.running) statusProc.running = true
  }

  function evaluate(text) {
    var doc
    try {
      doc = JSON.parse(text)
    } catch (e) {
      return                      // a broken collector is not worth waking anyone for
    }
    if (!doc || !doc.state) return

    var r = NotifyModel.decide(
      { signature: persisted.signature, notifiedAtMs: persisted.notifiedAtMs },
      doc, Date.now())

    persisted.signature = r.state.signature
    persisted.notifiedAtMs = r.state.notifiedAtMs

    if (r.notify) send(r)
  }

  function send(r) {
    if (notifyProc.running) return
    notifyProc.command = [
      "notify-send",
      "--app-name=hyprpm Manager",
      "--urgency=" + r.urgency,
      "--icon=application-x-addon",
      r.title,
      r.body
    ]
    notifyProc.running = true
  }

  Process {
    id: statusProc
    command: [
      "timeout", "--kill-after=1s", "10s", "bash",
      decodeURIComponent(Qt.resolvedUrl("bin/hyprpm-status").toString().slice(7))
    ]
    stdout: StdioCollector { id: statusOut }
    onExited: root.evaluate(statusOut.text)
  }

  Process { id: notifyProc }

  function checkUpdates() {
    if (!updatesProc.running) updatesProc.running = true
  }

  Process {
    id: updatesProc
    command: [
      "timeout", "--kill-after=5s", "120s", "bash",
      decodeURIComponent(Qt.resolvedUrl("bin/hyprpm-updates").toString().slice(7))
    ]
  }

  Timer {
    interval: root.updateStartupDelayMs
    running: true
    repeat: false
    onTriggered: root.checkUpdates()
  }

  Timer {
    interval: root.updateCheckMs
    running: true
    repeat: true
    onTriggered: root.checkUpdates()
  }

  Timer {
    interval: root.startupDelayMs
    running: true
    repeat: false
    onTriggered: root.check()
  }

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    onTriggered: root.check()
  }
}
