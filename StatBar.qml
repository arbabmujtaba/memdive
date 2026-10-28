import QtQuick 6.11
import qs.Commons

// Labelled thin progress bar used in the popup's stats column.
Column {
  id: stat

  property string label: ""
  property string value: ""
  property real fraction: 0
  property color barColor: Color.foreground
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  width: parent ? parent.width : 0
  spacing: Style.space(3)

  Item {
    width: parent.width
    height: labelText.implicitHeight

    Text {
      id: labelText
      text: stat.label
      color: stat.dim
      font.family: stat.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.right: parent.right
      text: stat.value
      color: stat.foreground
      font.family: stat.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    width: parent.width
    height: Style.space(4)
    radius: height / 2
    color: Qt.rgba(stat.foreground.r, stat.foreground.g, stat.foreground.b, 0.08)

    Rectangle {
      width: Math.max(height, parent.width * Math.max(0, Math.min(1, stat.fraction)))
      height: parent.height
      radius: height / 2
      color: stat.barColor
      Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
    }
  }
}
