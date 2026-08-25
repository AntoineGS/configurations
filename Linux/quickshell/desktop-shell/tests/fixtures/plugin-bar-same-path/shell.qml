import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  property string pluginPath: Quickshell.env("PLUGIN_BAR_PATH")
  property string resultPath: Quickshell.env("PLUGIN_BAR_RESULT")
  property int loadCount: 0
  property int destroyedCount: 0
  property var observedVersions: []
  property string configuredVersion: "1.0.0"

  FileView {
    id: resultFile
    path: root.resultPath
    atomicWrites: false
    blockWrites: false
    printErrors: false
  }

  Process {
    id: replaceProcess
    command: ["bash", "-c",
      "sleep 1; printf '%s\\n' 'import QtQuick' 'Item {' \" property string version: '2.0.0'\""
      + " ' property var harness: null' ' Component.onDestruction: if (harness) harness.destroyedCount++' '}' >\"$0\"",
      root.pluginPath]
    onExited: {
      if (Number(exitCode) !== 0) {
        resultFile.setText(JSON.stringify({ ok: false, error: "replacement failed" }))
        Qt.exit(1)
      }
      root.configuredVersion = "2.0.0"
      loader.active = false
      loader.source = ""
      Qt.callLater(function() {
        if (typeof Qt.clearComponentCache === "function") Qt.clearComponentCache()
        loader.source = "file://" + root.pluginPath
        loader.active = true
      })
    }
  }

  Loader {
    id: loader
    source: "file://" + root.pluginPath
    asynchronous: false
    onLoaded: {
      root.loadCount++
      item.version = root.configuredVersion
      var versions = root.observedVersions.slice(0)
      versions.push(String(item.version))
      root.observedVersions = versions
      item.harness = root
      if (root.loadCount === 1) replaceProcess.running = true
      else if (root.loadCount === 2) {
        if (root.destroyedCount !== 1 || root.observedVersions[1] !== "2.0.0") {
          resultFile.setText(JSON.stringify({ ok: false, error: "same-path item was not recycled",
            loadCount: root.loadCount, destroyedCount: root.destroyedCount,
            observedVersions: root.observedVersions }))
          Qt.exit(1)
          return
        }
        resultFile.setText(JSON.stringify({ ok: true, loadCount: root.loadCount,
          destroyedCount: root.destroyedCount, observedVersions: root.observedVersions }))
        Qt.exit(0)
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: false
    onTriggered: {
      resultFile.setText(JSON.stringify({ ok: false, error: "bar fixture timeout" }))
      Qt.exit(1)
    }
  }
}
