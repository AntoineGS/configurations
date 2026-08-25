import QtQuick
import qs.Commons

ElevatedSurface {
  id: root

  color: Color.barPanels.background
  borderSpec: Border.surfaceSpec(
    "bar-panels",
    "border",
    Color.barPanels.border,
    Math.max(1, Style.space(2))
  )
  padding: Style.spacing.popupPadding
  radius: Style.cornerRadius
}
