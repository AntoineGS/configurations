import QtQuick
import Quickshell
import Quickshell.Io

import "plugins/osd"

ShellRoot {
  id: root

  Osd {
    id: osd
  }

  function screenState() {
    var names = []
    for (var i = 0; i < osd.screenList.length; i++) {
      names.push(String(osd.screenList[i].name || ""))
    }
    return JSON.stringify({
      focused: osd.focusedMonitorName,
      target: osd.targetScreen ? String(osd.targetScreen.name || "") : "",
      screens: names
    })
  }

  function setScreenFixture(mode) {
    if (mode === "empty") {
      osd.screenList = []
    } else if (mode === "available") {
      var available = []
      for (var i = 0; i < Quickshell.screens.length; i++) available.push(Quickshell.screens[i])
      osd.screenList = available
    } else {
      return "invalid"
    }
    return root.screenState()
  }

  function surfaceState() {
    return JSON.stringify({
      suppressed: osd.testSurfaceSuppressed,
      visible: osd.surfaceVisible,
      opened: osd.opened
    })
  }

  IpcHandler {
    target: "desktop.osd-test"

    function screenState(): string { return root.screenState() }
    function setScreenFixture(mode: string): string { return root.setScreenFixture(mode) }
    function surfaceState(): string { return root.surfaceState() }
  }
}
