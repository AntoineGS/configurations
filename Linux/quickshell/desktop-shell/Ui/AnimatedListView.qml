import QtQuick
import qs.Commons

ListView {
  id: root

  property bool transitionsEnabled: true

  add: Transition {
    enabled: root.transitionsEnabled && Motion.enabled
    ParallelAnimation {
      NumberAnimation {
        property: "opacity"
        from: 0
        duration: Motion.normalDuration
        easing.type: Motion.effectEasing
      }
      NumberAnimation {
        property: "scale"
        from: 0.98
        to: 1
        duration: Motion.normalDuration
        easing.type: Motion.spatialEasing
      }
    }
  }

  remove: Transition {
    enabled: root.transitionsEnabled && Motion.enabled
    ParallelAnimation {
      NumberAnimation {
        property: "opacity"
        to: 0
        duration: Motion.fastDuration
        easing.type: Motion.exitEasing
      }
      NumberAnimation {
        property: "scale"
        to: 0.98
        duration: Motion.fastDuration
        easing.type: Motion.exitEasing
      }
    }
  }

  move: Transition {
    enabled: root.transitionsEnabled && Motion.enabled
    NumberAnimation {
      properties: "x,y"
      duration: Motion.spatialDuration
      easing.type: Motion.spatialEasing
    }
  }

  addDisplaced: Transition {
    enabled: root.transitionsEnabled && Motion.enabled
    NumberAnimation {
      properties: "x,y"
      duration: Motion.spatialDuration
      easing.type: Motion.spatialEasing
    }
  }

  displaced: Transition {
    enabled: root.transitionsEnabled && Motion.enabled
    NumberAnimation {
      properties: "x,y"
      duration: Motion.spatialDuration
      easing.type: Motion.spatialEasing
    }
  }
}
