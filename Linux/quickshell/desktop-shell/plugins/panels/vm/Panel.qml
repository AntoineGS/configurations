import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "desktop.vm"
  ipcTarget: "desktop.vm"

  property var vmState: Model.emptyState()
  property var hostMemoryState: Model.emptyHostStat()
  property var hostCpuState: Model.emptyHostStat()
  property var popupAnchorItem: vmCpuButton
  property int previewGiB: 1
  property bool resizePending: false
  property string actionError: ""
  property bool refreshQueued: false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color statForeground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool canResize: vmState.canResize && !resizePending
  readonly property bool hostMemoryCritical: Model.memoryCritical(root.hostMemoryState.percent)
  readonly property bool vmMemoryCritical: Model.memoryCritical(root.vmState.memoryPercent)
  readonly property string vmTooltip: vmState.stale
    ? vmState.name + " (stale): " + vmState.error
    : vmState.name

  function refresh() {
    if (!stateProcess.running) stateProcess.running = true
    if (!hostMemoryProcess.running) hostMemoryProcess.running = true
    if (!hostCpuProcess.running) hostCpuProcess.running = true
  }

  function openFrom(anchorItem) {
    if (!vmState.visible || !anchorItem) return
    popupAnchorItem = anchorItem
    root.open()
  }

  function openHostMonitor() {
    Util.execDetached("launch-or-focus-tui btop")
  }

  function requestMemory(gib) {
    var value = Math.round(Number(gib))
    if (!canResize || value < Model.minimumGiB() || value > Model.maximumGiB(vmState)) return
    resizePending = true
    actionError = ""
    previewGiB = value
    actionProcess.command = ["desktop-hardware-action", "vm", "set-memory", String(value)]
    actionProcess.running = true
  }

  function reportStateError() {
    var registry = bar && bar.shell ? bar.shell.pluginRegistry : null
    if (!registry) return
    if (vmState.stale && vmState.error) registry.recordPluginError(moduleName, vmState.error)
    else registry.clearPluginError(moduleName)
  }

  function applyState(raw, processError) {
    var nextState = Model.stateFromRaw(vmState, raw, processError)
    if (!nextState.malformed && !nextState.visible && root.opened) root.close()
    vmState = nextState
    reportStateError()
    if (!memorySlider.dragging && !resizePending) previewGiB = Model.currentGiB(vmState)
  }

  visible: hostMemoryState.available || hostCpuState.available || vmState.visible
  implicitWidth: visible ? statRow.implicitWidth : 0
  implicitHeight: visible ? statRow.implicitHeight : 0

  onOpenedChanged: {
    if (opened) {
      previewGiB = Model.currentGiB(vmState)
      actionError = ""
    }
  }
  onBarChanged: reportStateError()

  Timer {
    id: refreshTimer
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProcess
    command: ["desktop-hardware-state", "vm"]
    stdout: StdioCollector {
      id: stateStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: stateStderr
      waitForEnd: true
    }
    onExited: {
      var processError = ""
      if (Number(exitCode) !== 0) {
        processError = String(stateStderr.text || "").trim()
        if (!processError) processError = "desktop-hardware-state exited with code " + String(exitCode)
      }
      root.applyState(stateStdout.text || "", processError)
      if (!root.refreshQueued) return
      root.refreshQueued = false
      root.refresh()
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
    }
    onExited: {
      root.resizePending = false
      if (exitCode === 0) {
        root.actionError = ""
        if (stateProcess.running) root.refreshQueued = true
        else root.refresh()
      } else {
        root.previewGiB = Model.currentGiB(root.vmState)
        root.actionError = String(actionStderr.text || "").trim()
      }
    }
  }

  Process {
    id: hostMemoryProcess
    command: ["desktop-shell-status", "memory"]
    stdout: StdioCollector {
      id: hostMemoryStdout
      waitForEnd: true
    }
    onExited: root.hostMemoryState = Model.hostStateFromRaw(root.hostMemoryState, hostMemoryStdout.text || "")
  }

  Process {
    id: hostCpuProcess
    command: ["desktop-shell-status", "cpu"]
    stdout: StdioCollector {
      id: hostCpuStdout
      waitForEnd: true
    }
    onExited: root.hostCpuState = Model.hostStateFromRaw(root.hostCpuState, hostCpuStdout.text || "")
  }

  Row {
    id: statRow
    spacing: 0

    WidgetButton {
      id: hostMemoryButton
      bar: root.bar
      text: root.hostMemoryState.available ? root.hostMemoryState.text : ""
      tooltipText: root.hostMemoryState.tooltip
      horizontalMargin: 2.5
      foreground: root.hostMemoryCritical ? root.urgent : root.statForeground
      onPressed: function(mouseButton) {
        if (mouseButton === Qt.LeftButton) root.openHostMonitor()
      }
    }

    WidgetButton {
      id: vmMemoryButton
      bar: root.bar
      text: root.vmState.visible && root.vmState.showMemoryUsage
        ? Model.vmMetricText(root.vmState.memoryPercent) : ""
      tooltipText: root.vmTooltip
      horizontalMargin: 1
      foreground: root.vmMemoryCritical ? root.urgent : root.statForeground
      dimmed: !root.vmMemoryCritical
      onPressed: function(mouseButton) {
        if (mouseButton === Qt.LeftButton) root.openFrom(vmMemoryButton)
      }
    }

    WidgetButton {
      id: hostCpuButton
      bar: root.bar
      text: root.hostCpuState.available ? root.hostCpuState.text : ""
      tooltipText: root.hostCpuState.tooltip
      horizontalMargin: 2.5
      foreground: root.statForeground
      onPressed: function(mouseButton) {
        if (mouseButton === Qt.LeftButton) root.openHostMonitor()
      }
    }

    WidgetButton {
      id: vmCpuButton
      bar: root.bar
      text: root.vmState.visible ? Model.vmMetricText(root.vmState.cpuPercent) : ""
      tooltipText: root.vmTooltip
      horizontalMargin: 1
      foreground: root.statForeground
      dimmed: true
      onPressed: function(mouseButton) {
        if (mouseButton === Qt.LeftButton) root.openFrom(vmCpuButton)
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.popupAnchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.vmState.visible
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && root.canResize)
          root.previewGiB = Math.max(Model.minimumGiB(),
            Math.min(Model.maximumGiB(root.vmState), root.previewGiB + dx))
      }
      onActivateRequested: root.requestMemory(root.previewGiB)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.vmState.name
            meta: root.vmState.vcpus + " VCPUS · KVM"
            detail: "RUNNING"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            width: parent.width
            visible: root.vmState.stale
            text: root.vmState.error || ""
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            id: metricCards
            width: parent.width
            spacing: Style.space(8)

            BorderSurface {
              id: memoryCard
              visible: root.vmState.showMemoryUsage
              width: visible ? (metricCards.width - metricCards.spacing) / 2 : 0
              implicitHeight: Style.space(72)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(2)

                Text {
                  text: "MEMORY"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }
                Text {
                  text: Model.formatPercent(root.vmState.memoryPercent)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  text: Model.formatGiB(root.vmState.usedKiB) + " / " + Model.formatGiB(root.vmState.currentKiB)
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            BorderSurface {
              id: cpuCard
              width: root.vmState.showMemoryUsage
                ? (metricCards.width - metricCards.spacing) / 2 : metricCards.width
              implicitHeight: Style.space(72)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(2)

                Text {
                  text: "CPU"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }
                Text {
                  text: Model.formatPercent(root.vmState.cpuPercent)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  text: root.vmState.vcpus + " VCPUS"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "ALLOCATED MEMORY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            text: (memorySlider.dragging || root.resizePending
              || root.previewGiB !== Model.currentGiB(root.vmState)
              ? root.previewGiB : Model.currentGiB(root.vmState)) + " GiB"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          CursorSurface {
            width: parent.width
            implicitHeight: memorySlider.implicitHeight + Style.spacing.controlGap
            foreground: root.foreground
            bordered: true

            PanelSlider {
              id: memorySlider
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              bar: root.bar
              minimum: Model.minimumGiB()
              maximum: Model.maximumGiB(root.vmState)
              step: 1
              integer: true
              value: root.previewGiB
              enabled: root.canResize
              tickCount: Math.min(13, Math.max(2, maximum - minimum + 1))
              onMoved: function(value) { root.previewGiB = Math.round(value) }
              onReleased: function(value) { root.requestMemory(Math.round(value)) }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(minimumLabel.implicitHeight, maximumLabel.implicitHeight)

            Text {
              id: minimumLabel
              anchors.left: parent.left
              text: Model.minimumGiB() + " GiB"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              id: maximumLabel
              anchors.right: parent.right
              text: Model.maximumGiB(root.vmState) + " GiB"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            text: "LIVE + NEXT BOOT"
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }

          Text {
            width: parent.width
            visible: root.resizePending || root.actionError !== ""
            text: root.resizePending ? "Updating memory..." : root.actionError
            color: root.actionError !== "" ? Color.urgent : Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
