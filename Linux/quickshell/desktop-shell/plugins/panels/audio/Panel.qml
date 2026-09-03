import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.audio"
  ipcTarget: "desktop.audio"
  property var pluginRegistry: null

  readonly property bool capabilityAvailable: Pipewire.ready
  readonly property var nodes: capabilityAvailable && Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var sink: capabilityAvailable ? Pipewire.defaultAudioSink : null
  readonly property var source: capabilityAvailable ? Pipewire.defaultAudioSource : null
  readonly property color foreground: panelForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var candidateSinks: {
    var result = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && node.isSink && !node.isStream) result.push(node)
    }
    return result
  }
  readonly property var candidateSources: {
    var result = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && !node.isSink && !node.isStream && Model.isAudioSource(node)) result.push(node)
    }
    return result
  }
  readonly property var candidateStreams: {
    var result = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && node.isStream && Model.isPlaybackStream(node) && node.audio) result.push(node)
    }
    return result
  }

  function reportCapability() {
    var registry = pluginRegistry || (bar && bar.shell ? bar.shell.pluginRegistry : null)
    if (!registry) return
    var scope = "capability:panel:" + moduleName
    if (capabilityAvailable) registry.clearPluginError(moduleName, scope)
    else registry.recordPluginError(moduleName, "PipeWire capability unavailable", scope)
  }

  property var displaySinks: []
  property var displaySources: []
  property var displayStreams: []
  property string focusSection: "output"
  property int selectedIndex: -1
  property bool cursorActive: false
  readonly property bool outputAvailable: !!(sink && sink.audio)
  readonly property bool inputAvailable: !!(source && source.audio)
  readonly property real outputVolume: outputAvailable ? sink.audio.volume : 0
  readonly property real inputVolume: inputAvailable ? source.audio.volume : 0
  readonly property bool outputMuted: outputAvailable ? sink.audio.muted : false
  readonly property bool inputMuted: inputAvailable ? source.audio.muted : false
  readonly property bool anyAudible: (outputAvailable && !outputMuted) || (inputAvailable && !inputMuted)
  readonly property var remoteSummary: ({
    available: root.outputAvailable,
    icon: root.icon,
    volumePercent: Math.round(root.outputVolume * 100),
    muted: root.outputMuted,
    deviceLabel: root.outputAvailable ? root.nodeLabel(root.sink) : "",
    tooltip: root.outputAvailable
      ? (root.outputMuted ? "Muted" : "Volume: " + Math.round(root.outputVolume * 100) + "%")
        + (root.nodeLabel(root.sink) !== "" ? "\n" + root.nodeLabel(root.sink) : "")
      : "Audio unavailable"
  })
  readonly property string icon: {
    if (!sink || !sink.audio) return ""
    if (Model.isHeadphones(sink)) return "󰋋"
    if (outputMuted) return ""
    if (outputVolume >= 0.67) return ""
    if (outputVolume >= 0.34) return ""
    if (outputVolume > 0) return ""
    return ""
  }

  function refreshRows() {
    if (!opened) return
    displaySinks = Model.listSnapshot(candidateSinks)
    displaySources = Model.listSnapshot(candidateSources)
    displayStreams = Model.listSnapshot(candidateStreams)
    clampCursor()
  }

  function sectionCount(section) {
    if (section === "output") return displaySinks.length
    if (section === "input") return displaySources.length
    if (section === "streams") return displayStreams.length
    return 0
  }

  function visibleSections() {
    var sections = []
    if (outputAvailable || displaySinks.length > 0) sections.push("output")
    if (inputAvailable || displaySources.length > 0) sections.push("input")
    if (displayStreams.length > 0) sections.push("streams")
    return sections
  }

  function clampCursor() {
    var sections = visibleSections()
    if (sections.length === 0) return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = -1
      return
    }
    var minimum = focusSection === "streams" ? 0 : -1
    var maximum = sectionCount(focusSection) - 1
    selectedIndex = Math.max(minimum, Math.min(maximum, selectedIndex))
  }

  function moveCursor(delta) {
    var sections = visibleSections()
    if (sections.length === 0) return
    var sectionIndex = sections.indexOf(focusSection)
    if (sectionIndex < 0) sectionIndex = 0
    var minimum = focusSection === "streams" ? 0 : -1
    var maximum = sectionCount(focusSection) - 1

    if (delta > 0 && selectedIndex < maximum) {
      selectedIndex++
      return
    }
    if (delta < 0 && selectedIndex > minimum) {
      selectedIndex--
      return
    }

    var nextIndex = sectionIndex + (delta > 0 ? 1 : -1)
    if (nextIndex < 0 || nextIndex >= sections.length) return
    focusSection = sections[nextIndex]
    selectedIndex = focusSection === "streams" ? 0 : -1
  }

  function setVolume(node, value) {
    if (!node || node.id === undefined) return
    var next = Math.max(0, Math.min(1.5, Number(value)))
    if (!isFinite(next)) return
    Quickshell.execDetached([
      "desktop-connectivity-action", "audio", "set-volume", String(node.id), String(next)
    ])
  }

  function setDefault(node, input) {
    if (!node || node.id === undefined || !node.name) return
    Quickshell.execDetached([
      "desktop-connectivity-action",
      "audio",
      input ? "set-default-input" : "set-default-output",
      String(node.id),
      String(node.name)
    ])
  }

  function toggleMute(input) {
    var node = input ? source : sink
    if (!node || node.id === undefined) return
    Quickshell.execDetached([
      "desktop-connectivity-action",
      "audio",
      input ? "toggle-input-mute" : "toggle-output-mute",
      String(node.id)
    ])
  }

  function toggleAllMute() {
    var shouldMute = anyAudible
    if (outputAvailable && outputMuted !== shouldMute) toggleMute(false)
    if (inputAvailable && inputMuted !== shouldMute) toggleMute(true)
  }

  function activateCursor() {
    if (focusSection === "output") {
      if (selectedIndex < 0) toggleMute(false)
      else setDefault(displaySinks[selectedIndex], false)
    } else if (focusSection === "input") {
      if (selectedIndex < 0) toggleMute(true)
      else setDefault(displaySources[selectedIndex], true)
    }
  }

  function outputVolumeName(value, muted) {
    return Model.outputVolumeName(value, muted)
  }

  function nodeLabel(node) { return Model.nodeLabel(node) }
  function sinkGlyph(node) { return Model.sinkGlyph(node) }
  function sourceGlyph(node) { return Model.sourceGlyph(node) }
  function streamLabel(node) { return Model.streamLabel(node) }

  onOpenedChanged: {
    if (opened) {
      refreshRows()
      focusSection = "output"
      selectedIndex = -1
      cursorActive = false
    } else {
      displaySinks = []
      displaySources = []
      displayStreams = []
    }
  }

  onCandidateSinksChanged: if (opened) refreshTimer.restart()
  onCandidateSourcesChanged: if (opened) refreshTimer.restart()
  onCandidateStreamsChanged: if (opened) refreshTimer.restart()
  onPluginRegistryChanged: reportCapability()
  onBarChanged: reportCapability()
  onCapabilityAvailableChanged: reportCapability()
  Component.onCompleted: reportCapability()

  visible: capabilityAvailable
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  PwObjectTracker { objects: root.candidateSinks }
  PwObjectTracker { objects: root.candidateSources }
  PwObjectTracker { objects: root.candidateStreams }

  Timer {
    id: refreshTimer
    interval: 80
    repeat: false
    onTriggered: root.refreshRows()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleAllMute()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!root.outputAvailable) return
      root.setVolume(root.sink, root.outputVolume + (delta > 0 ? 0.05 : -0.05))
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0 && root.focusSection !== "streams") root.setVolume(
          root.focusSection === "input" ? root.source : root.sink,
          (root.focusSection === "input" ? root.inputVolume : root.outputVolume) + dx * 0.05)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: scrollArea.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, masterSwitch.implicitHeight)

            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.icon
              color: root.panelSecondary
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              opacity: root.outputMuted ? 0.5 : 1.0
            }

            ToggleSwitch {
              id: masterSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.anyAudible
              hasCursor: root.cursorActive && root.focusSection === "header"
              foreground: root.foreground
              onHovered: function(hovered) { if (hovered) { root.cursorActive = true; root.focusSection = "header" } }
              onToggled: root.toggleAllMute()

              PanelToolTip {
                visible: masterSwitch.containsMouse
                text: root.anyAudible ? "Mute audio" : "Unmute audio"
                fontFamily: root.fontFamily
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: masterSwitch.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Audio"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: root.outputVolumeName(root.outputVolume, root.outputMuted).toUpperCase()
                color: root.panelSecondary
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.outputAvailable || root.displaySinks.length > 0

            Item {
              width: parent.width
              implicitHeight: Math.max(outputHeader.implicitHeight, outputPercent.implicitHeight)
              PanelSectionHeader {
                id: outputHeader
                text: "OUTPUT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Text {
                id: outputPercent
                anchors.right: parent.right
                text: Math.round(root.outputVolume * 100) + "%"
                color: root.panelSecondary
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            CursorSurface {
              width: parent.width
              implicitHeight: outputSlider.implicitHeight + Style.space(8)
              hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex < 0
              foreground: root.foreground
              PanelSlider {
                id: outputSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                bar: root.bar
                value: root.outputVolume
                enabled: root.outputAvailable
                onMoved: function(value) { root.setVolume(root.sink, value) }
                onRightClicked: root.toggleMute(false)
              }
              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "output"
                  root.selectedIndex = -1
                }
              }
            }

            Repeater {
              model: root.displaySinks
              NodeRow {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                node: modelData
                rowIndex: index
                inputNode: false
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.inputAvailable || root.displaySources.length > 0
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "INPUT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            CursorSurface {
              width: parent.width
              implicitHeight: inputSlider.implicitHeight + Style.space(8)
              hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex < 0
              foreground: root.foreground
              PanelSlider {
                id: inputSlider
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                bar: root.bar
                value: root.inputVolume
                enabled: root.inputAvailable
                onMoved: function(value) { root.setVolume(root.source, value) }
                onRightClicked: root.toggleMute(true)
              }
              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "input"
                  root.selectedIndex = -1
                }
              }
            }
            Repeater {
              model: root.displaySources
              NodeRow {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                node: modelData
                rowIndex: index
                inputNode: true
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.displayStreams.length > 0
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "APPLICATIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: root.displayStreams
              StreamRow {
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                node: modelData
                rowIndex: index
              }
            }
          }
        }
      }
    }
  }

  component NodeRow: CursorSurface {
    id: nodeRow
    required property var node
    required property int rowIndex
    required property bool inputNode

    readonly property bool isCurrent: inputNode
      ? root.source && root.source.id === node.id
      : root.sink && root.sink.id === node.id
    hasCursor: root.cursorActive
      && root.focusSection === (inputNode ? "input" : "output")
      && root.selectedIndex === rowIndex
    current: nodeRow.isCurrent
    foreground: root.foreground
    fill: Style.hoverFillFor(root.foreground, Color.accent)
    currentFill: Style.selectedFillFor(root.foreground, Color.accent)
    implicitHeight: Style.space(38)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: inputNode ? root.sourceGlyph(node) : root.sinkGlyph(node)
      color: root.panelSecondary
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(38)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.nodeLabel(node)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: nodeRow.isCurrent
      elide: Text.ElideRight
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = inputNode ? "input" : "output"
        root.selectedIndex = rowIndex
      }
      onClicked: root.setDefault(node, inputNode)
    }
  }

  component StreamRow: CursorSurface {
    id: streamRow
    required property var node
    required property int rowIndex

    readonly property real volume: node && node.audio ? node.audio.volume : 0
    hasCursor: root.cursorActive && root.focusSection === "streams" && root.selectedIndex === rowIndex
    foreground: root.foreground
    implicitHeight: streamSlider.implicitHeight + Style.space(18)

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(3)

      Row {
        width: parent.width
        Text {
          width: parent.width - streamPercent.width
          text: root.streamLabel(node)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          id: streamPercent
          text: Math.round(streamRow.volume * 100) + "%"
          color: root.panelSecondary
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      PanelSlider {
        id: streamSlider
        width: parent.width
        bar: root.bar
        minimum: 0
        maximum: 1.5
        value: streamRow.volume
        onMoved: function(value) { root.setVolume(streamRow.node, value) }
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      hoverEnabled: true
      propagateComposedEvents: true
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "streams"
        root.selectedIndex = rowIndex
      }
    }
  }
}
