import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "EmojiSearch.js" as EmojiSearch

Item {
  id: root

  property string pluginPath: Quickshell.shellDir + "/plugins/emojis"
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool selectingRecent: false
  property var emojis: []
  property var filteredEmojis: []
  property var recentEmojis: []
  property var pendingRecentEmojis: []
  property bool stateReady: false
  property bool recentLoaded: false

  readonly property int recentLimit: 8
  readonly property bool showRecents: root.filterText === "" && recentModel.count > 0
  readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/desktop-shell"
  readonly property string recentPath: root.stateRoot + "/emoji-history.json"

  property color foreground: Color.barPanels.text
  property color secondaryForeground: Color.barPanels.secondaryText
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.popupPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md

  property int cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int columns: Math.max(1, Math.floor((panel.bodyWidth) / cellWidth))

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.selectingRecent = root.recentEmojis.length > 0
    root.rebuildDisplay()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "desktop.emojis")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function loadEmojis(raw) {
    root.emojis = EmojiSearch.parseEmojis(raw)
    if (root.opened) root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var out = EmojiSearch.filterEmojis(root.emojis, root.filterText, 1000)
    root.filteredEmojis = out

    displayModel.clear()
    for (var j = 0; j < out.length; j++) {
      displayModel.append({ emoji: out[j].e, index: j })
    }

    var activeCount = root.selectingRecent && root.showRecents ? recentModel.count : displayModel.count
    if (activeCount === 0) selectedIndex = 0
    else if (selectedIndex >= activeCount) selectedIndex = activeCount - 1
    else if (selectedIndex < 0) selectedIndex = 0
    cursorActive = activeCount > 0

    Qt.callLater(function() {
      if (!root.selectingRecent && displayModel.count > 0)
        resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function loadRecentEmojis(raw) {
    var merged = EmojiSearch.parseRecentEmojis(raw, root.recentLimit)
    var hadPending = root.pendingRecentEmojis.length > 0
    for (var i = root.pendingRecentEmojis.length - 1; i >= 0; i--)
      merged = EmojiSearch.addRecentEmoji(merged, root.pendingRecentEmojis[i], root.recentLimit)

    root.recentEmojis = merged
    root.pendingRecentEmojis = []
    root.recentLoaded = true
    recentModel.clear()
    for (var j = 0; j < root.recentEmojis.length; j++)
      recentModel.append({ emoji: root.recentEmojis[j] })

    if (hadPending)
      recentFile.setText(JSON.stringify(root.recentEmojis) + "\n")

    if (root.opened && root.filterText === "") {
      root.selectingRecent = recentModel.count > 0
      root.selectedIndex = 0
      root.cursorActive = recentModel.count > 0 || displayModel.count > 0
    }
  }

  function saveRecentEmoji(emoji) {
    root.recentEmojis = EmojiSearch.addRecentEmoji(root.recentEmojis, emoji, root.recentLimit)
    if (!root.recentLoaded)
      root.pendingRecentEmojis = EmojiSearch.addRecentEmoji(root.pendingRecentEmojis, emoji, root.recentLimit)
    recentModel.clear()
    for (var i = 0; i < root.recentEmojis.length; i++)
      recentModel.append({ emoji: root.recentEmojis[i] })
    if (root.recentLoaded)
      recentFile.setText(JSON.stringify(root.recentEmojis) + "\n")
  }

  function select(delta) {
    var count = root.selectingRecent && root.showRecents ? recentModel.count : displayModel.count
    if (count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + count) % count
    }
    if (!root.selectingRecent)
      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectRow(delta) {
    if (recentModel.count === 0 && displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      root.selectingRecent = root.showRecents && delta < 0
      selectedIndex = root.selectingRecent ? recentModel.count - 1 : 0
      if (!root.selectingRecent && displayModel.count > 0)
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    if (root.selectingRecent) {
      if (delta > 0 && displayModel.count > 0) {
        root.selectingRecent = false
        selectedIndex = Math.min(selectedIndex, displayModel.count - 1)
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      }
      return
    }
    var newIndex = selectedIndex + delta * columns
    if (newIndex < 0 && root.showRecents) {
      root.selectingRecent = true
      selectedIndex = Math.min(selectedIndex % columns, recentModel.count - 1)
      return
    }
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectPage(delta, halfPage) {
    if (recentModel.count === 0 && displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      root.selectingRecent = root.showRecents && delta < 0
      selectedIndex = root.selectingRecent ? recentModel.count - 1 : 0
      if (!root.selectingRecent && displayModel.count > 0)
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    var visibleRows = Math.max(1, Math.floor(resultGrid.height / cellHeight))
    var pageRows = halfPage ? Math.max(1, Math.floor(visibleRows / 2)) : visibleRows
    if (root.selectingRecent) {
      if (delta > 0 && displayModel.count > 0) {
        root.selectingRecent = false
        selectedIndex = Math.min(selectedIndex + columns * (pageRows - 1), displayModel.count - 1)
        resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      }
      return
    }
    var newIndex = selectedIndex + delta * columns * pageRows
    if (newIndex < 0 && root.showRecents) {
      root.selectingRecent = true
      selectedIndex = Math.min(selectedIndex % columns, recentModel.count - 1)
      return
    }
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.selectingRecent = nextFilter === "" && recentModel.count > 0
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    var model = root.selectingRecent && root.showRecents ? recentModel : displayModel
    if (index < 0 || index >= model.count) return
    var row = model.get(index)
    root.applySelected(row.emoji)
  }

  function applySelected(emoji) {
    if (!emoji) return
    root.saveRecentEmoji(emoji)
    root.dismiss()
    Quickshell.execDetached(["desktop-shell-emoji-insert", emoji])
  }

  ListModel { id: displayModel }
  ListModel { id: recentModel }

  Component.onCompleted: stateDirectoryProcess.running = true

  Process {
    id: stateDirectoryProcess
    command: ["mkdir", "-p", "--", root.stateRoot]
    onExited: function(exitCode) {
      if (Number(exitCode) === 0) root.stateReady = true
      else console.warn("emoji history directory could not be created")
    }
  }

  FileView {
    id: recentFile
    path: root.stateReady ? root.recentPath : ""
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadRecentEmojis(text())
    onLoadFailed: root.loadRecentEmojis("[]")
    onSaveFailed: function(error) { console.warn("emoji history save failed: " + error) }
  }

  FileView {
    path: root.pluginPath + "/emojis.json"
    onLoaded: root.loadEmojis(text())
  }
  TopBarOverlay {
    id: panel
    overlayId: "desktop.emojis"
    layerNamespace: "desktop-emojis"
    shell: root.shell
    opened: root.opened
    requestedCardWidth: Style.space(400)
    requestedCardHeight: Style.space(500)
    headerHeight: root.headerHeight
    contentSpacing: root.contentSpacing
    contentPadding: root.contentMargin
    onDismissRequested: root.dismiss()

    headerData: TextField {
      id: searchField
      width: parent.width
      height: root.headerHeight
      text: root.filterText
      placeholderText: "Search emojis…"
      foreground: root.foreground
      accent: root.accent
      font.family: root.fontFamily
      Keys.priority: Keys.BeforeItem
      onTextEdited: if (text !== root.filterText) root.setFilter(text)

      Keys.onPressed: function(event) {
        var control = event.modifiers & Qt.ControlModifier
        if (control && event.key === Qt.Key_H) {
          root.select(-1)
          event.accepted = true
        } else if (control && event.key === Qt.Key_J) {
          root.selectRow(1)
          event.accepted = true
        } else if (control && event.key === Qt.Key_K) {
          root.selectRow(-1)
          event.accepted = true
        } else if (control && event.key === Qt.Key_L) {
          root.select(1)
          event.accepted = true
        } else if (control && event.key === Qt.Key_U) {
          root.selectPage(-1, true)
          event.accepted = true
        } else if (control && event.key === Qt.Key_D) {
          root.selectPage(1, true)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.selectRow(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.selectRow(1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.selectPage(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.selectPage(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.cursorActive) root.activateIndex(root.selectedIndex)
          else if (displayModel.count > 0) root.cursorActive = true
          event.accepted = true
        }
      }
    }

    Item {
      anchors.fill: parent

      Column {
        anchors.fill: parent
        spacing: root.contentSpacing

        Item {
          id: recentSection
          width: parent.width
          height: root.showRecents ? root.cellHeight : 0
          visible: root.showRecents

          GridView {
            anchors.fill: parent
            model: recentModel
            interactive: false
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight

            delegate: CursorSurface {
              required property int index
              required property string emoji

              width: root.cellWidth
              height: root.cellHeight
              hasCursor: root.cursorActive && root.selectingRecent && index === root.selectedIndex
              foreground: root.foreground
              accent: root.accent

              Text {
                anchors.centerIn: parent
                text: parent.emoji
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Math.max(0, panel.bodyHeight - recentSection.height
            - root.contentSpacing * (root.showRecents ? 1 : 0))

          GridView {
            id: resultGrid
            anchors.fill: parent
            model: displayModel
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            delegate: CursorSurface {
              required property int index
              required property string emoji

              width: root.cellWidth
              height: root.cellHeight
              hasCursor: root.cursorActive && !root.selectingRecent && index === root.selectedIndex
              foreground: root.foreground
              accent: root.accent

              Text {
                anchors.centerIn: parent
                text: parent.emoji
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰈉"
              color: root.accent
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: "No matches for “" + root.filterText + "”"
              color: root.secondaryForeground
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
