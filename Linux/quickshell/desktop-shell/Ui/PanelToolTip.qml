import QtQuick
import QtQuick.Controls
import qs.Commons

// Styled wrapper around Qt Quick Controls ToolTip. Drop-in: declare inside
// the hovered item and bind `visible` to the hover state, e.g.
//   PanelToolTip {
//     visible: mouse.containsMouse
//     text: "Forget network"
//   }
//
// Defaults pull from [tooltip] in shell.toml via Color.tooltip.*. Override
// the panel* properties per-instance only when you need a tooltip that
// intentionally diverges from the theme.
//
// Property names are prefixed `panel*` to avoid clashing with ToolTip's
// built-in `background`/`font` properties.
ToolTip {
  id: root

  property color panelForeground: Color.tooltip.text
  property color panelBackground: Color.tooltip.background
  property color panelBorder: Color.tooltip.border
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.bodySmall
  property int elevationInset: Style.space(24)

  readonly property var panelBorderSpec: Border.localOrSurfaceSpec("tooltip", "border", panelBorder, Color.tooltip.border, Style.normalBorderWidth)

  delay: 400
  leftPadding: elevationInset + Border.left(panelBorderSpec) + Style.spacing.controlPaddingX
  rightPadding: elevationInset + Border.right(panelBorderSpec) + Style.spacing.controlPaddingX
  topPadding: elevationInset + Border.top(panelBorderSpec) + Style.spacing.controlPaddingY
  bottomPadding: elevationInset + Border.bottom(panelBorderSpec) + Style.spacing.controlPaddingY

  background: ElevatedSurface {
    x: root.elevationInset
    y: root.elevationInset
    width: root.width - root.elevationInset * 2
    height: root.height - root.elevationInset * 2
    color: root.panelBackground
    borderSpec: root.panelBorderSpec
    radius: Style.cornerRadius
    revealed: root.visible
    entranceY: -Style.space(6)
  }

  contentItem: Text {
    text: root.text
    color: root.panelForeground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }
}
