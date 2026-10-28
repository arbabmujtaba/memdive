import QtQuick 6.11

// Circular gauge: a faint track with an animated arc for `value` (0..1) and
// an optional second, thinner arc for `secondary` (e.g. cache share).
Canvas {
  id: root

  property real value: 0
  property real secondary: 0
  property real thickness: Math.max(2, width * 0.1)
  property color trackColor: Qt.rgba(1, 1, 1, 0.1)
  property color arcColor: "white"
  property color secondaryColor: Qt.rgba(1, 1, 1, 0.3)
  property bool animate: true

  property real shownValue: value
  property real shownSecondary: secondary

  Behavior on shownValue {
    enabled: root.animate
    NumberAnimation { duration: 650; easing.type: Easing.OutCubic }
  }
  Behavior on shownSecondary {
    enabled: root.animate
    NumberAnimation { duration: 650; easing.type: Easing.OutCubic }
  }

  onShownValueChanged: requestPaint()
  onShownSecondaryChanged: requestPaint()
  onArcColorChanged: requestPaint()
  onTrackColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  antialiasing: true
  renderStrategy: Canvas.Cooperative

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var size = Math.min(width, height)
    var cx = width / 2
    var cy = height / 2
    var r = size / 2 - thickness / 2
    var start = -Math.PI / 2
    ctx.lineCap = "round"

    ctx.beginPath()
    ctx.lineWidth = thickness
    ctx.strokeStyle = trackColor
    ctx.arc(cx, cy, r, 0, Math.PI * 2)
    ctx.stroke()

    var used = Math.max(0, Math.min(1, shownValue))
    var extra = Math.max(0, Math.min(1 - used, shownSecondary))
    if (extra > 0.004) {
      ctx.beginPath()
      ctx.lineWidth = thickness * 0.55
      ctx.strokeStyle = secondaryColor
      ctx.arc(cx, cy, r, start + used * Math.PI * 2, start + (used + extra) * Math.PI * 2)
      ctx.stroke()
    }
    if (used > 0.004) {
      ctx.beginPath()
      ctx.lineWidth = thickness
      ctx.strokeStyle = arcColor
      ctx.arc(cx, cy, r, start, start + used * Math.PI * 2)
      ctx.stroke()
    }
  }
}
