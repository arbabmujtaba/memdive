import QtQuick 6.11

// Round "porthole" gauge: water fills it to `value` (0..1) with two drifting
// waves. While `busy`, bubbles rise through the water.
Canvas {
  id: root

  property real value: 0
  property bool animating: true
  property bool busy: false
  property color waterColor: "#7fbbb3"
  property color rimColor: Qt.rgba(1, 1, 1, 0.12)
  property color glassColor: Qt.rgba(1, 1, 1, 0.03)
  property real rimWidth: Math.max(2, width * 0.045)

  property real shownValue: value
  property real phase: 0
  property real bubbleTime: 0

  Behavior on shownValue { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }

  NumberAnimation on phase {
    running: root.animating && root.visible
    from: 0; to: Math.PI * 2
    duration: 3200
    loops: Animation.Infinite
  }
  NumberAnimation on bubbleTime {
    running: root.busy && root.visible
    from: 0; to: 1
    duration: 1600
    loops: Animation.Infinite
  }

  onShownValueChanged: requestPaint()
  onPhaseChanged: requestPaint()
  onBubbleTimeChanged: requestPaint()
  onWaterColorChanged: requestPaint()
  onWidthChanged: requestPaint()

  antialiasing: true
  renderStrategy: Canvas.Cooperative

  function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var size = Math.min(width, height)
    var cx = width / 2, cy = height / 2
    var r = size / 2 - rimWidth
    var level = Math.max(0, Math.min(1, shownValue))
    var surface = cy + r - level * r * 2
    var amp = Math.max(1.2, r * 0.06) * (level > 0.02 && level < 0.98 ? 1 : 0.3)

    ctx.save()
    ctx.beginPath()
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.closePath()
    ctx.fillStyle = rgba(glassColor, glassColor.a)
    ctx.fill()
    ctx.clip()

    function wave(offset, a, alpha) {
      ctx.beginPath()
      ctx.moveTo(cx - r - 2, cy + r + 2)
      for (var x = -r - 2; x <= r + 2; x += 2) {
        var y = surface + Math.sin(x / r * 2.4 + phase + offset) * a
        ctx.lineTo(cx + x, y)
      }
      ctx.lineTo(cx + r + 2, cy + r + 2)
      ctx.closePath()
      ctx.fillStyle = rgba(waterColor, alpha)
      ctx.fill()
    }
    wave(Math.PI * 0.8, amp * 0.8, 0.22)
    wave(0, amp, 0.5)

    if (busy) {
      for (var i = 0; i < 7; i++) {
        var t = (bubbleTime + i / 7) % 1
        var bx = cx + Math.sin(i * 2.1 + t * 5) * r * 0.45
        var by = cy + r - t * r * 2
        var br = Math.max(1.2, r * (0.035 + (i % 3) * 0.015))
        ctx.beginPath()
        ctx.arc(bx, by, br, 0, Math.PI * 2)
        ctx.strokeStyle = rgba(waterColor, 0.85 * (1 - t))
        ctx.lineWidth = 1
        ctx.stroke()
      }
    }
    ctx.restore()

    // glass glint
    ctx.beginPath()
    ctx.arc(cx, cy, r * 0.78, Math.PI * 1.08, Math.PI * 1.42)
    ctx.strokeStyle = "rgba(255,255,255,0.10)"
    ctx.lineWidth = Math.max(1.5, r * 0.06)
    ctx.lineCap = "round"
    ctx.stroke()

    // rim
    ctx.beginPath()
    ctx.arc(cx, cy, r + rimWidth / 2, 0, Math.PI * 2)
    ctx.strokeStyle = rgba(rimColor, rimColor.a)
    ctx.lineWidth = rimWidth
    ctx.stroke()
  }
}
