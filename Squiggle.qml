import QtQuick 6.11

// Hand-drawn wavy underline.
Canvas {
  id: root
  property color stroke: "white"
  property real strokeAlpha: 0.7
  property real waves: 4
  implicitHeight: 6
  antialiasing: true
  onStrokeChanged: requestPaint()
  onWidthChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.strokeStyle = "rgba(" + Math.round(stroke.r * 255) + "," + Math.round(stroke.g * 255) + "," + Math.round(stroke.b * 255) + "," + strokeAlpha + ")"
    ctx.lineWidth = 1.5
    ctx.lineCap = "round"
    ctx.beginPath()
    var mid = height / 2
    ctx.moveTo(1, mid)
    for (var x = 1; x <= width - 1; x += 1.5) {
      ctx.lineTo(x, mid + Math.sin(x / width * Math.PI * 2 * waves) * (height / 2 - 1) * (0.7 + 0.3 * Math.sin(x * 0.7)))
    }
    ctx.stroke()
  }
}
