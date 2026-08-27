pragma Singleton
import QtQuick

QtObject {
  property string activeId: ""

  function claim(id) {
    var candidate = String(id || "")
    if (candidate === "") return false
    activeId = candidate
    return true
  }

  function release(id) {
    if (activeId !== String(id || "")) return false
    activeId = ""
    return true
  }

  function reset() {
    activeId = ""
  }
}
