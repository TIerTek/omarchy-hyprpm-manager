import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons
BarWidget {
  id: root
  moduleName: "tiertek.hyprpm-manager"
  // Hidden unless this machine actually uses hyprpm. Most Omarchy users have
  // no native Hyprland plugins at all, and an always-present icon telling them
  // so would just be clutter in the bar.
  visible: status.available
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property color stateColor: {
    if (status.state === "broken") return Color.urgent
    if (status.state === "degraded") return Qt.tint(Color.foreground, Qt.rgba(1, 0.65, 0, 0.45))
    return Color.foreground
  }
  readonly property string tooltip: {
    if (status.state === "broken") return "Hyprland plugins are not loading — click to fix"
    if (status.state === "degraded") return "Hyprland plugins need rebuilding before the next restart"
    return "Hyprland plugins healthy"
  }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function refresh() { status.refresh() }
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.status = status
  }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Status { id: status }
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
  IpcHandler {
    target: "tiertek.hyprpm-manager"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf12e"
    foreground: root.stateColor
    tooltipText: root.tooltip
    onPressed: root.toggle()
  }
}
