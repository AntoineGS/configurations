import QtQuick
import QtQuick.Effects
import qs.Commons

BorderSurface {
  id: root

  property bool revealed: false
  property real entranceX: 0
  property real entranceY: 0
  property real revealProgress: 0
  property bool motionEnabled: true
  property real concealedScale: 0.97
  property real concealedXScale: concealedScale
  property real concealedYScale: concealedScale
  property real scaleOriginX: width / 2
  property real scaleOriginY: height / 2
  property int motionDuration: Motion.fastDuration
  property int revealDuration: motionDuration
  property int concealDuration: motionDuration
  property int revealEasing: Motion.spatialEasing
  property int concealEasing: Motion.spatialEasing
  property int shadowBlurMax: 24
  property real shadowBlurAmount: 0.7
  property real shadowOpacityAmount: 0.38
  property color shadowTint: "#000000"
  property real shadowOffsetY: 4
  property real shadowScaleAmount: 1.0
  property rect effectPaddingRect: Qt.rect(0, 0, 0, 0)
  property bool _completed: false

  opacity: revealProgress

  transform: [
    Scale {
      origin.x: root.scaleOriginX
      origin.y: root.scaleOriginY
      xScale: root.concealedXScale + root.revealProgress * (1 - root.concealedXScale)
      yScale: root.concealedYScale + root.revealProgress * (1 - root.concealedYScale)
    },
    Translate {
      x: (1 - root.revealProgress) * root.entranceX
      y: (1 - root.revealProgress) * root.entranceY
    }
  ]

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
    enabled: root._completed && root.motionEnabled && Motion.enabled
    NumberAnimation {
      duration: root.revealed ? root.revealDuration : root.concealDuration
      easing.type: root.revealed ? root.revealEasing : root.concealEasing
    }
  }

  function settleReveal() {
    if (!root.motionEnabled || !Motion.enabled) {
      revealProgress = revealed ? 1 : 0
    }
  }

  onMotionEnabledChanged: settleReveal()

  Connections {
    target: Motion
    function onEnabledChanged() {
      if (!Motion.enabled) Qt.callLater(root.settleReveal)
    }
  }
}
