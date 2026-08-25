import QtQuick
import QtQuick.Layouts
import qs.Commons

WidgetButton {
  id: root

  property string iconText: ""
  property string valueText: ""
  property bool valueIsIcon: false
  property real iconSize: bar && bar.iconFontSize ? bar.iconFontSize : Style.bar.iconFont
  property real valueSize: fontSize
  property real contentSpacing: spaceMetrics.advanceWidth / 2
  readonly property bool metricMode: iconText !== "" || valueText !== ""
  readonly property real metricHorizontalPadding: Math.max(0, (Style.bar.iconSlot - Style.bar.iconCanvas) / 2)

  labelVisible: !metricMode
  hasVisualContent: metricMode || text !== ""
  fixedWidth: metricMode && !vertical ? content.implicitWidth + metricHorizontalPadding * 2 : -1

  TextMetrics {
    id: spaceMetrics
    text: " "
    font.family: root.fontFamily
    font.pixelSize: root.valueSize
    font.weight: root.fontWeight
  }

  RowLayout {
    id: content
    visible: root.metricMode
    anchors.centerIn: parent
    spacing: root.iconText !== "" && root.valueText !== "" ? root.contentSpacing : 0

    Text {
      visible: root.iconText !== ""
      text: root.iconText
      color: root.contentColor
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      font.weight: root.fontWeight
      renderType: Text.NativeRendering
      Layout.alignment: Qt.AlignVCenter
    }

    Text {
      visible: root.valueText !== ""
      text: root.valueText
      color: root.contentColor
      font.family: root.fontFamily
      font.pixelSize: root.valueIsIcon ? root.iconSize : root.valueSize
      font.weight: root.fontWeight
      renderType: Text.NativeRendering
      Layout.alignment: Qt.AlignVCenter
    }
  }
}
