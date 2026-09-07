import QtQuick
import Quickshell.Io

// Non-visual: polls bin/hyprpm-status and exposes the parsed document.
//
// All detection lives in the shell collector, which is covered by
// tests/test-status.sh. This component only schedules it and parses JSON, so a
// change to the state machine never requires touching QML.
Item {
  id: root

  readonly property var empty: ({
    schema: 1, state: "unavailable",
    hyprland: { tag: "", commit: "" }, headers: { status: "unknown" },
    deps: { missing: [] }, plugins: [], problems: []
  })

  property var data: empty
  property bool busy: false
  property int intervalMs: 60000

  readonly property string state: data && data.state ? data.state : "unavailable"
  readonly property bool available: state !== "unavailable"

  signal refreshed()

  function refresh() {
    if (proc.running) return
    root.busy = true
    proc.running = true
  }

  Process {
    id: proc
    command: [
      "timeout", "--kill-after=1s", "10s", "bash",
      decodeURIComponent(Qt.resolvedUrl("bin/hyprpm-status").toString().slice(7))
    ]
    stdout: StdioCollector { id: out }
    onExited: {
      // The collector is contracted to always print valid JSON and exit 0.
      // If it somehow does neither, fall back to "unavailable" so the widget
      // hides rather than rendering a half-parsed state.
      try {
        var parsed = JSON.parse(out.text)
        root.data = (parsed && parsed.state) ? parsed : root.empty
      } catch (e) {
        root.data = root.empty
      }
      root.busy = false
      root.refreshed()
    }
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
