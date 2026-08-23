import QtQuick
import QtQuick.Effects

BorderSurface {
  id: root

  property bool revealed: false
  property real entranceX: 0
  property real entranceY: 0
  property real revealProgress: 0
  property bool motionEnabled: true
  property real concealedScale: 0.97
  property int motionDuration: 140
  property int shadowBlurMax: 24
  property real shadowBlurAmount: 0.7
  property real shadowOpacityAmount: 0.38
  property color shadowTint: "#000000"
  property real shadowOffsetY: 4
  property real shadowScaleAmount: 1.0
  property rect effectPaddingRect: Qt.rect(0, 0, 0, 0)
  property bool _completed: false

  opacity: revealProgress
  scale: concealedScale + revealProgress * (1 - concealedScale)
  transformOrigin: Item.Center

  transform: Translate {
    x: (1 - root.revealProgress) * root.entranceX
    y: (1 - root.revealProgress) * root.entranceY
  }

  layer.enabled: true
  layer.effect: MultiEffect {
    shadowEnabled: true
    blurMax: root.shadowBlurMax
    shadowBlur: root.shadowBlurAmount
    shadowOpacity: root.shadowOpacityAmount
    shadowColor: root.shadowTint
    shadowVerticalOffset: root.shadowOffsetY
    shadowScale: root.shadowScaleAmount
    paddingRect: root.effectPaddingRect
  }

  onRevealedChanged: {
    if (_completed) revealProgress = revealed ? 1 : 0
  }

  Component.onCompleted: {
    _completed = true
    if (revealed) Qt.callLater(function() { root.revealProgress = 1 })
  }

  Behavior on revealProgress {
    enabled: root._completed && root.motionEnabled
    NumberAnimation { duration: root.motionDuration; easing.type: Easing.OutCubic }
  }
}
