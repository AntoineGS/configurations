import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import "Model.js" as Model

SharedService {
  id: root

  readonly property bool capabilityAvailable: Pipewire.ready
  readonly property var sink: collecting && Pipewire.ready ? Pipewire.defaultAudioSink : null
  readonly property var source: collecting && Pipewire.ready ? Pipewire.defaultAudioSource : null
  readonly property bool outputAvailable: !!(root.sink && root.sink.audio)
  readonly property bool inputAvailable: !!(root.source && root.source.audio)
  readonly property real outputVolume: root.outputAvailable ? root.sink.audio.volume : 0
  readonly property real inputVolume: root.inputAvailable ? root.source.audio.volume : 0
  readonly property bool outputMuted: root.outputAvailable ? !!root.sink.audio.muted : false
  readonly property bool inputMuted: root.inputAvailable ? !!root.source.audio.muted : false
  readonly property bool anyAudible: (root.outputAvailable && !root.outputMuted)
    || (root.inputAvailable && !root.inputMuted)
  readonly property var remoteSummary: Model.remoteSummary(root.sink)

  PwObjectTracker {
    objects: [root.sink, root.source].filter(function(node) { return !!node })
  }
}
