import QtQuick
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "tiertek.hyprpm-manager"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var status: null

  readonly property var barIdentity: hostWidget || root
  readonly property var doc: (status && status.data) ? status.data : ({})
  readonly property var plugins: doc.plugins ? doc.plugins : []
  readonly property var problems: doc.problems ? doc.problems : []
  readonly property string hyprTag: (doc.hyprland && doc.hyprland.tag) ? doc.hyprland.tag : "unknown"
  readonly property string headersStatus: (doc.headers && doc.headers.status) ? doc.headers.status : "unknown"
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  readonly property color stateColor: {
    if (doc.state === "broken") return Color.urgent
    if (doc.state === "degraded") return Qt.tint(Color.foreground, Qt.rgba(1, 0.65, 0, 0.45))
    return Color.foreground
  }

  readonly property string headline: {
    // "unavailable" is reachable here even though the bar button hides in that
    // state: the panel can still be opened over IPC, and it must not claim
    // everything is fine when the collector found nothing at all.
    if (doc.state === "unavailable") return "hyprpm not in use"
    if (doc.state === "broken") return "Plugins are not loading"
    if (doc.state === "degraded") return "Rebuild needed before next restart"
    return "All plugins loaded"
  }

  readonly property string subline: {
    if (doc.state === "unavailable") return "No Hyprland plugin repositories installed"
    return "Hyprland " + root.hyprTag + " \u00b7 headers " + root.headersStatus
  }

  function problemTitle(code) {
    switch (code) {
      case "deps_missing":    return "Build tools missing"
      case "headers_missing": return "Hyprland headers not installed"
      case "abi_mismatch":    return "Built against a different Hyprland"
      case "rebuild_pending": return "Rebuild needed before next restart"
      case "not_loaded":      return "Enabled plugin is not loaded"
      case "build_failed":    return "Plugin failed to build"
    }
    return code
  }

  function pluginState(p) {
    if (!p.enabled) return "disabled"
    if (p.failed) return "build failed"
    return p.loaded ? "loaded" : "not loaded"
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Long and privileged work is handed to a visible terminal rather than run
  // behind the panel. hyprpm compiles Hyprland and elevates on its own; a
  // silent Process would swallow both the build output and the password
  // prompt, and this plugin deliberately holds no privilege of its own.
  function runInTerminal(cmd) {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + cmd)
    root.close()
  }

  // Flipping a plugin is NOT unprivileged. hyprpm elevates for every state
  // write, not only for builds, so run from the shell process this fails with
  // "Failed to write plugin state" and the switch springs back with no
  // explanation. It goes to the same visible terminal as update and reload.
  //
  // The launcher collapses its arguments with "$*", which destroys quoting, so
  // the work lives in bin/hyprpm-apply and is invoked with plain arguments --
  // never as a composed shell string with && or quotes in it.
  readonly property string applyHelper:
    decodeURIComponent(Qt.resolvedUrl("bin/hyprpm-apply").toString().slice(7))

  function setPluginEnabled(name, on) {
    root.runInTerminal(root.applyHelper + " " + (on ? "enable" : "disable") + " " + name)
  }

  onOpenedChanged: if (opened && status) status.refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "u" || t === "U") root.runInTerminal("hyprpm update")
        else if (t === "r" || t === "R") root.runInTerminal("hyprpm reload")
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        // ---------- Hero: state glyph, headline, Hyprland version ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf12e"
            color: root.stateColor
            font.family: root.family
            font.pixelSize: Style.font.display
          }

          Column {
            id: heroText
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.headline
              color: root.stateColor
              font.family: root.family
              font.pixelSize: Style.font.title
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.subline
              color: Qt.darker(Color.foreground, 1.5)
              font.family: root.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        // ---------- Problems: cause first, with the command that fixes it ----------
        PanelSeparator { width: parent.width; visible: root.problems.length > 0 }
        PanelSectionHeader {
          text: root.problems.length === 1 ? "Problem" : "Problems"
          visible: root.problems.length > 0
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.problems.length > 0

          Repeater {
            model: root.problems
            delegate: Item {
              required property var modelData
              width: column.width
              implicitHeight: pcol.implicitHeight

              Column {
                id: pcol
                width: parent.width
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.problemTitle(modelData.code)
                  color: Color.urgent
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  visible: !!modelData.detail
                  textFormat: Text.PlainText
                  text: modelData.detail
                  color: Qt.darker(Color.foreground, 1.5)
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  visible: !!modelData.fix
                  textFormat: Text.PlainText
                  text: "fix: " + modelData.fix
                  color: Qt.darker(Color.foreground, 1.3)
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        // ---------- Plugins ----------
        PanelSeparator { width: parent.width }
        PanelSectionHeader { text: "Hyprland plugins" }

        Text {
          width: parent.width
          visible: root.plugins.length === 0
          textFormat: Text.PlainText
          text: "No hyprpm plugins installed."
          color: Qt.darker(Color.foreground, 1.5)
          font.family: root.family
          font.pixelSize: Style.font.bodySmall
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: root.plugins
            delegate: Item {
              required property var modelData
              width: column.width
              implicitHeight: Math.max(labels.implicitHeight, sw.implicitHeight)

              Column {
                id: labels
                anchors.left: parent.left
                anchors.right: sw.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.name
                  color: Color.foreground
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.repo + " · " + root.pluginState(modelData)
                  color: (modelData.enabled && !modelData.loaded)
                    ? Color.urgent : Qt.darker(Color.foreground, 1.5)
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              ToggleSwitch {
                id: sw
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: modelData.enabled === true
                foreground: Color.foreground
                onToggled: root.setPluginEnabled(modelData.name, !modelData.enabled)
              }
            }
          }
        }

        // ---------- Actions ----------
        PanelSeparator { width: parent.width }

        Item {
          width: parent.width
          implicitHeight: Math.max(actions.implicitHeight, hint.implicitHeight)

          Row {
            id: actions
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            PanelActionButton {
              iconText: "\uf019"
              tooltipText: "Update and rebuild all plugins (u)"
              foreground: Color.foreground
              onClicked: root.runInTerminal("hyprpm update")
            }
            PanelActionButton {
              iconText: "\uf021"
              tooltipText: "Reload plugins into the running Hyprland (r)"
              foreground: Color.foreground
              onClicked: root.runInTerminal("hyprpm reload")
            }
          }

          Text {
            id: hint
            anchors.right: parent.right
            anchors.left: actions.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: "opens a terminal"
            color: Qt.darker(Color.foreground, 1.6)
            font.family: root.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
