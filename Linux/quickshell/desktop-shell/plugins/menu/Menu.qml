import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool menuReady: false
  property var menuItems: []
  property var items: ({})
  property var itemOrder: []
  property string activeMenu: "root"
  property var navStack: []
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null

  readonly property var routeWidgets: ({
    "setup.power-profile": "desktop.power",
    "setup.monitors": "desktop.monitor"
  })
  readonly property var whenResults: MenuModel.routeVisibility(
    root.shell && root.shell.barConfig ? root.shell.barConfig.layout : null,
    root.routeWidgets)

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder, 0)
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int rowHeight: Math.max(Style.space(42), Style.font.body + Style.spacing.rowPaddingX * 2)
  readonly property int rowSpacing: Style.space(2)
  readonly property int listHeight: Math.min(
    Math.max(rowHeight, displayModel.count * rowHeight + Math.max(0, displayModel.count - 1) * rowSpacing),
    Style.space(440)
  )
  readonly property string healthSummary: {
    var health = root.shell && root.shell.healthState ? root.shell.healthState : null
    if (!health) return ""
    if (health.configValid === false) return "Shell config needs attention"
    if (health.pluginErrors && health.pluginErrors.length > 0) return "Shell health has warnings"
    return ""
  }

  function item(id) {
    return root.items[String(id || "")] || null
  }

  function rebuildItems() {
    var merged = MenuModel.mergeMenuSources(root.menuItems, [])
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    root.menuReady = true
    if (!root.item(root.activeMenu)) root.activeMenu = "root"
    if (root.opened) root.rebuildDisplay()
  }

  function applyMenuSource(raw) {
    var result = MenuModel.parseMenuJsoncResult(raw)
    if (result.valid) {
      root.menuItems = result.items
    } else {
      root.menuItems = MenuModel.preserveLastValid(root.menuItems, result)
      console.warn("desktop menu JSONC is invalid; keeping the last valid menu")
    }
    root.rebuildItems()
  }

  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  function isDisabled(entry) {
    return MenuModel.isDisabled({}, entry)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, {}, {}, entry, detail, score, section)
  }

  function rowSelectable(index) {
    if (index < 0 || index >= displayModel.count) return false
    return !displayModel.get(index).disabled
  }

  function nextSelectable(from, direction) {
    var count = displayModel.count
    if (count === 0) return -1
    var step = direction < 0 ? -1 : 1
    var index = ((from % count) + count) % count
    for (var i = 0; i < count; i++) {
      if (root.rowSelectable(index)) return index
      index = (index + step + count) % count
    }
    return -1
  }

  function settleCursor() {
    var target = root.nextSelectable(root.selectedIndex, 1)
    root.selectedIndex = target >= 0 ? target : 0
    root.cursorActive = target >= 0
  }

  function rebuildDisplay() {
    displayModel.clear()
    if (!root.menuReady) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var commandRows = []
    var query = root.filterText.trim()

    if (query) {
      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root" || !root.isVisible(entry)) continue
        if (!MenuModel.isDescendantOf(root.items, entry.id, active)) continue
        if (!MenuModel.matchesQuery(entry, query, !root.isDisabled(entry))) continue
        commandRows.push(root.displayRow(entry, root.parentPath(entry.id), MenuModel.searchScore(root.items, entry, query), "search"))
      }
      commandRows.sort(function(left, right) {
        if (left.score !== right.score) return left.score - right.score
        return left.path.localeCompare(right.path)
      })
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active || !root.isVisible(child)) continue
        commandRows.push(root.displayRow(child, child.description, child.order, ""))
      }
    }

    var appRows = []
    if (query && active === "root" && root.appLibrary) {
      var applications = root.appLibrary.sortedEntries(query)
      for (var appIndex = 0; appIndex < applications.length; appIndex++) {
        var application = applications[appIndex]
        appRows.push(MenuModel.applicationRow(application.entry, root.appLibrary, application.score))
      }
    }

    var rows = MenuModel.composeSearchResults(commandRows, appRows, null)
    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    root.settleCursor()
  }

  function parentPath(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function select(delta) {
    if (displayModel.count === 0) return
    var from = root.cursorActive ? root.selectedIndex + delta : (delta < 0 ? displayModel.count - 1 : 0)
    var target = root.nextSelectable(from, delta)
    if (target < 0) return
    root.cursorActive = true
    root.selectedIndex = target
    resultList.positionViewAtIndex(target, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = String(nextFilter || "")
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory) {
    var target = String(id || "")
    if (!root.item(target) || root.item(target).kind === "action") target = "root"
    if (pushHistory && target !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = target
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function goBack() {
    if (root.activeMenu === "root") return false
    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }
    var active = root.item(root.activeMenu)
    root.setActiveMenu(active && active.parent ? active.parent : "root", false)
    return true
  }

  function activateIndex(index) {
    if (!root.rowSelectable(index)) return
    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true)
    } else if (row.kind === "application") {
      root.opened = false
      root.filterText = ""
      if (root.appLibrary) root.appLibrary.launch(row.desktopId, row.label)
    } else {
      root.applySelected(row.action)
    }
  }

  function applySelected(action) {
    if (!root.runAction(action)) return
    root.opened = false
    root.filterText = ""
  }

  function runAction(action) {
    if (!MenuModel.isOpaqueActionId(action) || actionProcess.running) return false
    actionProcess.command = ["desktop-shell-action", String(action)]
    actionProcess.running = true
    return true
  }

  function selectFromPointer(index) {
    if (!root.rowSelectable(index)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function openExistingMenu(initialMenu) {
    root.activeMenu = root.item(initialMenu) ? initialMenu : "root"
    root.navStack = []
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.opened = true
    root.rebuildDisplay()
    if (root.appLibrary) root.appLibrary.refreshIcons()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.item(id)
    if (entry && entry.kind === "action") {
      if (!root.isVisible(entry)) return "unknown"
      root.runAction(entry.action)
      return "ok"
    }
    if (entry && entry.kind === "link") id = entry.target
    root.openExistingMenu(id)
    return "ok"
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (error) { payload = ({}) }
    return root.openRoute(payload.initialMenu || payload.menu || "root")
  }

  function close() {
    root.opened = false
    root.filterText = ""
  }

  onWhenResultsChanged: if (root.opened) root.rebuildDisplay()

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.opened && root.activeMenu === "root" && root.filterText.trim()) root.rebuildDisplay()
    }
  }

  // The menu is loaded on demand in preview, so keep its health probe with the
  // single menu instance instead of adding a handler to each bar screen.
  IpcHandler {
    target: "desktop.menu"

    function ping(): string { return "pong" }
  }

  function refresh() {
    defaultMenuFile.reload()
    return "ok"
  }

  ListModel {
    id: displayModel
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  FileView {
    id: defaultMenuFile
    path: Quickshell.shellDir + "/config/menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyMenuSource(text())
    onLoadFailed: root.applyMenuSource("")
    onFileChanged: reload()
  }

  PanelWindow {
    id: panel
    visible: root.opened && root.menuReady
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "desktop-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Rectangle {
      anchors.fill: parent
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(460), panel.width - Style.gapsOut * 2)
      height: Math.min(
        root.contentMargin * 2 + Style.space(54) + root.listHeight + (root.healthSummary ? Style.space(24) : 0),
        panel.height - Style.gapsOut * 2
      )
      anchors.centerIn: parent
      color: root.background
      radius: Style.cornerRadius
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.margins: card.padding
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (!root.goBack()) root.close()
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else root.settleCursor()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127
                     && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Column {
          anchors.fill: parent
          spacing: Style.space(10)

          Text {
            width: parent.width
            height: Style.space(34)
            text: root.filterText || ((root.item(root.activeMenu) ? root.item(root.activeMenu).label : "Control") + "…")
            color: root.foreground
            opacity: root.filterText ? 1 : 0.62
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }

          Item {
            width: parent.width
            height: root.listHeight

            ListView {
              id: resultList
              anchors.fill: parent
              model: displayModel
              clip: true
              spacing: root.rowSpacing
              boundsBehavior: Flickable.StopAtBounds

              delegate: BorderSurface {
                id: row
                required property int index
                required property string itemId
                required property string kind
                required property string icon
                required property string iconFont
                required property string appIcon
                required property string label
                required property string target
                required property string detail
                required property string path
                required property string action
                required property int childCount
                required property bool disabled
                required property string desktopId

                width: ListView.view.width
                height: root.rowHeight
                radius: Style.cornerRadius
                color: root.cursorActive && row.index === root.selectedIndex ? root.selectedBackground : "transparent"
                borderSpec: root.cursorActive && row.index === root.selectedIndex ? root.selectedBorderSpec : Border.none()
                opacity: row.disabled ? 0.42 : 1

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Item {
                    width: Style.space(28)
                    height: parent.height

                    Text {
                      anchors.fill: parent
                      visible: row.kind !== "application"
                      text: row.icon
                      color: root.cursorActive && row.index === root.selectedIndex ? root.selectedText : root.foreground
                      font.family: row.iconFont || root.fontFamily
                      font.pixelSize: Style.font.icon
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                    }

                    Image {
                      anchors.fill: parent
                      anchors.margins: Style.space(2)
                      visible: row.kind === "application"
                      source: visible && root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }
                  }

                  Column {
                    width: parent.width - Style.space(58)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      width: parent.width
                      text: row.label
                      color: root.cursorActive && row.index === root.selectedIndex ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      visible: row.detail !== "" && root.filterText !== ""
                      text: row.detail
                      color: root.foreground
                      opacity: 0.5
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    width: Style.space(14)
                    text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                    color: root.cursorActive && row.index === root.selectedIndex ? root.selectedText : root.foreground
                    opacity: row.kind === "menu" || row.kind === "link" ? 0.5 : 0
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    verticalAlignment: Text.AlignVCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: !row.disabled
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectFromPointer(row.index)
                  onClicked: {
                    root.cursorActive = true
                    root.selectedIndex = row.index
                    root.activateIndex(row.index)
                  }
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: displayModel.count === 0
              text: root.filterText ? "No matches" : "Nothing here yet"
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          Text {
            width: parent.width
            visible: root.healthSummary !== ""
            text: root.healthSummary
            color: root.selectedText
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }
      }
    }

    onVisibleChanged: if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
}
