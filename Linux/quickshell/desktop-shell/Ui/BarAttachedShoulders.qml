import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real bodyWidth: 0
  property real radius: Style.popupOuterRadius
  property color surfaceColor: Color.barPanels.background
  property real revealProgress: 1
  readonly property bool hovered: leftPointerArea.containsMouse || rightPointerArea.containsMouse

  width: root.bodyWidth + root.radius * 2
  height: root.radius
  opacity: root.revealProgress

  transform: Scale {
    origin.x: root.width / 2
    origin.y: 0
    xScale: 1
    yScale: root.revealProgress
  }

  Shape {
    width: root.radius
    height: root.radius
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.surfaceColor
      strokeWidth: 0

      PathSvg {
        path: "M 0 0 H " + root.radius + " V " + root.radius
          + " A " + root.radius + " " + root.radius + " 0 0 0 0 0 Z"
      }
    }
  }

  Shape {
    x: root.radius + root.bodyWidth
    width: root.radius
    height: root.radius
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.surfaceColor
      strokeWidth: 0

      PathSvg {
        path: "M " + root.radius + " 0 H 0 V " + root.radius
          + " A " + root.radius + " " + root.radius + " 0 0 1 " + root.radius + " 0 Z"
      }
    }
  }

  MouseArea {
    id: leftPointerArea
    width: root.radius
    height: root.radius
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onClicked: {}
  }

  MouseArea {
    id: rightPointerArea
    x: root.radius + root.bodyWidth
    width: root.radius
    height: root.radius
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onClicked: {}
  }
}
