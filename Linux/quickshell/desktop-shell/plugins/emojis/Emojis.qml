import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
  property var emojis: []
  property var filteredEmojis: []

  property color foreground: Color.barPanels.text
  property color secondaryForeground: Color.barPanels.secondaryText
  property color accent: Color.accent
  property color scrim: Color.modal.scrim
  property string fontFamily: Style.font.family
  property int contentMargin: Style.spacing.popupPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(400), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)

  property int cellWidth: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int cellHeight: Math.max(Style.space(44), Style.font.display + Style.spacing.md)
  property int columns: Math.floor((cardWidth - contentMargin * 2) / cellWidth)

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
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

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    cursorActive = displayModel.count > 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectRow(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    var newIndex = selectedIndex + delta * columns
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function selectPage(delta, halfPage) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
      resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
      return
    }
    var visibleRows = Math.max(1, Math.floor(resultGrid.height / cellHeight))
    var pageRows = halfPage ? Math.max(1, Math.floor(visibleRows / 2)) : visibleRows
    var newIndex = selectedIndex + delta * columns * pageRows
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    root.applySelected(row.emoji)
  }

  function applySelected(emoji) {
    if (!emoji) return
    root.dismiss()
    Quickshell.execDetached(["desktop-shell-emoji-insert", emoji])
  }

  ListModel { id: displayModel }

  FileView {
    path: root.pluginPath + "/emojis.json"
    onLoaded: root.loadEmojis(text())
  }
  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "desktop-emojis"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
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
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

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
              hasCursor: root.cursorActive && index === root.selectedIndex
              foreground: root.foreground
              accent: root.accent

              Text {
                anchors.centerIn: parent
                text: parent.emoji
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = index
                  root.activateIndex(index)
                }
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
