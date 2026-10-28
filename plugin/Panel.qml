import QtQuick 6.11
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// RAM Free: bar ring showing memory use, plus a popup with five one-click
// depths. Each depth tile runs `bin/ramfree run <n>` immediately.
Panel {
  id: root
  moduleName: "arch.ramfree"
  ipcTarget: "arch.ramfree"
  manageIpc: false

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    return decodeURIComponent(u.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property string cli: pluginDir + "/bin/ramfree"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showPercent: setting("showPercent", false) === true

  property var mem: Model.parseMeminfo("")
  property int selected: 2
  property int hovered: 0
  property int runningLevel: 0
  property var lastResult: null
  property bool helperInstalled: false
  property bool runFromIpc: false

  readonly property int focusLevel: hovered > 0 ? hovered : selected
  readonly property var focusInfo: Model.LEVELS[focusLevel - 1]
  readonly property color gaugeColor: mem.usedFraction >= 0.85 ? urgent : accent

  function tint(depth, alpha) {
    // Mix foreground toward accent (and urgent at the top end) by depth.
    var t = (depth - 1) / 4
    var base = depth === 5 ? urgent : accent
    var r = foreground.r + (base.r - foreground.r) * (0.35 + 0.65 * t)
    var g = foreground.g + (base.g - foreground.g) * (0.35 + 0.65 * t)
    var b = foreground.b + (base.b - foreground.b) * (0.35 + 0.65 * t)
    return Qt.rgba(r, g, b, alpha)
  }

  function refreshMem() {
    if (!memProc.running) memProc.running = true
  }

  function runLevel(depth) {
    depth = Number(depth)
    if (!(depth >= 1 && depth <= 5) || runProc.running) return
    selected = depth
    runningLevel = depth
    lastResult = null
    runProc.command = [root.cli, "run", String(depth)]
    runProc.running = true
  }

  function moveSelection(dx) {
    selected = Math.max(1, Math.min(5, selected + dx))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    hovered = 0
    refreshMem()
    helperProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: memProc
    command: ["cat", "/proc/meminfo"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mem = Model.parseMeminfo(text)
    }
  }

  Process {
    id: helperProc
    command: [root.cli, "helper"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.helperInstalled = String(text).trim() === "installed"
    }
  }

  Process {
    id: runProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try { parsed = JSON.parse(String(text).trim().split("\n").pop()) } catch (e) {}
        root.lastResult = parsed || { ok: false, error: "no output" }
        root.runningLevel = 0
        root.refreshMem()
        if (root.runFromIpc && !root.opened && root.bar)
          root.bar.run("omarchy-notification-send " + JSON.stringify("RAM Free: " + Model.resultText(root.lastResult)))
        root.runFromIpc = false
      }
    }
    onExited: function(code) {
      if (root.runningLevel !== 0) {
        root.runningLevel = 0
        if (!root.lastResult) root.lastResult = { ok: false, error: "exit " + code }
      }
    }
  }

  Timer {
    interval: root.opened ? 1500 : 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshMem()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function run(level: string): string {
      root.runFromIpc = true
      root.runLevel(parseInt(level, 10))
      return "started"
    }
  }

  // ---- bar button -------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.showPercent ? Style.bar.iconSlot * 1.9 : Style.bar.iconSlot
    tooltipText: "RAM " + Model.percent(root.mem.usedFraction) + " used · " + Model.formatKiB(root.mem.availableKiB) + " available"
    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)

          Item {
            width: Style.bar.iconCanvas
            height: Style.bar.iconCanvas
            anchors.verticalCenter: parent.verticalCenter

            RingGauge {
              id: barRing
              anchors.fill: parent
              thickness: Math.max(2, width * 0.17)
              value: root.mem.usedFraction
              arcColor: root.runningLevel > 0 ? root.accent : (root.mem.usedFraction >= 0.85 ? root.urgent : root.barForeground)
              trackColor: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.22)
              secondary: 0

              RotationAnimator on rotation {
                running: root.runningLevel > 0
                from: 0; to: 360; duration: 900
                loops: Animation.Infinite
                onRunningChanged: if (!running) barRing.rotation = 0
              }
            }
          }

          Text {
            visible: root.showPercent
            anchors.verticalCenter: parent.verticalCenter
            text: Model.percent(root.mem.usedFraction)
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont - 2
          }
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.runLevel(root.selected)
      else root.toggle()
    }
  }

  // ---- popup ------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(372))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.hovered = 0; root.moveSelection(dx !== 0 ? dx : dy) }
      onActivateRequested: root.runLevel(root.selected)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t >= "1" && t <= "5") root.runLevel(parseInt(t, 10))
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        // -- hero: big gauge + stats
        Row {
          width: parent.width
          spacing: Style.space(16)

          Item {
            id: gaugeBox
            width: Style.space(104)
            height: width

            RingGauge {
              anchors.fill: parent
              thickness: Style.space(9)
              value: root.mem.usedFraction
              secondary: root.mem.cacheFraction
              arcColor: root.gaugeColor
              secondaryColor: Qt.rgba(root.gaugeColor.r, root.gaugeColor.g, root.gaugeColor.b, 0.32)
              trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            }

            Column {
              anchors.centerIn: parent
              spacing: 0
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Model.percent(root.mem.usedFraction)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "USED"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.5
              }
            }
          }

          Column {
            width: parent.width - gaugeBox.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(7)

            Text {
              text: "Memory"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: Model.formatKiB(root.mem.usedKiB) + " of " + Model.formatKiB(root.mem.totalKiB)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            StatBar { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Available"; value: Model.formatKiB(root.mem.availableKiB); fraction: 1 - root.mem.usedFraction; barColor: root.foreground }
            StatBar { foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily; label: "Cache"; value: Model.formatKiB(root.mem.cacheKiB); fraction: root.mem.cacheFraction; barColor: root.gaugeColor }
            StatBar {
              visible: root.mem.swapTotalKiB > 0
              foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
              label: "Swap"; value: Model.formatKiB(root.mem.swapUsedKiB); fraction: root.mem.swapFraction; barColor: root.dim
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        PanelSectionHeader {
          text: "DEPTH"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // -- depth tiles
        Row {
          id: tiles
          width: parent.width
          spacing: Style.space(6)
          readonly property real tileWidth: (width - spacing * 4) / 5

          Repeater {
            model: Model.LEVELS
            delegate: Rectangle {
              id: tile
              required property var modelData
              readonly property int depth: modelData.depth
              readonly property bool isFocus: root.focusLevel === depth
              readonly property bool isRunning: root.runningLevel === depth

              width: tiles.tileWidth
              height: Style.space(70)
              radius: Math.max(Style.cornerRadius, Style.space(8))
              color: root.tint(depth, isFocus ? 0.16 + depth * 0.035 : 0.05 + depth * 0.02)
              border.width: isFocus ? Math.max(1, Style.space(1.5)) : 1
              border.color: root.tint(depth, isFocus ? 0.9 : 0.18)
              opacity: root.runningLevel > 0 && !isRunning ? 0.4 : 1
              scale: tileMouse.pressed ? 0.95 : 1

              Behavior on color { ColorAnimation { duration: 140 } }
              Behavior on opacity { NumberAnimation { duration: 160 } }
              Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

              // Depth meter: one to five bars rising with the level.
              Row {
                anchors.top: parent.top
                anchors.topMargin: Style.space(8)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(2)
                Repeater {
                  model: 5
                  delegate: Item {
                    id: meterSlot
                    required property int index
                    width: Style.space(3)
                    height: Style.space(10)
                    Rectangle {
                      anchors.bottom: parent.bottom
                      width: parent.width
                      height: Style.space(3 + meterSlot.index * 1.75)
                      radius: width / 2
                      color: meterSlot.index < tile.depth ? root.tint(tile.depth, 0.95) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                    }
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Style.space(3)
                visible: !tile.isRunning
                text: String(tile.depth)
                color: tile.isFocus ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }

              RingGauge {
                visible: tile.isRunning
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Style.space(3)
                width: Style.space(22); height: width
                thickness: Style.space(3)
                value: 0.28
                animate: false
                arcColor: root.tint(tile.depth, 1)
                trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                RotationAnimator on rotation { running: tile.isRunning; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
              }

              Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(7)
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.modelData.name
                color: tile.isFocus ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.runningLevel > 0 ? Qt.BusyCursor : Qt.PointingHandCursor
                onContainsMouseChanged: root.hovered = containsMouse ? tile.depth : (root.hovered === tile.depth ? 0 : root.hovered)
                onClicked: root.runLevel(tile.depth)
              }
            }
          }
        }

        // -- description of the focused depth
        Column {
          width: parent.width
          spacing: Style.space(4)

          Row {
            spacing: Style.space(6)
            Text {
              text: root.focusInfo.name
              color: root.tint(root.focusLevel, 1)
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: badge.implicitWidth + Style.space(10)
              height: badge.implicitHeight + Style.space(4)
              radius: height / 2
              color: "transparent"
              border.width: 1
              border.color: root.focusInfo.root ? root.tint(root.focusLevel, 0.5) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
              Text {
                id: badge
                anchors.centerIn: parent
                text: root.focusInfo.root ? (root.helperInstalled ? "ROOT" : "ROOT · HELPER MISSING") : "NO PASSWORD"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - 1
                font.letterSpacing: 1
              }
            }
          }

          Text {
            width: parent.width
            text: root.focusInfo.detail
            color: root.dim
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // -- result
        Rectangle {
          id: resultCard
          width: parent.width
          visible: root.lastResult !== null || root.runningLevel > 0
          height: resultCol.implicitHeight + Style.space(16)
          radius: Math.max(Style.cornerRadius, Style.space(8))
          readonly property bool good: root.lastResult && root.lastResult.ok
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
          border.width: 1
          border.color: root.runningLevel > 0 ? root.tint(root.runningLevel, 0.5)
            : (good ? root.tint(root.lastResult.level, 0.5) : Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.6))

          Column {
            id: resultCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(10)
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: root.runningLevel > 0
                ? "Freeing memory at depth " + root.runningLevel + "…"
                : (resultCard.good ? "✓  " : "✕  ") + Model.resultText(root.lastResult)
              color: root.runningLevel > 0 || resultCard.good ? root.foreground : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              visible: text !== "" && root.runningLevel === 0
              text: Model.helperNote(root.lastResult)
              color: root.dim
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          width: parent.width
          text: "Press 1–5 to run · ←/→ + Enter"
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 2.1)
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
