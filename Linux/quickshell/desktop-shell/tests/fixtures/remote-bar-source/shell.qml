import QtQuick
import Quickshell
import "services"

ShellRoot {
  id: test
  property int step: 0
  property int launches: 0
  property double deadline: Date.now() + 15000
  property string expected: ""
  property double idleUntil: 0

  RemoteBarSource { id: source; host: "DESKTOP-E07VTRN" }
  RemoteBarSource { id: other; host: "OTHER"; connectionTarget: "wrong" }

  function check(condition, message) {
    if (!condition) {
      console.error("FAIL step " + step + ": " + message)
      Qt.exit(1)
      throw new Error(message)
    }
  }

  Connections {
    target: source.fetchProcess
    function onStarted() { test.launches++ }
  }
  Connections {
    target: source
    function onSnapshotChanged() {
      if (source.snapshot)
        test.check(source.disk.target + source.disk.serial === test.expected, "obsolete reply applied")
    }
  }

  Timer {
    interval: 20
    running: true
    repeat: true
    onTriggered: {
      test.check(Date.now() < test.deadline, "timed out")
      switch (test.step) {
      case 0:
        source.fetchNow()
        test.check(test.launches === 0 && !source.warning, "inactive source fetched or warned")
        source.connectionTarget = "A"
        source.active = true
        test.expected = "A2"
        test.step++
        break
      case 1:
        if (test.launches !== 1) return
        source.connectionTarget = "B"
        source.connectionTarget = "A"
        test.step++
        break
      case 2:
        if (!source.snapshot) return
        test.check(test.launches === 2 && source.health === "fresh", "queued A-B-A refresh")
        test.expected = "A4"
        source.fetchNow()
        test.step++
        break
      case 3:
        if (test.launches !== 3) return
        source.fetchNow()
        source.fetchNow()
        source.active = false
        source.nowSeconds = 0
        source.active = true
        test.check(source.nowSeconds > 0, "clock not refreshed on activation")
        test.step++
        break
      case 4:
        if (source.disk.serial !== 4) return
        test.check(test.launches === 4, "busy requests not coalesced")
        source.fetchNow()
        test.step++
        break
      case 5:
        if (test.launches !== 5) return
        source.fetchNow()
        source.active = false
        test.idleUntil = Date.now() + 700
        test.step++
        break
      case 6:
        if (Date.now() < test.idleUntil) return
        test.check(test.launches === 5 && source.disk.serial === 4 && !source.warning,
          "deactivated source continued work or applied reply")
        source.connectionTarget = "error"
        test.check(source.snapshot === null && source.snapshotReceivedAt === 0, "transport retained snapshot")
        source.active = true
        test.step++
        break
      case 7:
        if (test.launches !== 6) return
        source.connectionTarget = "B"
        test.expected = "B1"
        test.step++
        break
      case 8:
        test.check(source.lastError === "", "obsolete transport error applied")
        if (!source.snapshot) return
        test.check(source.disk.target === "B", "new destination not fetched promptly")
        source.connectionTarget = "error"
        test.step++
        break
      case 9:
        if (!source.lastError) return
        test.check(source.lastError.indexOf("transport failed") !== -1 && source.warning, "missing fetch error")
        source.connectionTarget = "invalid"
        test.step++
        break
      case 10:
        if (!source.lastError) return
        test.check(source.snapshot === null, "invalid JSON accepted")
        source.connectionTarget = "wrong"
        other.active = true
        test.step++
        break
      case 11:
        if (!source.lastError || !other.snapshot) return
        test.check(source.snapshot === null && other.snapshot.host === "OTHER", "canonical host validation/isolation")
        source.connectionTarget = "A"
        test.expected = "A6"
        test.step++
        break
      case 12:
        if (!source.snapshot) return
        test.check(source.lastError === "" && other.snapshot.host === "OTHER", "recovery or source isolation")
        console.log("RemoteBarSource runtime fixture passed")
        Qt.quit()
      }
    }
  }
}
