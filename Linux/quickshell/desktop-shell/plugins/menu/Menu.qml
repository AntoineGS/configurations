import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
import "../../services/CalculatorProvider.js" as CalculatorProvider

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
  property bool calculatorFocused: false
  property int calculatorSerial: 0
  property string calculatorPendingQuery: ""
  property string calculatorResult: ""
  property string calculatorResultQuery: ""
  property string menuMode: "menu"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string requestDir: ""
  property string pendingAction: ""
  property bool closingDetailsVisible: false
  property real animatedListHeight: listHeight
  property real measuredRouteContentWidth: 0
  property real browseRouteContentWidth: 0
  property real animatedCardWidth: boundedCardWidth
  property bool hasVisibleIcons: false
  property bool hasVisibleChevrons: false
  property real iconColumnWidth: hasVisibleIcons ? Style.space(28) : 0
  property real iconColumnGap: hasVisibleIcons ? Style.space(8) : 0
  property real chevronColumnWidth: hasVisibleChevrons ? Style.space(14) : 0
  property real chevronColumnGap: hasVisibleChevrons ? Style.space(8) : 0
  property string motionState: "closed"
  property real materialXScale: 0
  property real materialYScale: 0
  property real surfaceOpacity: 0
  property real seedOpacity: 0
  property real searchOpacity: 0
  property real resultsOpacity: 0
  property real scrimOpacity: 0
  property real closeTargetXScale: 0
  property real closeTargetYScale: 0
  property bool preparingCardHeight: false
  property bool routeWidthReady: false
  property bool preparingCardWidth: false
  property bool pendingCardFinalization: false
  property int readinessGeneration: 0
  property bool listTransitionsEnabled: motionState === "open"

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property bool dmenuActive: root.menuMode === "input" || root.menuMode === "select"
  readonly property bool rowDetailsVisible: root.motionState !== "closed"
    && (root.filterText.trim() !== "" || root.dmenuActive || root.closingDetailsVisible)
  readonly property bool requestActive: root.dmenuActive && root.requestDir !== ""
  readonly property bool surfaceVisible: menuReady
    && (opened || motionState !== "closed" || surfaceOpacity > 0)
  readonly property real seedSize: Style.space(8)
  readonly property real seedXScale: seedSize / Math.max(1, card.width)
  readonly property real seedYScale: seedSize / Math.max(1, card.height)
  readonly property real searchCenterY: contentMargin + Style.space(17)

  readonly property var routeWidgets: ({
    "setup.power-profile": "desktop.power",
    "setup.monitors": "desktop.monitor"
  })
  readonly property var whenResults: MenuModel.routeVisibility(
    root.shell && root.shell.barConfig ? root.shell.barConfig.layout : null,
    root.routeWidgets)

  readonly property color foreground: Color.barPanels.text
  readonly property color secondaryForeground: Color.barPanels.secondaryText
  readonly property color accent: Color.accent
  readonly property color scrim: Color.modal.scrim
  readonly property string fontFamily: Style.font.family
  readonly property int contentMargin: Style.spacing.popupPadding
  readonly property int rowHeight: Math.max(Style.space(42), Style.font.body + Style.spacing.rowPaddingX * 2)
  readonly property int rowSpacing: Style.space(2)
  readonly property string searchPlaceholder: root.dmenuActive ? root.dmenuPrompt
    : root.calculatorFocused ? "Calculate…"
    : ((root.item(root.activeMenu) ? root.item(root.activeMenu).label : "Control") + "…")
  readonly property real outputWidth: panel.screen && panel.screen.width > 0
    ? panel.screen.width : Math.max(0, panel.width)
  readonly property real boundedCardWidth: MenuModel.adaptiveMenuWidth(
    root.measuredRouteContentWidth,
    root.contentMargin * 2,
    root.outputWidth,
    Style.gapsOut
  )
  readonly property int listHeight: Math.min(
    Math.max(rowHeight, displayModel.count * rowHeight + Math.max(0, displayModel.count - 1) * rowSpacing),
    Style.space(440)
  )
  readonly property real desiredCardHeight: root.contentMargin * 2 + Style.space(54) + root.animatedListHeight
    + (root.healthSummary ? Style.space(24) : 0)
  readonly property real cardHeight: panel.height > 0
    ? Math.min(root.desiredCardHeight, Math.max(1, panel.height - Style.gapsOut * 2))
    : root.desiredCardHeight
  readonly property real cardTop: MenuModel.launcherCardTop(panel.height, root.cardHeight, Style.gapsOut)

  function prepareCardHeight() {
    root.preparingCardHeight = true
    root.animatedListHeight = root.listHeight
    root.animatedListHeight = Qt.binding(function() { return root.listHeight })
    root.preparingCardHeight = false
  }

  Behavior on animatedListHeight {
    enabled: root.opened && !root.preparingCardHeight && Motion.enabled
    NumberAnimation {
      duration: Motion.spatialDuration
      easing.type: Motion.spatialEasing
    }
  }

  Behavior on animatedCardWidth {
    enabled: root.opened && root.routeWidthReady && !root.preparingCardWidth && Motion.enabled
    NumberAnimation {
      duration: Motion.spatialDuration
      easing.type: Motion.spatialEasing
    }
  }

  Behavior on iconColumnWidth {
    enabled: Motion.enabled
    NumberAnimation { duration: Motion.normalDuration; easing.type: Motion.spatialEasing }
  }

  Behavior on iconColumnGap {
    enabled: Motion.enabled
    NumberAnimation { duration: Motion.normalDuration; easing.type: Motion.spatialEasing }
  }

  Behavior on chevronColumnWidth {
    enabled: Motion.enabled
    NumberAnimation { duration: Motion.normalDuration; easing.type: Motion.spatialEasing }
  }

  Behavior on chevronColumnGap {
    enabled: Motion.enabled
    NumberAnimation { duration: Motion.normalDuration; easing.type: Motion.spatialEasing }
  }
  readonly property string healthSummary: {
    var health = root.shell && root.shell.healthState ? root.shell.healthState : null
    if (!health) return ""
    if (health.configValid === false) return "Shell config needs attention"
    if (health.pluginErrors && health.pluginErrors.length > 0) return "Shell health has warnings"
    return ""
  }

  FontMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.heading
  }

  FontMetrics {
    id: detailMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  FontMetrics {
    id: searchMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  function item(id) {
    return root.items[String(id || "")] || null
  }

  function rebuildItems() {
    var previousActiveMenu = root.activeMenu
    var merged = MenuModel.mergeMenuSources(root.menuItems, [])
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    root.menuReady = true
    if (!root.item(root.activeMenu)) root.activeMenu = "root"
    var activeMenuChanged = previousActiveMenu !== root.activeMenu
    if (root.opened && activeMenuChanged && root.filterText.trim() !== "")
      root.cacheBrowseRouteWidth(root.browseRows(root.activeMenu))
    if (root.opened && activeMenuChanged && root.filterText.trim() === "")
      root.rebuildDisplay(true, false, true)
    else if (root.opened) root.rebuildDisplay(false, false)
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
    root.syncResultSelection()
  }

  function syncResultSelection() {
    var target = root.cursorActive && root.selectedIndex < displayModel.count ? root.selectedIndex : -1
    if (resultList.currentIndex !== target) {
      resultList.currentIndex = target
      return
    }
    if (target >= 0 && resultList.currentItem !== resultList.itemAtIndex(target)) {
      resultList.currentIndex = -1
      resultList.currentIndex = target
    }
  }

  function currentDisplayRows() {
    var rows = []
    for (var i = 0; i < displayModel.count; i++) rows.push(displayModel.get(i))
    return rows
  }

  function applyDisplayRows(rows) {
    root.hasVisibleIcons = MenuModel.rowsHaveIcons(rows)
    root.hasVisibleChevrons = MenuModel.rowsHaveChevrons(rows)
    var operations = MenuModel.planRowReconciliation(root.currentDisplayRows(), rows)
    for (var i = 0; i < operations.length; i++) {
      var operation = operations[i]
      if (operation.type === "remove") displayModel.remove(operation.index)
      else if (operation.type === "move") displayModel.move(operation.from, operation.to, 1)
      else if (operation.type === "insert") displayModel.insert(operation.index, operation.row)
      else if (operation.type === "set") displayModel.set(operation.index, operation.row)
    }
  }

  function measuredTextWidth(metrics, text) {
    var width = Number(metrics.advanceWidth(String(text || "")))
    return isFinite(width) && width > 0 ? Math.ceil(width) : 0
  }

  function measureRouteContent(rows) {
    var values = Array.isArray(rows) ? rows : []
    var textWidth = 0
    for (var i = 0; i < values.length; i++) {
      var row = values[i] || {}
      textWidth = Math.max(
        textWidth,
        root.measuredTextWidth(labelMetrics, row.label),
        root.measuredTextWidth(detailMetrics, row.detail)
      )
    }

    var hasIcons = MenuModel.rowsHaveIcons(values)
    var hasChevrons = MenuModel.rowsHaveChevrons(values)
    var iconWidth = hasIcons ? Style.space(28) : 0
    var iconGap = hasIcons ? Style.space(8) : 0
    var chevronWidth = hasChevrons ? Style.space(14) : 0
    var chevronGap = hasChevrons ? Style.space(8) : 0
    var rowWidth = Style.space(16) + iconWidth + iconGap + textWidth + chevronWidth + chevronGap
    var promptLeftBorder = Math.max(
      Border.left(Border.controlSpec("normal", root.foreground, root.accent)),
      Border.left(Border.controlSpec("hover-cursor", root.foreground, root.accent)),
      Border.left(Border.controlSpec("focus", root.foreground, root.accent)))
    var promptRightBorder = Math.max(
      Border.right(Border.controlSpec("normal", root.foreground, root.accent)),
      Border.right(Border.controlSpec("hover-cursor", root.foreground, root.accent)),
      Border.right(Border.controlSpec("focus", root.foreground, root.accent)))
    var fieldWidth = root.measuredTextWidth(searchMetrics, root.searchPlaceholder)
      + searchField.horizontalPadding * 2 + promptLeftBorder + promptRightBorder
    return Math.max(rowWidth, fieldWidth)
  }

  function browseRows(route) {
    var rows = []
    for (var i = 0; i < root.itemOrder.length; i++) {
      var child = root.item(root.itemOrder[i])
      if (!child || child.parent !== route || !root.isVisible(child)) continue
      rows.push(root.displayRow(child, child.description, child.order, ""))
    }
    return rows
  }

  function cacheBrowseRouteWidth(rows) {
    root.browseRouteContentWidth = root.measureRouteContent(rows)
  }

  function captureRouteWidth(rows, snap, cacheBrowseWidth) {
    root.preparingCardWidth = snap === true
    root.measuredRouteContentWidth = root.measureRouteContent(rows)
    if (cacheBrowseWidth === true) root.browseRouteContentWidth = root.measuredRouteContentWidth
    if (snap === true) {
      root.animatedCardWidth = root.boundedCardWidth
      root.animatedCardWidth = Qt.binding(function() { return root.boundedCardWidth })
    }
    root.routeWidthReady = true
    root.preparingCardWidth = false
  }

  function settleCardWidth(targetWidth) {
    if (!root.routeWidthReady) return
    root.preparingCardWidth = true
    root.animatedCardWidth = targetWidth === undefined ? root.boundedCardWidth : targetWidth
    root.animatedCardWidth = Qt.binding(function() {
      return MenuModel.adaptiveMenuWidth(
        root.measuredRouteContentWidth,
        root.contentMargin * 2,
        root.outputWidth,
        Style.gapsOut)
    })
    root.preparingCardWidth = false
  }

  function rebuildDisplay(captureWidth, snapWidth, cacheBrowseWidth) {
    if (!root.menuReady) {
      root.applyDisplayRows([])
      return
    }

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var query = root.filterText.trim()

    if (root.dmenuActive) {
      var dmenuRows = root.menuMode === "select" ? MenuModel.dmenuRows(root.dmenuOptions, query) : []
      root.applyDisplayRows(dmenuRows)
      if (captureWidth === true) root.captureRouteWidth(dmenuRows, snapWidth === true, false)
      root.settleCursor()
      if (root.menuMode === "input") root.cursorActive = false
      root.syncResultSelection()
      Qt.callLater(root.syncResultSelection)
      return
    }

    var commandRows = []
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
      commandRows = root.browseRows(active)
    }

    var appRows = []
    if (query && active === "root" && root.appLibrary) {
      var applications = root.appLibrary.sortedEntries(query)
      for (var appIndex = 0; appIndex < applications.length; appIndex++) {
        var application = applications[appIndex]
        appRows.push(MenuModel.applicationRow(application.entry, root.appLibrary, application.score))
      }
    }

    var calculatorResult = null
    if (query && active === "root" && root.calculatorResult && root.calculatorResultQuery === query)
      calculatorResult = MenuModel.calculatorRow(query, root.calculatorResult, root.calculatorSerial)

    var rows = MenuModel.composeSearchResults(commandRows, appRows, calculatorResult)
    root.applyDisplayRows(rows)
    if (captureWidth === true)
      root.captureRouteWidth(rows, snapWidth === true, cacheBrowseWidth === true)
    root.settleCursor()
    Qt.callLater(root.syncResultSelection)
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
    root.syncResultSelection()
    resultList.positionViewAtIndex(target, ListView.Contain)
  }

  function selectHalfPage(delta) {
    var visibleRows = Math.max(1, Math.floor(resultList.height / (root.rowHeight + root.rowSpacing)))
    root.select(delta * Math.max(1, Math.floor(visibleRows / 2)))
  }

  function setFilter(nextFilter) {
    var wasSearching = root.filterText.trim() !== ""
    root.filterText = String(nextFilter || "")
    var isSearching = root.filterText.trim() !== ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (!root.dmenuActive) root.scheduleCalculator(root.filterText)
    if (root.dmenuActive || wasSearching === isSearching) {
      root.rebuildDisplay(false, false)
    } else if (isSearching) {
      root.rebuildDisplay(true, false, false)
    } else {
      root.rebuildDisplay(false, false)
      root.measuredRouteContentWidth = root.browseRouteContentWidth
    }
    Qt.callLater(function() {
      if (root.cursorActive && displayModel.count > 0)
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function scheduleCalculator(query) {
    root.calculatorSerial += 1
    root.calculatorPendingQuery = String(query || "").trim()
    root.calculatorResult = ""
    root.calculatorResultQuery = ""
    calculatorDebounce.stop()
    calculatorTimeout.stop()
    if (calculatorProcess.running) calculatorProcess.signal(15)
    if (CalculatorProvider.isExpressionLike(root.calculatorPendingQuery)) calculatorDebounce.restart()
  }

  function setActiveMenu(id, pushHistory) {
    var target = String(id || "")
    if (!root.item(target) || root.item(target).kind === "action") target = "root"
    if (pushHistory && target !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = target
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay(true, false, true)
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
    } else if (row.kind === "dmenu") {
      root.finishRequest(row.selection)
    } else if (row.kind === "application") {
      root.opened = false
      root.filterText = ""
      if (root.appLibrary) root.appLibrary.launch(row.desktopId)
    } else if (row.kind === "calculator") {
      root.opened = false
      root.filterText = ""
      Quickshell.execDetached(["wl-copy", "--type", "text/plain", row.label])
    } else {
      root.applySelected(row.action)
    }
  }

  function applySelected(action) {
    if (!MenuModel.isOpaqueActionId(action) || actionProcess.running || root.pendingAction) return
    root.pendingAction = String(action)
    root.opened = false
    root.filterText = ""
    actionDelay.restart()
  }

  function runAction(action) {
    if (!MenuModel.isOpaqueActionId(action) || actionProcess.running) return false
    actionProcess.command = ["desktop-shell-action", String(action)]
    actionProcess.running = true
    return true
  }

  function openExistingMenu(initialMenu) {
    var firstMaterialization = !root.surfaceVisible
    if (root.requestActive) root.finishRequest(null)
    root.menuMode = "menu"
    root.dmenuPrompt = ""
    root.dmenuOptions = []
    root.requestDir = ""
    root.activeMenu = root.item(initialMenu) ? initialMenu : "root"
    root.navStack = []
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (!firstMaterialization) root.opened = true
    root.rebuildDisplay(true, firstMaterialization, true)
    if (firstMaterialization) {
      root.prepareCardHeight()
      root.opened = true
    }
    if (root.appLibrary) root.appLibrary.refreshIcons()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function openDmenu(payload) {
    var firstMaterialization = !root.surfaceVisible
    if (root.requestActive) root.finishRequest(null)
    root.menuMode = payload.mode === "input" ? "input" : "select"
    root.dmenuPrompt = String(payload.prompt || (root.menuMode === "input" ? "Input" : "Select"))
    root.dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    root.requestDir = String(payload.requestDir || "")
    if (!root.requestDir) return "unknown"
    root.activeMenu = "root"
    root.navStack = []
    root.filterText = root.menuMode === "input" ? String(payload.initial || "") : ""
    root.selectedIndex = 0
    root.cursorActive = root.menuMode === "select"
    if (!firstMaterialization) root.opened = true
    root.rebuildDisplay(true, firstMaterialization)
    if (firstMaterialization) {
      root.prepareCardHeight()
      root.opened = true
    }
    Qt.callLater(function() { searchField.forceActiveFocus() })
    return "ok"
  }

  function finishRequest(selection) {
    if (!root.requestActive) return
    var activeRequestDir = root.requestDir
    root.requestDir = ""
    root.opened = false
    root.filterText = ""
    if (selection === null || selection === undefined)
      Quickshell.execDetached(["desktop-shell-menu-result", activeRequestDir, "cancel"])
    else
      Quickshell.execDetached(["desktop-shell-menu-result", activeRequestDir, "value", String(selection)])
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
    if (payload.mode === "input" || payload.mode === "select") return root.openDmenu(payload)
    root.calculatorFocused = payload.mode === "calculator"
    return root.openRoute(payload.initialMenu || payload.menu || "root")
  }

  function close() {
    if (root.requestActive) root.finishRequest(null)
    root.invalidateReadinessFinalization()
    root.opened = false
    root.filterText = ""
    root.calculatorFocused = false
    root.menuMode = "menu"
    root.requestDir = ""
    root.scheduleCalculator("")
  }

  function invalidateReadinessFinalization() {
    root.readinessGeneration += 1
    root.pendingCardFinalization = false
  }

  function scheduleReadinessFinalization() {
    root.readinessGeneration += 1
    root.pendingCardFinalization = true
    var generation = root.readinessGeneration
    Qt.callLater(function() {
      if (generation !== root.readinessGeneration || !root.pendingCardFinalization
          || !root.menuReady || !root.opened) return
      root.pendingCardFinalization = false
      root.rebuildDisplay(true, true, true)
      root.prepareCardHeight()
      root.beginOpenMotion()
      searchField.forceActiveFocus()
    })
  }

  function settleOpenMotion() {
    root.materialXScale = 1
    root.materialYScale = 1
    root.surfaceOpacity = 1
    root.seedOpacity = 0
    root.searchOpacity = 1
    root.resultsOpacity = 1
    root.scrimOpacity = 1
    root.motionState = "open"
  }

  function settleClosedMotion() {
    root.surfaceOpacity = 0
    root.seedOpacity = 0
    root.searchOpacity = 0
    root.resultsOpacity = 0
    root.scrimOpacity = 0
    root.closingDetailsVisible = false
    root.motionState = "closed"
  }

  function beginOpenMotion() {
    closeMotion.stop()
    root.closingDetailsVisible = false
    if (root.motionState === "closed") {
      root.materialXScale = root.seedXScale
      root.materialYScale = root.seedYScale
      root.surfaceOpacity = 0
      root.seedOpacity = 1
      root.searchOpacity = 0
      root.resultsOpacity = 0
      root.scrimOpacity = 0
    }
    root.motionState = "opening"
    if (!Motion.enabled) {
      root.settleOpenMotion()
      return
    }
    openMotion.restart()
  }

  function beginCloseMotion() {
    openMotion.stop()
    if (root.motionState === "closed") return
    root.closingDetailsVisible = root.filterText.trim() !== "" || root.dmenuActive
    root.closeTargetXScale = root.materialXScale * 0.98
    root.closeTargetYScale = root.materialYScale * 0.94
    root.motionState = "closing"
    if (!Motion.enabled) {
      root.settleClosedMotion()
      return
    }
    closeMotion.restart()
  }

  onWhenResultsChanged: if (root.opened) root.rebuildDisplay(false, false)

  onOutputWidthChanged: root.settleCardWidth(MenuModel.adaptiveMenuWidth(
    root.measuredRouteContentWidth,
    root.contentMargin * 2,
    root.outputWidth,
    Style.gapsOut))

  onOpenedChanged: {
    if (root.opened) {
      if (root.menuReady) root.beginOpenMotion()
    } else {
      root.invalidateReadinessFinalization()
      root.beginCloseMotion()
    }
  }

  onMenuReadyChanged: {
    if (!root.menuReady || !root.opened) return
    root.scheduleReadinessFinalization()
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.opened && root.activeMenu === "root" && root.filterText.trim()) root.rebuildDisplay(false, false)
    }
  }

  Connections {
    target: Motion

    function onEnabledChanged() {
      if (Motion.enabled) return
      openMotion.stop()
      closeMotion.stop()
      root.settleCardWidth()
      root.iconColumnWidth = root.hasVisibleIcons ? Style.space(28) : 0
      root.iconColumnWidth = Qt.binding(function() {
        return root.hasVisibleIcons ? Style.space(28) : 0
      })
      root.iconColumnGap = root.hasVisibleIcons ? Style.space(8) : 0
      root.iconColumnGap = Qt.binding(function() {
        return root.hasVisibleIcons ? Style.space(8) : 0
      })
      root.chevronColumnWidth = root.hasVisibleChevrons ? Style.space(14) : 0
      root.chevronColumnWidth = Qt.binding(function() {
        return root.hasVisibleChevrons ? Style.space(14) : 0
      })
      root.chevronColumnGap = root.hasVisibleChevrons ? Style.space(8) : 0
      root.chevronColumnGap = Qt.binding(function() {
        return root.hasVisibleChevrons ? Style.space(8) : 0
      })
      if (root.opened && (!root.menuReady || root.pendingCardFinalization)) {
        root.motionState = "closed"
      } else if (root.opened) {
        root.settleOpenMotion()
      }
      else root.settleClosedMotion()
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

  Timer {
    id: actionDelay
    interval: 100
    onTriggered: {
      var action = root.pendingAction
      root.pendingAction = ""
      root.runAction(action)
    }
  }

  ParallelAnimation {
    id: openMotion

    onFinished: root.settleOpenMotion()

    NumberAnimation {
      target: root
      property: "materialXScale"
      to: 1
      duration: Motion.normalDuration
      easing.type: Motion.spatialEasing
    }
    SequentialAnimation {
      PauseAnimation { duration: 80 }
      NumberAnimation {
        target: root
        property: "materialYScale"
        to: 1
        duration: Motion.spatialDuration
        easing.type: Motion.spatialEasing
      }
    }
    NumberAnimation {
      target: root
      property: "surfaceOpacity"
      to: 1
      duration: 80
      easing.type: Motion.effectEasing
    }
    NumberAnimation {
      target: root
      property: "seedOpacity"
      to: 0
      duration: 100
      easing.type: Motion.effectEasing
    }
    SequentialAnimation {
      PauseAnimation { duration: 80 }
      NumberAnimation {
        target: root
        property: "searchOpacity"
        to: 1
        duration: 100
        easing.type: Motion.effectEasing
      }
    }
    SequentialAnimation {
      PauseAnimation { duration: 140 }
      NumberAnimation {
        target: root
        property: "resultsOpacity"
        to: 1
        duration: Motion.normalDuration
        easing.type: Motion.effectEasing
      }
    }
    NumberAnimation {
      target: root
      property: "scrimOpacity"
      to: 1
      duration: Motion.spatialDuration
      easing.type: Motion.effectEasing
    }
  }

  ParallelAnimation {
    id: closeMotion

    onFinished: root.settleClosedMotion()

    NumberAnimation {
      target: root
      property: "surfaceOpacity"
      to: 0
      duration: Motion.fastDuration
      easing.type: Motion.exitEasing
    }
    NumberAnimation {
      target: root
      property: "searchOpacity"
      to: 0
      duration: 120
      easing.type: Motion.exitEasing
    }
    NumberAnimation {
      target: root
      property: "resultsOpacity"
      to: 0
      duration: 90
      easing.type: Motion.exitEasing
    }
    NumberAnimation {
      target: root
      property: "seedOpacity"
      to: 0
      duration: Motion.fastDuration
      easing.type: Motion.exitEasing
    }
    NumberAnimation {
      target: root
      property: "materialXScale"
      to: root.closeTargetXScale
      duration: Motion.fastDuration
      easing.type: Motion.exitEasing
    }
    NumberAnimation {
      target: root
      property: "materialYScale"
      to: root.closeTargetYScale
      duration: Motion.fastDuration
      easing.type: Motion.exitEasing
    }
    NumberAnimation {
      target: root
      property: "scrimOpacity"
      to: 0
      duration: Motion.fastDuration
      easing.type: Motion.exitEasing
    }
  }

  Timer {
    id: calculatorDebounce
    interval: 150
    onTriggered: {
      if (calculatorProcess.running) {
        calculatorDebounce.restart()
        return
      }
      calculatorProcess.requestSerial = root.calculatorSerial
      calculatorProcess.requestQuery = root.calculatorPendingQuery
      calculatorProcess.command = ["qalc", "-t", calculatorProcess.requestQuery]
      calculatorProcess.running = true
      calculatorTimeout.restart()
    }
  }

  Timer {
    id: calculatorTimeout
    interval: 1500
    onTriggered: if (calculatorProcess.running) calculatorProcess.signal(15)
  }

  Process {
    id: calculatorProcess
    property int requestSerial: 0
    property string requestQuery: ""
    property string output: ""
    command: []
    stdout: SplitParser {
      onRead: function(line) {
        if (calculatorProcess.output.length <= 4096)
          calculatorProcess.output += (calculatorProcess.output ? "\n" : "") + line
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: output = ""
    onExited: function(exitCode) {
      calculatorTimeout.stop()
      var result = Number(exitCode) === 0 ? CalculatorProvider.normalizeResult(output, 4096) : ""
      if (!result || !CalculatorProvider.shouldAcceptResult(requestSerial, root.calculatorSerial,
          requestQuery, root.filterText.trim())) return
      root.calculatorResult = result
      root.calculatorResultQuery = requestQuery
      if (root.opened) root.rebuildDisplay(false, false)
    }
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
    visible: root.surfaceVisible
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "desktop-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

      Rectangle {
        anchors.fill: parent
        color: root.scrim
        opacity: root.scrimOpacity

        MouseArea {
          anchors.fill: parent
          enabled: root.opened
          onClicked: root.close()
        }
      }

    Rectangle {
      id: materialSeed

      width: root.seedSize
      height: root.seedSize
      radius: width / 2
      x: Math.round(panel.width / 2 - width / 2)
      y: Math.round(root.cardTop + root.searchCenterY - height / 2)
      color: root.accent
      opacity: root.seedOpacity
    }

    Item {
      id: cardFrame

      width: root.animatedCardWidth
      height: root.cardHeight
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.cardTop
      opacity: root.surfaceOpacity

      transform: Scale {
        origin.x: cardFrame.width / 2
        origin.y: root.searchCenterY
        xScale: root.materialXScale
        yScale: root.materialYScale
      }

      PanelSurface {
        id: card

        anchors.fill: parent
        padding: root.contentMargin
        revealed: true
        motionEnabled: false

        MouseArea {
          anchors.fill: parent
          onClicked: {}
        }

        Item {
          id: content
          anchors.fill: parent
          anchors.margins: card.padding

        Column {
          anchors.fill: parent
          spacing: Style.space(10)

          TextField {
            id: searchField
            width: parent.width
            height: Style.space(34)
            text: root.filterText
            placeholderText: root.searchPlaceholder
            foreground: root.foreground
            accent: root.accent
            opacity: root.searchOpacity
            font.family: root.fontFamily
            Keys.priority: Keys.BeforeItem
            onTextEdited: if (text !== root.filterText) root.setFilter(text)

            Keys.onPressed: function(event) {
              var control = event.modifiers & Qt.ControlModifier
              if (control && event.key === Qt.Key_H) {
                root.goBack()
                event.accepted = true
              } else if (control && event.key === Qt.Key_J) {
                root.select(1)
                event.accepted = true
              } else if (control && event.key === Qt.Key_K) {
                root.select(-1)
                event.accepted = true
              } else if (control && event.key === Qt.Key_L) {
                if (root.cursorActive) root.activateIndex(root.selectedIndex)
                else root.settleCursor()
                event.accepted = true
              } else if (control && event.key === Qt.Key_U) {
                root.selectHalfPage(-1)
                event.accepted = true
              } else if (control && event.key === Qt.Key_D) {
                root.selectHalfPage(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (root.filterText) root.setFilter("")
                else if (!root.goBack()) root.close()
                event.accepted = true
              } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
                root.goBack()
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.select(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.select(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
                if (root.dmenuActive && root.menuMode === "input") root.finishRequest(root.filterText)
                else if (root.cursorActive) root.activateIndex(root.selectedIndex)
                else root.settleCursor()
                event.accepted = true
              }
            }
          }

          Item {
            width: parent.width
            height: root.animatedListHeight
            opacity: root.resultsOpacity

            AnimatedListView {
              id: resultList
              anchors.fill: parent
              model: displayModel
              clip: true
              spacing: root.rowSpacing
              boundsBehavior: Flickable.StopAtBounds
              transitionsEnabled: root.listTransitionsEnabled
              highlightFollowsCurrentItem: false

              highlight: CursorSurface {
                id: selectionHighlight

                width: resultList.width
                height: root.rowHeight
                y: root.selectedIndex * (root.rowHeight + resultList.spacing)
                hasCursor: true
                foreground: root.foreground
                accent: root.accent
                opacity: root.cursorActive && root.selectedIndex < displayModel.count ? 1 : 0

                Behavior on y {
                  enabled: Motion.enabled && resultList.transitionsEnabled
                  NumberAnimation {
                    duration: Motion.normalDuration
                    easing.type: Motion.spatialEasing
                  }
                }

                Behavior on opacity {
                  enabled: Motion.enabled
                  NumberAnimation {
                    duration: Motion.fastDuration
                    easing.type: Motion.effectEasing
                  }
                }
              }

              delegate: Item {
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
                required property string selection
                required property int childCount
                required property bool disabled
                required property string desktopId

                width: ListView.view.width
                height: root.rowHeight
                opacity: row.disabled ? 0.42 : 1

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: root.iconColumnGap

                  Item {
                    id: iconSlot
                    width: root.iconColumnWidth
                    height: parent.height
                    clip: true

                    Text {
                      anchors.fill: parent
                      visible: iconSlot.width > 0 && row.kind !== "application"
                      text: row.icon
                      color: root.foreground
                      font.family: row.iconFont || root.fontFamily
                      font.pixelSize: Style.font.icon
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                    }

                    Image {
                      anchors.fill: parent
                      anchors.margins: Style.space(2)
                      visible: iconSlot.width > 0 && row.kind === "application"
                      source: visible && root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }
                  }

                  Row {
                    width: parent.width - iconSlot.width - parent.spacing
                    height: parent.height
                    spacing: root.chevronColumnGap

                    Column {
                      width: parent.width - root.chevronColumnWidth - parent.spacing
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        width: parent.width
                        text: row.label
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.heading
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        visible: row.detail !== "" && root.rowDetailsVisible
                        text: row.detail
                        color: root.secondaryForeground
                        opacity: 0.5
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }
                    }

                    Text {
                      width: root.chevronColumnWidth
                      height: parent.height
                      text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                      color: root.secondaryForeground
                      opacity: text !== "" ? 0.5 : 0
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      verticalAlignment: Text.AlignVCenter
                    }
                  }
                }

              }
            }

            Text {
              anchors.centerIn: parent
              visible: displayModel.count === 0 && root.menuMode !== "input"
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
            color: root.secondaryForeground
            opacity: 0.75 * root.resultsOpacity
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
}
