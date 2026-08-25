import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: root

  property string shellPath: Quickshell.shellDir
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property var history: []
  property bool historyValid: false
  property int watchRestartDelay: 1000
  property bool shuttingDown: false
  property bool stateReady: false
  property bool captureStarted: false

  property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/desktop-shell"
  property string historyPath: root.stateRoot + "/clipboard-history.json"
  property string imageDir: root.stateRoot + "/clipboard-images"
  property string captureScript: root.shellPath + "/plugins/clipboard/capture.sh"
  property color foreground: Color.barPanels.text
  property color secondaryForeground: Color.barPanels.secondaryText
  property color accent: Color.accent
  property color scrim: Color.modal.scrim
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.popupPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(875), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int historyLimit: 500

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    root.cancelClearHistory()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function normalizeEntry(value) {
    return ClipboardHistory.normalizeEntry(value)
  }

  function entryKey(entry) {
    return ClipboardHistory.entryKey(entry)
  }

  function loadHistory(raw) {
    var result = ClipboardHistory.parseHistoryResult(raw, root.imageDir)
    root.historyValid = result.valid
    root.history = result.history
    if (root.historyValid) Quickshell.execDetached(["desktop-shell-clipboard-cleanup", "--prune"])
    if (root.opened) root.rebuildDisplay()
  }

  function historyLoadFailed() {
    root.historyValid = false
    root.history = []
    if (root.opened) root.rebuildDisplay()
  }

  function saveHistory() {
    root.historyValid = true
    historyFile.setText(JSON.stringify(root.history.slice(0, root.historyLimit), null, 2) + "\n")
  }

  function addClipboardEntry(entry) {
    var normalized = ClipboardHistory.normalizeEntry(entry, root.imageDir)
    if (!normalized) return

    root.history = ClipboardHistory.addEntry(root.history, normalized, root.historyLimit, root.imageDir)
    root.saveHistory()
    if (root.opened) root.rebuildDisplay()
  }

  function addClipboardJson(line) {
    root.addClipboardEntry(ClipboardHistory.parseEntryJson(line, root.imageDir))
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.disarmPointer()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function confirmClearHistory() {
    var removedImages = ClipboardHistory.imagePaths(root.history)
    root.history = ClipboardHistory.clearHistory()
    root.saveHistory()
    if (removedImages.length > 0)
      Quickshell.execDetached(["desktop-shell-clipboard-cleanup", "--remove"].concat(removedImages))
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    var removedEntry = root.history[row.historyIndex]
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()
    if (removedEntry && removedEntry.type === "image")
      Quickshell.execDetached(["desktop-shell-clipboard-cleanup", "--remove", String(removedEntry.path || "")])

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, 50)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectHalfPage(delta) {
    var visibleRows = Math.max(1, Math.floor(resultList.height / (root.rowHeight + resultList.spacing)))
    root.select(delta * Math.max(1, Math.floor(visibleRows / 2)))
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.applySelected(row)
  }

  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.copySelected(row)
  }

  function openIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.openSelected(row)
  }

  function applySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached(["desktop-shell-clipboard-paste-file", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached(["desktop-shell-clipboard-paste-text", "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  function copySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached(["desktop-shell-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached(["desktop-shell-clipboard-paste-text", "--copy-only", "--history-index", String(row.historyIndex)])
    }
  }

  function openSelected(row) {
    if (!row) return
    root.opened = false
    Quickshell.execDetached(["desktop-shell-clipboard-open", "--history-index", String(row.historyIndex)])
  }

  function startWatchers() {
    if (root.shuttingDown) return
    if (!textWatchProc.running) textWatchProc.running = true
    if (!imageWatchProc.running) imageWatchProc.running = true
    watchStableTimer.restart()
  }

  function startCapture() {
    if (root.captureStarted || root.shuttingDown) return
    root.captureStarted = true
    currentProc.running = true
    root.startWatchers()
  }

  function scheduleWatcherRestart() {
    if (root.shuttingDown) return
    watchStableTimer.stop()
    watchRestartTimer.interval = root.watchRestartDelay
    root.watchRestartDelay = Math.min(root.watchRestartDelay * 2, 30000)
    watchRestartTimer.restart()
  }

  Component.onCompleted: {
    stateInitProc.running = true
  }

  Component.onDestruction: {
    root.shuttingDown = true
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.stateReady ? root.historyPath : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.loadHistory(text())
      root.startCapture()
    }
    onLoadFailed: {
      root.historyLoadFailed()
      root.startCapture()
    }
    onFileChanged: reload()
  }

  Process {
    id: stateInitProc
    command: [root.captureScript, "--init"]
    onExited: function(exitCode) {
      if (Number(exitCode) !== 0) {
        console.warn("clipboard state initialization failed")
        return
      }
      root.stateReady = true
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: root.scheduleWatcherRestart()
    Component.onDestruction: if (running) signal(15)
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image", "--watch", root.captureScript, "image"]
    onExited: root.scheduleWatcherRestart()
    Component.onDestruction: if (running) signal(15)
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Timer {
    id: watchRestartTimer
    repeat: false
    onTriggered: root.startWatchers()
  }

  Timer {
    id: watchStableTimer
    interval: 30000
    repeat: false
    onTriggered: root.watchRestartDelay = 1000
  }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "desktop-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    PanelSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      padding: root.contentMargin
      revealed: root.opened
      entranceY: -Style.space(6)

      MouseArea { anchors.fill: parent; onClicked: {} }

      ConfirmDialog {
        id: clearConfirm

        anchors.fill: parent
        opened: root.clearConfirmOpen
        z: 10
        message: "Delete entire clipboard history?"
        confirmText: "Delete"
        foreground: root.foreground
        secondaryForeground: root.secondaryForeground
        scrim: root.scrim
        fontFamily: root.fontFamily
        onCanceled: root.cancelClearHistory()
        onConfirmed: root.confirmClearHistory()
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        TextField {
          id: searchField
          width: parent.width
          height: root.headerHeight
          text: root.filterText
          placeholderText: "Search clipboard…"
          foreground: root.foreground
          accent: root.accent
          font.family: root.fontFamily
          Keys.priority: Keys.BeforeItem
          onTextEdited: if (text !== root.filterText) root.setFilter(text)

          Keys.onPressed: function(event) {
            if (root.clearConfirmOpen) {
              if (clearConfirm.handleKey(event)) event.accepted = true
              return
            }

            var control = event.modifiers & Qt.ControlModifier
            if (control && event.key === Qt.Key_J) {
              root.select(1)
              event.accepted = true
            } else if (control && event.key === Qt.Key_K) {
              root.select(-1)
              event.accepted = true
            } else if (control && event.key === Qt.Key_U) {
              root.selectHalfPage(-1)
              event.accepted = true
            } else if (control && event.key === Qt.Key_D) {
              root.selectHalfPage(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              if (root.filterText) root.setFilter("")
              else root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Delete) {
              if (event.modifiers & Qt.ShiftModifier) root.requestClearHistory()
              else root.removeDisplayIndex(root.selectedIndex)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.select(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.select(1)
              event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              root.select(-6)
              event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              root.select(6)
              event.accepted = true
            } else if (event.key === Qt.Key_Home) {
              root.selectAbsolute(0)
              event.accepted = true
            } else if (event.key === Qt.Key_End) {
              root.selectAbsolute(displayModel.count - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (root.cursorActive && (event.modifiers & Qt.AltModifier)) root.openIndex(root.selectedIndex)
              else if (root.cursorActive && (event.modifiers & Qt.ShiftModifier)) root.copyIndex(root.selectedIndex)
              else if (root.cursorActive) root.activateIndex(root.selectedIndex)
              else if (displayModel.count > 0) root.cursorActive = true
              event.accepted = true
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: parent.width / 2
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: displayModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: CursorSurface {
                  id: row
                  required property int index
                  required property string entryType
                  required property string previewText
                  required property string fullText
                  required property string previewImage

                  width: ListView.view.width
                  height: root.rowHeight
                  hasCursor: root.cursorActive && index === root.selectedIndex
                  foreground: root.foreground
                  accent: root.accent

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    anchors.topMargin: Style.space(8)
                    anchors.bottomMargin: Style.space(8)
                    spacing: Style.space(10)

                    Image {
                      visible: parent.parent.previewImage.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      source: parent.parent.previewImage
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Text {
                      width: parent.width - (parent.parent.previewImage.length > 0 ? parent.height + parent.spacing : 0)
                      height: parent.height
                      text: parent.parent.previewText
                      color: parent.parent.hasCursor ? root.foreground : root.secondaryForeground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      opacity: parent.parent.entryType === "image" || parent.parent.entryType === "file" ? 0.72 : 1.0
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) {
                      root.selectFromPointer(row.index, row, mouse)
                    }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      root.activateIndex(row.index)
                    }
                  }
                }
              }
            }

            Item {
              width: parent.width / 2
              height: parent.height
              clip: true

              property var activeRow: displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.foreground, 0.28)
              }

              Text {
                visible: parent.activeRow && !parent.activeRow.previewImage
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                anchors.rightMargin: 0
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                text: parent.activeRow ? parent.activeRow.fullText : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
              }

              Image {
                visible: parent.activeRow && parent.activeRow.previewImage
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                anchors.rightMargin: 0
                anchors.topMargin: 0
                anchors.bottomMargin: 0
                source: parent.activeRow ? parent.activeRow.previewImage : ""
                fillMode: Image.PreserveAspectFit
                verticalAlignment: Image.AlignTop
                asynchronous: true
                smooth: true
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰅌"
              color: root.accent
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }
      }
    }
  }
}
