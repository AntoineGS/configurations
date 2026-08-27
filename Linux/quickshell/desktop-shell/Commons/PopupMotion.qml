pragma Singleton
import QtQuick

QtObject {
  readonly property int surfaceOpenDuration: 360
  readonly property int surfaceCloseDuration: 320
  readonly property int overlayHeaderOpenDelay: 90
  readonly property int overlayHeaderOpenDuration: 160
  readonly property int overlayBodyOpenDelay: 140
  readonly property int overlayBodyOpenDuration: 180
  readonly property int overlayHeaderCloseDuration: 180
  readonly property int overlayBodyCloseDuration: 140

  readonly property int surfaceOpenEasing: Easing.OutCubic
  readonly property int surfaceCloseEasing: Easing.InOutCubic
  readonly property int overlayContentOpenEasing: Easing.OutQuad
  readonly property int overlayContentCloseEasing: Easing.InCubic
  readonly property int overlayScrimEasing: Easing.OutQuad
}
