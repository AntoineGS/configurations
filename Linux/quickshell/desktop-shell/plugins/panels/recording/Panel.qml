import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "desktop.recording"
  ipcTarget: "desktop.recording"
  manageIpc: false

  readonly property var recordingService: bar && bar.shell
    ? bar.shell.serviceFor("desktop.recording") : null
  readonly property bool loaded: recordingService ? recordingService.loaded : false
  readonly property bool recording: recordingService ? recordingService.recording : false
  readonly property string outputPath: recordingService ? recordingService.outputPath : ""

  ServiceConsumer {
    id: recordingConsumer
    service: root.recordingService
    active: true
  }

  visible: root.loaded && root.recording
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰑋"
    active: root.recording
    tooltipText: root.outputPath
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton && root.recordingService)
        root.recordingService.toggleRecording()
    }
  }
}
