pragma Singleton
import QtQuick

QtObject {
  readonly property int surfaceOpenDuration: 360
  readonly property int surfaceCloseDuration: 320
  readonly property int menuSearchOpenDelay: 90
  readonly property int menuSearchOpenDuration: 160
  readonly property int menuResultsOpenDelay: 140
  readonly property int menuResultsOpenDuration: 180
  readonly property int menuSearchCloseDuration: 180
  readonly property int menuResultsCloseDuration: 140

  readonly property int surfaceOpenEasing: Easing.OutCubic
  readonly property int surfaceCloseEasing: Easing.InOutCubic
  readonly property int menuContentOpenEasing: Easing.OutQuad
  readonly property int menuContentCloseEasing: Easing.InCubic
  readonly property int menuScrimEasing: Easing.OutQuad
}
