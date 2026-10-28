import QtQuick 6.11
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Memdive: a memory ring in the bar and a popup with five one-click depths.
// Each depth tile runs `bin/memdive run <n>`; the hand-drawn dive log below
// the tiles shows recent runs and a hint for the current situation.
Panel {
  id: root
  moduleName: "io.github.arbabmujtaba.memdive"
  ipcTarget: "io.github.arbabmujtaba.memdive"
  manageIpc: false

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    return decodeURIComponent(u.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property string cli: pluginDir + "/bin/memdive"
  readonly property string historyPath: {
    var state = Quickshell.env("XDG_STATE_HOME")
    return (state && state !== "" ? state : Quickshell.env("HOME") + "/.local/state") + "/memdive/history.jsonl"
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string handFamily: handFont.status === FontLoader.Ready ? handFont.name : fontFamily
  readonly property bool vertical: bar ? bar.vertical === true : false
  readonly property bool showPercent: setting("showPercent", false) === true && !vertical

  property var mem: Model.parseMeminfo("")
  property var caps: null
  property var history: Model.parseHistory("", Date.now())
  property real nowMs: Date.now()
  property int selected: 2
  property int hovered: 0
  property int runningLevel: 0
  property var lastResult: null
  property bool runFromIpc: false
  property bool installingHelper: false

  readonly property bool helperReady: caps !== null && caps.helper === "installed"
  readonly property bool helperNeeded: caps !== null && caps.helper !== "installed" && caps.pkexec === true
  readonly property bool rootless: caps === null || caps.reclaim !== false
  readonly property int focusLevel: hovered > 0 ? hovered : selected
  readonly property var focusInfo: Model.LEVELS[focusLevel - 1]
  readonly property color gaugeColor: mem.usedFraction >= 0.85 ? urgent : accent

  function tint(depth, alpha) {
    // Foreground blends toward the accent as you go deeper; Abyss uses urgent.
    var t = 0.35 + 0.65 * (depth - 1) / 4
    var base = depth === 5 ? urgent : accent
    return Qt.rgba(foreground.r + (base.r - foreground.r) * t,
                   foreground.g + (base.g - foreground.g) * t,
                   foreground.b + (base.b - foreground.b) * t, alpha)
  }

  function refreshMem() { if (!memProc.running) memProc.running = true }
  function refreshCaps() { if (!capsProc.running) capsProc.running = true }

  function runLevel(depth) {
    depth = Number(depth)
    if (!(depth >= 1 && depth <= 5) || runProc.running) return
    selected = depth
    runningLevel = depth
    lastResult = null
    runProc.command = [root.cli, "run", String(depth)]
    runProc.running = true
  }

  function installHelper() {
    if (installProc.running) return
    installingHelper = true
    installProc.command = ["pkexec", "bash", root.pluginDir + "/helper/install.sh"]
    installProc.running = true
  }

  function notify(text) {
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run("command -v omarchy-notification-send >/dev/null && omarchy-notification-send " + JSON.stringify(text)
        + " || notify-send Memdive " + JSON.stringify(text))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    hovered = 0
    nowMs = Date.now()
    refreshMem()
    refreshCaps()
    historyFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  FontLoader {
    id: handFont
    source: Qt.resolvedUrl("assets/fonts/Caveat.ttf")
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.history = Model.parseHistory(text(), Date.now())
    onLoadFailed: root.history = Model.parseHistory("", Date.now())
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
    id: capsProc
    command: [root.cli, "caps"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.caps = Model.parseCaps(text)
    }
  }

  Process {
    id: installProc
    onExited: function() {
      root.installingHelper = false
      root.refreshCaps()
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
        root.nowMs = Date.now()
        root.refreshMem()
        historyFile.reload()
        if (root.runFromIpc && !root.opened) root.notify("Memdive: " + Model.resultText(root.lastResult))
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
    onTriggered: { root.refreshMem(); if (root.opened) root.nowMs = Date.now() }
  }

  Component.onCompleted: refreshCaps()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function run(level: string): string {
      var depth = parseInt(level, 10)
      if (!(depth >= 1 && depth <= 5)) return "depth must be 1-5"
      root.runFromIpc = true
      root.runLevel(depth)
      return "diving to " + depth
    }
  }

  // ---- bar button -------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.showPercent ? Style.bar.iconSlot * 1.9 : Style.bar.iconSlot
    tooltipText: "Memory " + Model.percent(root.mem.usedFraction) + " used · " + Model.formatKiB(root.mem.availableKiB) + " free"
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.hovered = 0
        root.selected = Math.max(1, Math.min(5, root.selected + (dx !== 0 ? dx : dy)))
      }
      onActivateRequested: root.runLevel(root.selected)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t >= "1" && t <= "5") root.runLevel(parseInt(t, 10)) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(14)

          // -- hero: porthole + stats
          Row {
            width: parent.width
            spacing: Style.space(16)

            Item {
              id: gaugeBox
              width: Style.space(108)
              height: width

              PortholeGauge {
                anchors.fill: parent
                value: root.mem.usedFraction
                animating: root.opened
                busy: root.runningLevel > 0
                waterColor: root.gaugeColor
                rimColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                glassColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
              }

              Column {
                anchors.centerIn: parent
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Model.percent(root.mem.usedFraction)
                  color: root.foreground
                  style: Text.Raised
                  styleColor: Qt.rgba(0, 0, 0, 0.35)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.runningLevel > 0 ? "DIVING" : "USED"
                  color: root.foreground
                  opacity: 0.7
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

              Row {
                spacing: Style.space(6)
                Text {
                  id: titleText
                  text: "Memdive"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }
                Text {
                  anchors.baseline: titleText.baseline
                  text: "~" + Math.round(root.mem.usedFraction * 200) + " m"
                  color: root.dim
                  font.family: root.handFamily
                  font.pixelSize: Style.font.title + 2
                }
              }
              Text {
                text: Model.formatKiB(root.mem.usedKiB) + " of " + Model.formatKiB(root.mem.totalKiB)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              StatBar {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                label: "Available"; value: Model.formatKiB(root.mem.availableKiB)
                fraction: 1 - root.mem.usedFraction; barColor: root.foreground
              }
              StatBar {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                label: "Cache"; value: Model.formatKiB(root.mem.cacheKiB)
                fraction: root.mem.cacheFraction; barColor: root.gaugeColor
              }
              StatBar {
                foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
                label: "Swap"
                value: root.mem.swapTotalKiB > 0 ? Model.formatKiB(root.mem.swapUsedKiB) : "none"
                fraction: root.mem.swapFraction; barColor: root.dim
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Item {
            width: parent.width
            height: depthHeader.implicitHeight
            PanelSectionHeader {
              id: depthHeader
              text: "PICK A DEPTH"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: depthHeader.verticalCenter
              text: "keys 1–5"
              color: Qt.darker(root.foreground, 2.0)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
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
                readonly property bool needsHelper: (modelData.root || !root.rootless) && root.caps !== null && !root.helperReady

                width: tiles.tileWidth
                height: Style.space(74)
                radius: Math.max(Style.cornerRadius, Style.space(8))
                gradient: Gradient {
                  GradientStop { position: 0.0; color: root.tint(tile.depth, tile.isFocus ? 0.10 + tile.depth * 0.03 : 0.03 + tile.depth * 0.012) }
                  GradientStop { position: 1.0; color: root.tint(tile.depth, tile.isFocus ? 0.22 + tile.depth * 0.04 : 0.07 + tile.depth * 0.03) }
                }
                border.width: tile.isFocus ? Math.max(1, Style.space(1.5)) : 1
                border.color: root.tint(tile.depth, tile.isFocus ? 0.9 : 0.18)
                opacity: root.runningLevel > 0 && !tile.isRunning ? 0.4 : (tile.needsHelper && !tile.isFocus ? 0.7 : 1)
                scale: tileMouse.pressed ? 0.95 : (tile.isFocus ? 1.0 : 0.985)

                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

                // depth meter: bars rising with the level
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
                        color: meterSlot.index < tile.depth ? root.tint(tile.depth, 0.95) : root.faint
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
                  trackColor: root.faint
                  RotationAnimator on rotation { running: tile.isRunning; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                }

                Text {
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(7)
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width - Style.space(4)
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: tile.modelData.name
                  color: tile.isFocus ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // small lock dot when this depth still needs the helper
                Rectangle {
                  visible: tile.needsHelper
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: Style.space(5)
                  width: Style.space(5); height: width; radius: width / 2
                  color: root.dim
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

          // -- what the focused depth does
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
                border.color: (root.focusInfo.root || !root.rootless) ? root.tint(root.focusLevel, 0.5) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                Text {
                  id: badge
                  anchors.centerIn: parent
                  text: !root.focusInfo.root && root.rootless ? "NO PASSWORD" : (root.helperReady ? "ROOT · ONE CLICK" : "NEEDS HELPER")
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

          // -- sketchy dive log
          Item {
            id: notes
            width: parent.width
            height: notesCol.implicitHeight + Style.space(30)

            SketchBox {
              anchors.fill: parent
              stroke: root.foreground
              strokeAlpha: 0.42
              seed: 11
              tapeColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
            }

            Column {
              id: notesCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(14)
              anchors.topMargin: Style.space(16)
              spacing: Style.space(2)

              Row {
                width: parent.width
                spacing: Style.space(8)
                Column {
                  Text {
                    id: logTitle
                    text: "dive log"
                    color: root.foreground
                    font.family: root.handFamily
                    font.pixelSize: Style.font.heading + 6
                    font.weight: Font.DemiBold
                  }
                  Squiggle {
                    width: logTitle.implicitWidth + Style.space(4)
                    height: Style.space(6)
                    stroke: root.accent
                    waves: 3.5
                  }
                }
                Text {
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(6)
                  visible: root.history.todayCount > 0
                  text: "today: " + root.history.todayCount + (root.history.todayCount === 1 ? " dive, " : " dives, ")
                    + Model.formatKiB(root.history.todayKiB) + " brought up"
                  color: root.dim
                  font.family: root.handFamily
                  font.pixelSize: Style.font.title + 1
                }
              }

              // live status / latest result
              Text {
                width: parent.width
                visible: text !== ""
                topPadding: Style.space(4)
                text: root.runningLevel > 0
                  ? "going down to " + Model.levelName(root.runningLevel).toLowerCase() + "…"
                  : (root.lastResult ? (root.lastResult.ok ? "✓ " : "✕ ") + Model.resultNote(root.lastResult) : "")
                color: root.runningLevel > 0 || (root.lastResult && root.lastResult.ok) ? root.accent : root.urgent
                font.family: root.handFamily
                font.pixelSize: Style.font.heading + 2
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
              }
              Text {
                width: parent.width
                visible: text !== "" && root.runningLevel === 0
                text: Model.helperNote(root.lastResult)
                color: root.dim
                font.family: root.handFamily
                font.pixelSize: Style.font.title + 1
                wrapMode: Text.WordWrap
              }

              Text {
                visible: root.history.recent.length === 0 && root.runningLevel === 0 && !root.lastResult
                topPadding: Style.space(4)
                text: "no dives yet. pick a depth up there ↑"
                color: root.dim
                font.family: root.handFamily
                font.pixelSize: Style.font.title + 2
              }

              Repeater {
                model: root.history.recent
                delegate: Row {
                  id: logRow
                  required property var modelData
                  required property int index
                  readonly property var line: Model.logLine(modelData, root.nowMs)
                  spacing: Style.space(8)
                  topPadding: index === 0 ? Style.space(4) : 0
                  opacity: 1 - index * 0.17

                  Text {
                    width: Style.space(44)
                    text: logRow.line.when
                    color: root.dim
                    font.family: root.handFamily
                    font.pixelSize: Style.font.title + 2
                  }
                  // hand-circled depth number
                  Item {
                    width: Style.space(18); height: width
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                      anchors.fill: parent
                      radius: width / 2
                      color: "transparent"
                      border.width: 1.2
                      border.color: root.tint(logRow.line.depth, 0.75)
                      rotation: -8
                    }
                    Text {
                      anchors.centerIn: parent
                      text: String(logRow.line.depth)
                      color: root.tint(logRow.line.depth, 1)
                      font.family: root.handFamily
                      font.pixelSize: Style.font.title + 1
                      font.weight: Font.Bold
                    }
                  }
                  Text {
                    width: Style.space(70)
                    text: logRow.line.name
                    color: root.foreground
                    font.family: root.handFamily
                    font.pixelSize: Style.font.title + 2
                  }
                  Text {
                    text: logRow.line.freed
                    color: root.accent
                    font.family: root.handFamily
                    font.pixelSize: Style.font.title + 2
                    font.weight: Font.DemiBold
                  }
                }
              }

              // the hint, with a doodled arrow
              Row {
                width: parent.width
                topPadding: Style.space(8)
                spacing: Style.space(4)
                Text {
                  id: arrow
                  text: "↳"
                  color: root.accent
                  font.family: root.handFamily
                  font.pixelSize: Style.font.heading + 2
                }
                Text {
                  width: parent.width - arrow.width - parent.spacing
                  text: Model.tip(root.mem, root.caps, root.focusLevel)
                  color: root.foreground
                  opacity: 0.85
                  wrapMode: Text.WordWrap
                  font.family: root.handFamily
                  font.pixelSize: Style.font.title + 2
                }
              }

              // one-time helper install, drawn like a pencilled button
              Item {
                visible: root.helperNeeded
                width: installLabel.implicitWidth + Style.space(26)
                height: installLabel.implicitHeight + Style.space(10)

                SketchBox {
                  anchors.fill: parent
                  stroke: installMouse.containsMouse ? root.accent : root.foreground
                  strokeAlpha: installMouse.containsMouse ? 0.9 : 0.5
                  roughness: 1.4
                  seed: 3
                  tape: false
                }
                Text {
                  id: installLabel
                  anchors.centerIn: parent
                  text: root.installingHelper ? "installing…"
                    : (root.caps && root.caps.helper === "outdated" ? "update root helper" : "install root helper")
                  color: installMouse.containsMouse ? root.accent : root.foreground
                  font.family: root.handFamily
                  font.pixelSize: Style.font.title + 3
                  font.weight: Font.DemiBold
                }
                MouseArea {
                  id: installMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.installHelper()
                }
              }
            }
          }
        }
      }
    }
  }
}
