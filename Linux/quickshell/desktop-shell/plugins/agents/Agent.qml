import QtQuick
import Quickshell.Io

// One provider's usage record, read from the repository-owned state path.
// Collection and authentication stay outside the panel.
Item {
  id: root
  visible: false

  property string agentId: ""
  property string path: ""
  property bool active: true
  property int generation: 0
  property var record: null

  FileView {
    id: recordFile
    path: root.path
    watchChanges: root.active
    printErrors: false
    onFileChanged: if (root.active) reload()
    onLoaded: if (root.active) root.parse(text())
    onLoadFailed: if (root.active) root.record = null
  }

  onActiveChanged: if (root.active) recordFile.reload()

  function parse(content) {
    if (!root.active) return
    try {
      var parsed = JSON.parse(String(content || ""))
      root.record = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      console.warn("agents", "Ignoring bad usage record", root.path, e)
      root.record = null
    }
  }
}
