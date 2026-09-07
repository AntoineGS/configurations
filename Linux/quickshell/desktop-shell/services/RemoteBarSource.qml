import QtQuick
import Quickshell.Io
import "RemoteBarModel.js" as RemoteBarModel

QtObject {
  id: root

  required property string host
  property string connectionTarget: ""
  property bool active: false
  property var snapshot: null
  property double snapshotReceivedAt: 0
  property string lastError: ""
  property double nowSeconds: Math.floor(Date.now() / 1000)
  property int generation: 0
  property bool fetchQueued: false

  readonly property var freshness: RemoteBarModel.freshness(snapshot, nowSeconds, snapshotReceivedAt, 30, 60)
  readonly property string health: freshness.state
  readonly property int snapshotAgeSeconds: freshness.ageSeconds
  readonly property bool warning: active && health !== "fresh"
  readonly property var agents: RemoteBarModel.widget(snapshot, "agents")
  readonly property var audio: RemoteBarModel.widget(snapshot, "audio")
  readonly property var disk: RemoteBarModel.widget(snapshot, "disk")
  readonly property var vm: RemoteBarModel.widget(snapshot, "vm")

  function fetchNow() {
    if (!active || connectionTarget === "") return
    if (fetchProcess.running) {
      fetchQueued = true
      return
    }
    fetchQueued = false
    fetchProcess.requestGeneration = generation
    fetchProcess.requestTarget = connectionTarget
    fetchProcess.requestHost = host
    fetchProcess.command = ["desktop-remote-bar", "fetch", connectionTarget]
    fetchProcess.running = true
  }

  onActiveChanged: {
    generation++
    fetchQueued = false
    if (active) {
      nowSeconds = Math.floor(Date.now() / 1000)
      Qt.callLater(root.fetchNow)
    }
  }
  onConnectionTargetChanged: {
    generation++
    snapshot = null
    snapshotReceivedAt = 0
    lastError = ""
    fetchQueued = false
    if (active) Qt.callLater(root.fetchNow)
  }
  Component.onCompleted: {
    if (active) Qt.callLater(root.fetchNow)
  }

  property Process fetchProcess: Process {
    property int requestGeneration: -1
    property string requestTarget: ""
    property string requestHost: ""
    stdout: StdioCollector {
      id: fetchStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: fetchStderr
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) {
      // Destination alone cannot reject a reply from an earlier A -> B -> A request.
      if (root.active && requestGeneration === root.generation
          && requestTarget === root.connectionTarget && requestHost === root.host) {
        if (Number(exitCode) !== 0 || Number(exitStatus) !== 0) {
          root.lastError = String(fetchStderr.text || "Remote snapshot read failed").trim().slice(0, 240)
        } else {
          var parsed = RemoteBarModel.parseSnapshot(fetchStdout.text, requestHost)
          if (parsed) {
            root.snapshot = parsed
            root.snapshotReceivedAt = Math.floor(Date.now() / 1000)
            root.nowSeconds = root.snapshotReceivedAt
            root.lastError = ""
          } else root.lastError = "Remote snapshot is invalid"
        }
      }
      if (root.fetchQueued) {
        root.fetchQueued = false
        Qt.callLater(root.fetchNow)
      }
    }
  }

  property Timer fetchTimer: Timer {
    interval: 10000
    running: root.active
    repeat: true
    onTriggered: root.fetchNow()
  }

  property Timer clockTimer: Timer {
    interval: 1000
    running: root.active
    repeat: true
    onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
  }
}
