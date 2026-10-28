import QtQuick 6.11

// Hand-drawn rectangle: every edge is stroked twice with small seeded wobbles,
// so it looks pencilled but stays identical between repaints. Optional strip
// of "tape" across the top-left corner.
Canvas {
  id: root

  property color stroke: "white"
  property real strokeAlpha: 0.55
  property real roughness: 2.2
  property int seed: 7
  property bool tape: true
  property color tapeColor: Qt.rgba(1, 1, 1, 0.12)

  onStrokeChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  antialiasing: true

  function rgba(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var s = seed
    function rand() { // mulberry32
      s = (s + 0x6D2B79F5) | 0
      var t = Math.imul(s ^ (s >>> 15), 1 | s)
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
    function j(k) { return (rand() - 0.5) * roughness * 2 * (k || 1) }

    var m = 3
    var pts = [[m, m], [width - m, m], [width - m, height - m], [m, height - m]]
    ctx.lineCap = "round"
    for (var pass = 0; pass < 2; pass++) {
      ctx.strokeStyle = rgba(stroke, pass === 0 ? strokeAlpha : strokeAlpha * 0.55)
      ctx.lineWidth = pass === 0 ? 1.4 : 0.9
      for (var e = 0; e < 4; e++) {
        var a = pts[e], b = pts[(e + 1) % 4]
        // overshoot the corners a little, like a quick pencil line
        var dx = b[0] - a[0], dy = b[1] - a[1]
        var len = Math.sqrt(dx * dx + dy * dy) || 1
        var ox = dx / len * 2.5, oy = dy / len * 2.5
        ctx.beginPath()
        ctx.moveTo(a[0] - ox + j(), a[1] - oy + j())
        ctx.quadraticCurveTo((a[0] + b[0]) / 2 + j(1.6), (a[1] + b[1]) / 2 + j(1.6), b[0] + ox + j(), b[1] + oy + j())
        ctx.stroke()
      }
    }

    if (tape) {
      ctx.save()
      ctx.translate(Math.min(46, width * 0.18), 4)
      ctx.rotate(-0.12)
      ctx.fillStyle = rgba(tapeColor, tapeColor.a)
      ctx.fillRect(-26, -7, 52, 14)
      ctx.restore()
    }
  }
}
