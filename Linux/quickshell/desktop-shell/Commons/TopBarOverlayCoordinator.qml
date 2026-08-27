pragma Singleton
import QtQuick

QtObject {
  property string activeId: ""
  property string persistentId: ""

  function claim(id, persistent) {
    var candidate = String(id || "")
    if (candidate === "") return false
    if (persistentId !== "" && persistentId !== candidate) return false
    activeId = candidate
    if (persistent === true) persistentId = candidate
    return true
  }

  function release(id) {
    var candidate = String(id || "")
    if (activeId !== candidate) return false
    activeId = ""
    if (persistentId === candidate) persistentId = ""
    return true
  }

  function reset() {
    activeId = ""
    persistentId = ""
  }
}
