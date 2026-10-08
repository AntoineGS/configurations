import QtQuick
import qs.Commons
import qs.Commons as Commons

ElevatedSurface {
  id: root

  color: Commons.Color.barPanels.background
  borderSpec: Border.surfaceSpec(
    "bar-panels",
    "border",
    Commons.Color.barPanels.border,
    Math.max(1, Style.space(2))
  )
  padding: Style.spacing.popupPadding
  radius: Style.cornerRadius
}
