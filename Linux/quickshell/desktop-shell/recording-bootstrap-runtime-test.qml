import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/panels/recording" as Recording

Item {
  id: root
  property string modePath: Quickshell.env("RECORDING_FIXTURE_MODE")
  property string countPath: Quickshell.env("RECORDING_FIXTURE_COUNT")
  property string activePath: Quickshell.env("RECORDING_FIXTURE_ACTIVE")
  property string fakePrepare: Qt.resolvedUrl("tests/fixtures/recording/fake-prepare").toString().replace("file://", "")
  property bool switched: false
  property int checks: 0

  Recording.Panel {
    id: panel
    prepareExecutable: root.fakePrepare
    initialPrepareInterval: 100
    recoveryPrepareInterval: 100
  }

  FileView {
    id: modeFile
    path: root.modePath
    preload: false
    blockWrites: false
    printErrors: false
  }

  Connections {
    target: panel
    function onPrepareErrorChanged() {
      if (!root.switched && panel.prepareError !== "") {
        root.switched = true
        modeFile.setText("success\n")
      }
    }
    function onRuntimeReadyChanged() {
      if (panel.runtimeReady) {
        console.log("Recording bootstrap fixture passed")
        Qt.exit(0)
      }
    }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      root.checks++
      if (root.checks >= 200) {
        console.error("Recording bootstrap fixture timed out", panel.prepareGeneration,
          panel.prepareFinalizedGeneration, panel.prepareInFlight, panel.prepareError)
        Qt.exit(1)
      }
    }
  }
}
