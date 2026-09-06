import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "plugins/bar"
import "plugins/panels/disk" as Disk

Item {
  id: root

  property int observedTicks: 0
  property var dynamicConsumer: null
  property var reloadService: null
  property bool dynamicDestroyStarted: false
  property bool dynamicDestroyCompleted: false
  property bool reloadDestroyStarted: false
  property bool reloadDestroyCompleted: false
  property var installedDiskService: null
  property string diskSharedLogText: ""
  property string diskCustomLogText: ""
  property string diskClickLogText: ""
  property bool diskClickRequested: false
  property bool diskClickReadStarted: false
  property bool diskDisabled: false
  property int diskSharedLinesBeforeDisable: -1
  readonly property var firstSample: first.service ? first.service.sample : null
  readonly property var secondSample: second.service ? second.service.sample : null
  readonly property string diskExecutable: Qt.resolvedUrl("tests/fixtures/disk/fake-status")
    .toString().replace("file://", "")
  readonly property string diskSharedLogPath: Quickshell.env("DISK_FIXTURE_SHARED_LOG")
  readonly property string diskCustomLogPath: Quickshell.env("DISK_FIXTURE_CUSTOM_LOG")
  readonly property string diskClickLogPath: Quickshell.env("DISK_FIXTURE_CLICK_LOG")
  readonly property var legacyDiskEntry: ({
    id: "disk",
    type: "command",
    exec: "desktop-shell-status disk",
    interval: 300,
    text: "legacy disk fallback",
    tooltip: "legacy disk tooltip",
    keepSpace: true,
    horizontalMargin: 3,
    verticalPadding: 4,
    fontSize: 11,
    onClick: "printf '%s' fixture-click > \"$DISK_FIXTURE_CLICK_LOG\"",
    onMiddleClick: "",
    onRightClick: ""
  })
  readonly property var newDiskEntry: ({ id: "desktop.disk" })
  readonly property var customDiskEntry: ({
    id: "disk",
    type: "command",
    exec: root.diskExecutable + " disk-custom",
    interval: 1
  })

  QtObject {
    id: fakeShell

    property bool previewMode: false
    property bool barVisible: false
    property var remoteBarService: null

    function widgetSettingsFor(pluginId) {
      return ({})
    }

    function serviceFor(pluginId) {
      return String(pluginId || "") === "desktop.disk" ? root.installedDiskService : null
    }
  }

  QtObject {
    id: fakeBarWidgetRegistry
    property var widgets: ({})
  }

  Component {
    id: diskWidgetComponent
    Disk.BarWidget { }
  }

  Bar {
    id: diskBar
    shellPath: ""
    barWidgetRegistry: fakeBarWidgetRegistry
    barConfig: ({
      centerAnchor: "desktop.clock",
      layout: { left: [], center: [], right: [] }
    })
    shell: fakeShell
    testEntries: [root.legacyDiskEntry, root.legacyDiskEntry,
      root.newDiskEntry, root.newDiskEntry, root.customDiskEntry]
  }

  Disk.Service {
    id: diskService
    shell: fakeShell
    manifest: ({ id: "desktop.disk" })
    statusExecutable: root.diskExecutable
    processStartGraceInterval: 50
  }

  FileView {
    id: diskSharedLog
    path: root.diskSharedLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.diskSharedLogText = text()
    onFileChanged: reload()
  }

  FileView {
    id: diskCustomLog
    path: root.diskCustomLogPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.diskCustomLogText = text()
    onFileChanged: reload()
  }

  Process {
    id: diskClickReader
    command: ["cat", root.diskClickLogPath]
    stdout: StdioCollector {
      id: diskClickReaderOutput
      waitForEnd: true
    }
    onExited: {
      root.diskClickLogText = diskClickReaderOutput.text || ""
      if (root.diskClickLogText === "") root.diskClickReadStarted = false
    }
  }

  component FakeSharedService: SharedService {
    property int sampleCounter: 0
    property var sample: null

    Timer {
      interval: 15
      repeat: true
      running: parent.collecting
      onTriggered: {
        parent.sampleCounter++
        parent.sample = ({ sequence: parent.sampleCounter })
      }
    }
  }

  FakeSharedService {
    id: source
    shell: fakeShell
    manifest: ({ id: "source" })
  }

  FakeSharedService {
    id: replacement
    shell: fakeShell
    manifest: ({ id: "replacement" })
  }

  Component {
    id: fakeServiceComponent

    FakeSharedService {
      shell: fakeShell
      manifest: ({ id: "reload" })
    }
  }

  ServiceConsumer {
    id: first
    service: null
  }

  ServiceConsumer {
    id: second
    service: null
  }

  Component {
    id: consumerComponent

    ServiceConsumer { }
  }

  Timer {
    interval: 0
    running: true
    repeat: false
    onTriggered: root.run()
  }

  Timer {
    id: observationTimer
    interval: 10
    repeat: true
    onTriggered: root.observeSample()
  }

  Timer {
    id: diskObservationTimer
    interval: 10
    repeat: true
    onTriggered: root.observeDiskScenario()
  }

  Timer {
    id: dynamicDestroyCheckTimer
    interval: 10
    repeat: true
    onTriggered: {
      if (source.consumerCount !== 1) return
      stop()
      root.continueAfterDynamicDestroy()
    }
  }

  Timer {
    id: reloadDestroyCheckTimer
    interval: 10
    repeat: true
    onTriggered: {
      if (first.service !== null || first.attachedService !== null) return
      stop()
      root.continueAfterReloadDestroy()
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: false
    onTriggered: root.fail("watchdog expired")
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  function nonEmptyLines(text) {
    return String(text || "").split("\n").filter(function(line) { return line !== "" })
  }

  function diskSlotFor(entry, ordinal) {
    var matches = []
    var slots = diskBar.moduleSlots || []
    var expectedType = entry.id === "disk"
      ? (entry.exec === "desktop-shell-status disk" ? "" : "command") : ""
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] && slots[i].moduleName === String(entry.id || "")
          && slots[i].customType === expectedType) matches.push(slots[i])
    }
    return matches[ordinal] || null
  }

  function checkTwoConsumers() {
    first.service = source
    second.service = source
    check(source.consumerCount === 2, "two distinct consumers")
    first.details = true
    second.details = true
    first.active = false
    check(source.consumerCount === 1 && source.detailed, "second consumer retains demand")
    second.service = replacement
    check(source.consumerCount === 0, "old service detached")
    check(replacement.consumerCount === 1 && replacement.detailed, "replacement attached")
    second.active = false
    check(!replacement.collecting, "last consumer stops collection")
  }

  function checkIdempotentUpdates() {
    first.active = true
    first.service = source
    first.details = false
    check(source.consumerCount === 1 && !source.detailed, "consumer attaches without detail demand")
    first.service = source
    first.active = true
    first.details = false
    check(source.consumerCount === 1 && !source.detailed, "idempotent consumer updates")

    var dynamic = consumerComponent.createObject(root)
    check(dynamic !== null, "dynamic consumer created")
    dynamic.service = source
    check(source.consumerCount === 2, "dynamic consumer attaches")
    dynamicConsumer = dynamic
    dynamicDestroyStarted = true
    dynamic.destroy()
    dynamicDestroyCheckTimer.start()
  }

  function continueAfterDynamicDestroy() {
    try {
      check(source.consumerCount === 1, "destroyed consumer detaches")
      check(dynamicDestroyStarted, "dynamic destruction was scheduled")
      check(!reloadDestroyStarted, "dynamic destruction completes before reload case")
      dynamicDestroyCompleted = true
      dynamicConsumer = null
      checkNullServiceDuringReload()
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }

  function checkNullServiceDuringReload() {
    check(dynamicDestroyCompleted, "reload case waits for dynamic destruction")
    var reloadService = fakeServiceComponent.createObject(root)
    check(reloadService !== null, "reload service created")
    root.reloadService = reloadService
    first.service = root.reloadService
    check(root.reloadService.consumerCount === 1, "reload service receives consumer")
    reloadDestroyStarted = true
    root.reloadService.destroy()
    reloadDestroyCheckTimer.start()
  }

  function continueAfterReloadDestroy() {
    try {
      check(first.service === null, "destroyed service reference is cleared")
      check(first.attachedService === null, "consumer detaches after service destruction")
      check(reloadDestroyStarted, "reload destruction was scheduled")
      check(dynamicDestroyCompleted, "dynamic destruction completed before reload destruction")
      reloadDestroyCompleted = true
      root.reloadService = null
      checkPreviewMode()
      checkPendingAction()
      beginSampleObservation()
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }

  function checkPreviewMode() {
    first.service = source
    fakeShell.previewMode = true
    check(!source.collecting, "preview mode suppresses collection")
    fakeShell.previewMode = false
    check(source.collecting, "normal mode restores collection demand")
    first.active = false
  }

  function checkPendingAction() {
    first.service = null
    source.operationPending = true
    check(source.consumerCount === 0, "pending action has no consumer demand")
    check(source.collecting, "pending action retains collection")
    source.operationPending = false
    check(!source.collecting, "completed action stops collection")
  }

  function beginSampleObservation() {
    first.active = true
    second.active = true
    first.details = false
    second.details = false
    first.service = source
    second.service = source
    source.sampleCounter = 0
    source.sample = null
    root.observedTicks = 0
    observationTimer.start()
  }

  function observeSample() {
    try {
      if (source.sampleCounter < 1) return
      root.observedTicks++
      check(firstSample !== null && secondSample !== null, "both consumers receive a sample")
      check(firstSample === secondSample, "consumers observe the same sample identity")
      check(firstSample === source.sample, "consumers observe the collector sample")
      check(dynamicDestroyCompleted && reloadDestroyCompleted, "destruction cases completed before sampling")
      check(root.observedTicks === 1, "one shared sample observation")
      observationTimer.stop()
      root.installedDiskService = diskService
      fakeBarWidgetRegistry.widgets = ({ "desktop.disk": { component: diskWidgetComponent } })
      diskObservationTimer.start()
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }

  function observeDiskScenario() {
    try {
      diskSharedLog.reload()
      diskCustomLog.reload()

      if (root.diskDisabled) {
        if (diskService.consumerCount !== 0 || diskService.collecting) return
        var disabledSharedLines = root.nonEmptyLines(root.diskSharedLogText)
        if (disabledSharedLines.length !== root.diskSharedLinesBeforeDisable) return
        diskObservationTimer.stop()
        console.log("Shared service disk slot fixture passed", disabledSharedLines.length,
          root.nonEmptyLines(root.diskCustomLogText).length)
        Qt.exit(0)
        return
      }

      var legacyFirstSlot = root.diskSlotFor(root.legacyDiskEntry, 0)
      var legacySecondSlot = root.diskSlotFor(root.legacyDiskEntry, 1)
      var newFirstSlot = root.diskSlotFor(root.newDiskEntry, 0)
      var newSecondSlot = root.diskSlotFor(root.newDiskEntry, 1)
      var customSlot = root.diskSlotFor(root.customDiskEntry, 0)
      if (!legacyFirstSlot || !legacySecondSlot || !newFirstSlot || !newSecondSlot || !customSlot) return
      var widgets = [legacyFirstSlot.activeItem, legacySecondSlot.activeItem,
        newFirstSlot.activeItem, newSecondSlot.activeItem]
      if (widgets.some(function(widget) { return !widget })) return
      if (!customSlot.activeItem || !root.installedDiskService) return
      if (diskService.consumerCount !== 4 || !diskService.outputText) return

      var sharedLines = root.nonEmptyLines(root.diskSharedLogText)
      var customLines = root.nonEmptyLines(root.diskCustomLogText)
      if (sharedLines.length !== 1 || customLines.length < 1) return
      if (diskService.refreshGeneration !== 1 || diskService.refreshFinalizedGeneration !== 1) return

      for (var i = 0; i < widgets.length; i++) {
        var widget = widgets[i]
        if (widget.diskService !== diskService
            || widget.outputText !== "D 42%"
            || widget.outputIcon !== "D"
            || widget.outputValue !== "42%"
            || widget.outputTooltip !== "Disk fixture"
            || widget.outputActive !== true
            || widget.outputMuted !== false) return
      }
      root.check(diskService.remoteSummary.available === true, "disk remote summary is available")
      root.check(diskService.remoteSummary.text === "D 42%", "disk remote summary text")
      root.check(diskService.remoteSummary.value === "42%", "disk remote summary value")
      root.check(customSlot.activeItem.outputText === "custom disk", "custom disk keeps its collector")

      if (!root.diskClickRequested) {
        root.diskClickRequested = true
        legacyFirstSlot.activeItem.triggerPress(Qt.LeftButton)
        return
      }
      if (root.diskClickLogText === "" && !root.diskClickReadStarted) {
        root.diskClickReadStarted = true
        diskClickReader.running = true
        return
      }
      if (root.diskClickLogText !== "fixture-click") return

      if (!root.diskDisabled) {
        root.diskSharedLinesBeforeDisable = sharedLines.length
        root.diskDisabled = true
        fakeBarWidgetRegistry.widgets = ({})
        return
      }

    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }

  function fail(message) {
    console.error("shared-service-runtime-test: " + String(message),
      root.observedTicks, diskBar.moduleSlots.length, diskService.consumerCount,
      diskService.refreshGeneration, root.diskSharedLogText, root.diskCustomLogText,
      root.diskClickLogText, diskService.outputText)
    Qt.exit(1)
  }

  function run() {
    try {
      checkTwoConsumers()
      checkIdempotentUpdates()
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }
}
