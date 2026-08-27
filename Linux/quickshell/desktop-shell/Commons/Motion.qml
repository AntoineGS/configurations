pragma Singleton
import QtQuick

QtObject {
  property bool enabled: true

  readonly property int fastDuration: 140
  readonly property int normalDuration: 160
  readonly property int spatialDuration: 220
  readonly property int popupOpenDuration: 360
  readonly property int popupCloseDuration: 320

  readonly property int spatialEasing: Easing.OutCubic
  readonly property int effectEasing: Easing.OutQuad
  readonly property int exitEasing: Easing.InCubic
  readonly property int popupOpenEasing: Easing.OutCubic
  readonly property int popupCloseEasing: Easing.InOutCubic
}
