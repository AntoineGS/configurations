import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "services"

Item {
  id: root

  readonly property string snapshotPath: Quickshell.env("REMOTE_PUBLISHER_FIXTURE_SNAPSHOT")
    || "/tmp/desktop-shell-remote-publisher-" + String(Date.now()) + "/missing/remote-bar.json"
  property string snapshotText: ""
  property int phase: 0
  property int checks: 0
  property bool started: false
  property bool previewProbeComplete: false
  property bool previewDirectoryMissing: false
  property string snapshotBeforePreview: ""
  property string settledSnapshotAfterStop: ""
  property var oldVmService: null
  property var destroyedVmService: null
  property int publicationCount: 0
  property int previewPublicationBaseline: 0
  property int stopPublicationBaseline: 0
  property int stopSettledPublicationCount: 0
  property bool stopSettlementObserved: false
  property var configuredDomains: ({
    "desktop.agents": true,
    "desktop.audio": true,
    "desktop.disk": true,
    "desktop.vm": true
  })
  property var publisherConfig: ({
    publish: true,
    host: "fixture-host",
    target: ""
  })
  property var agentsService: null
  property var audioService: null
  property var diskService: null
  property var vmService: null
  property var replacementService: null
  readonly property var replacementSummary: ({
    available: true,
    hostMemory: {
      available: true,
      stale: false,
      text: "M 31%",
      icon: "M",
      value: "31%",
      tooltip: "Replacement memory fixture",
      percent: 31
    },
    hostCpu: {
      available: true,
      stale: false,
      text: "C 84%",
      icon: "C",
      value: "84%",
      tooltip: "Replacement CPU fixture",
      percent: 84
    },
    runningVmCount: 2,
    vm: {
      visible: true,
      name: "replacement-vm",
      stale: false,
      error: "",
      cpuPercent: 63,
      memoryPercent: 52,
      showMemoryUsage: true
    }
  })

  QtObject {
    id: fakeShell
    property bool previewMode: true

    function widgetSettingsFor(pluginId) { return ({}) }

    function serviceFor(pluginId) {
      var id = String(pluginId || "")
      if (id === "desktop.agents") return root.agentsService
      if (id === "desktop.audio") return root.audioService
      if (id === "desktop.disk") return root.diskService
      if (id === "desktop.vm") return root.vmService
      return null
    }

    function serviceConfigured(pluginId) {
      return root.configuredDomains[String(pluginId || "")] === true
    }
  }

  component FixtureService: SharedService {
    property var remoteSummary: ({})
  }

  FixtureService {
    id: agentsFixtureService
    shell: fakeShell
    manifest: ({ id: "desktop.agents" })
    remoteSummary: ({
      available: true,
      text: "AI",
      tooltip: "Codex usage fixture",
      muted: false
    })
  }

  FixtureService {
    id: audioFixtureService
    shell: fakeShell
    manifest: ({ id: "desktop.audio" })
    remoteSummary: ({
      available: true,
      icon: "",
      volumePercent: 50,
      muted: false,
      deviceLabel: "USB",
      tooltip: "Volume: 50%\nUSB"
    })
  }

  FixtureService {
    id: diskFixtureService
    shell: fakeShell
    manifest: ({ id: "desktop.disk" })
    remoteSummary: ({
      available: true,
      text: "D 42%",
      icon: "D",
      value: "42%",
      tooltip: "Disk fixture",
      active: true,
      muted: false
    })
  }

  FixtureService {
    id: vmFixtureService
    shell: fakeShell
    manifest: ({ id: "desktop.vm" })
    remoteSummary: ({
      available: true,
      hostMemory: {
        available: true,
        stale: false,
        text: "M 24%",
        icon: "M",
        value: "24%",
        tooltip: "Memory fixture",
        percent: 24
      },
      hostCpu: {
        available: true,
        stale: false,
        text: "C 42%",
        icon: "C",
        value: "42%",
        tooltip: "CPU fixture",
        percent: 42
      },
      runningVmCount: 1,
      vm: {
        visible: true,
        name: "fixture-vm",
        stale: false,
        error: "",
        cpuPercent: 12,
        memoryPercent: 28,
        showMemoryUsage: true
      }
    })
  }

  Component {
    id: replacementComponent

    FixtureService {
      shell: fakeShell
      manifest: ({ id: "desktop.vm" })
      remoteSummary: root.replacementSummary
    }
  }

  RemoteBarService {
    id: publisher
    shell: fakeShell
    config: root.publisherConfig
    snapshotPath: root.snapshotPath
  }

  FileView {
    id: snapshotReader
    path: root.snapshotPath
    preload: true
    watchChanges: true
    blockWrites: true
    printErrors: false
    onLoaded: root.snapshotText = text()
    onLoadFailed: root.snapshotText = ""
    onFileChanged: reload()
  }

  Process {
    id: previewDirectoryProbe
    command: ["test", "!", "-d", publisher.snapshotDirectory]
    onExited: function(exitCode) {
      root.previewDirectoryMissing = Number(exitCode) === 0
      root.previewProbeComplete = true
    }
  }

  Connections {
    target: publisher.snapshotFile
    function onSaved() { root.publicationCount++ }
  }

  Timer {
    interval: 25
    repeat: true
    running: true
    onTriggered: {
      if (!root.started) return
      root.checks++
      root.advance()
      if (root.checks >= 400) {
        root.fail("watchdog expired at phase " + root.phase)
      }
    }
  }

  Component.onCompleted: {
    root.agentsService = agentsFixtureService
    root.audioService = audioFixtureService
    root.diskService = diskFixtureService
    root.vmService = vmFixtureService
    previewDirectoryProbe.running = true
    root.started = true
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  function readSnapshot() {
    try {
      var value = JSON.parse(String(root.snapshotText || ""))
      return value && typeof value === "object" ? value : null
    } catch (_) {
      return null
    }
  }

  function finish() {
    console.log("Remote publisher lifecycle fixture passed", root.checks)
    Qt.exit(0)
  }

  function fail(message) {
    console.error("remote-publisher-runtime-test: " + String(message),
      publisher.snapshotWritePending, publisher.publishDirectoryReady,
      publisher.agentsConsumer ? publisher.agentsConsumer.active : false,
      publisher.audioConsumer ? publisher.audioConsumer.active : false,
      publisher.diskConsumer ? publisher.diskConsumer.active : false,
      publisher.vmConsumer ? publisher.vmConsumer.active : false,
      publisher.snapshotWriteQueued, root.publicationCount,
      root.snapshotText)
    Qt.exit(1)
  }

  function advance() {
    try {
      snapshotReader.reload()

      if (root.phase === 0) {
        if (!root.previewProbeComplete) return
        check(root.previewDirectoryMissing, "preview construction leaves the snapshot directory absent")
        check(fakeShell.previewMode && !publisher.publisherActive, "publisher starts in preview mode")
        check(!publisher.publishDirectoryProcess.running, "preview does not start directory creation")
        check(!publisher.publishDirectoryReady, "preview does not mark the directory ready")
        check(!publisher.publishTimer.running, "preview does not start the publish timer")
        check(!publisher.snapshotWritePending && !publisher.snapshotWriteQueued,
          "preview does not queue a snapshot write")
        check(root.publicationCount === 0 && root.snapshotText === "",
          "preview does not publish a snapshot")
        check(agentsFixtureService.consumerCount === 0 && audioFixtureService.consumerCount === 0
            && diskFixtureService.consumerCount === 0 && vmFixtureService.consumerCount === 0,
          "preview does not demand any service")
        fakeShell.previewMode = false
        check(publisher.publisherActive, "publisher activates after preview ends")
        root.phase = 1
        return
      }

      if (root.phase === 1) {
        if (!publisher.agentsConsumer.ready || !publisher.vmConsumer.ready) return
        if (publisher.agentsService === null || publisher.vmService === null) return
        if (!publisher.publishDirectoryReady || publisher.snapshotWritePending) return
        check(publisher.publishTimer.running, "publisher timer starts after preview")
        check(publisher.sourceEnabled === false, "fixture does not start remote detection")
        check(agentsFixtureService.consumerCount === 1 && !agentsFixtureService.detailed,
          "publisher baseline demand for agents")
        check(audioFixtureService.consumerCount === 1 && !audioFixtureService.detailed,
          "publisher baseline demand for audio")
        check(diskFixtureService.consumerCount === 1 && !diskFixtureService.detailed,
          "publisher baseline demand for disk")
        check(vmFixtureService.consumerCount === 1 && !vmFixtureService.detailed,
          "publisher baseline demand for VM")
        var initial = root.readSnapshot()
        if (!initial) return
        check(initial.schemaVersion === 1, "remote schema preserved")
        check(initial.host === "fixture-host", "publisher host preserved")
        check(initial.widgets.vm.hostCpu.value === "42%", "shared CPU sample published")
        check(initial.widgets.audio.volumePercent === 50, "audio summary published")
        root.phase = 2
        return
      }

      if (root.phase === 2) {
        if (root.oldVmService !== null) return
        root.oldVmService = root.vmService
        root.replacementService = replacementComponent.createObject(root)
        root.vmService = null
        check(root.oldVmService.consumerCount === 0, "old VM service loses publisher demand")
        check(publisher.vmService === null, "null VM service is unavailable to publisher")
        publisher.publishSnapshot()
        root.phase = 3
        return
      }

      if (root.phase === 3) {
        if (publisher.snapshotWritePending) return
        var nullServiceSnapshot = root.readSnapshot()
        if (!nullServiceSnapshot || JSON.stringify(nullServiceSnapshot.widgets.vm) !== "{}") return
        check(root.oldVmService.consumerCount === 0, "null VM service keeps old demand detached")
        check(root.replacementService !== null, "VM replacement service is created")
        root.vmService = root.replacementService
        root.phase = 4
        return
      }

      if (root.phase === 4) {
        if (root.replacementService.consumerCount !== 1 || publisher.snapshotWritePending) return
        publisher.publishSnapshot()
        root.phase = 5
        return
      }

      if (root.phase === 5) {
        if (publisher.snapshotWritePending) return
        var replacement = root.readSnapshot()
        if (!replacement || replacement.widgets.vm.hostCpu.value !== "84%") return
        check(replacement.widgets.vm.vm.name === "replacement-vm", "replacement VM summary published")
        root.destroyedVmService = root.replacementService
        root.destroyedVmService.destroy()
        root.phase = 6
        return
      }

      if (root.phase === 6) {
        if (publisher.vmConsumer.service !== null || publisher.vmConsumer.attachedService !== null) return
        check(publisher.vmConsumer.service === null && publisher.vmConsumer.attachedService === null,
          "service invalidation removes the publisher consumer")
        root.replacementService = null
        root.vmService = null
        check(publisher.vmService === null, "destroyed VM service is unavailable to publisher")
        if (publisher.snapshotWritePending) return
        publisher.publishSnapshot()
        root.phase = 7
        return
      }

      if (root.phase === 7) {
        if (publisher.snapshotWritePending) return
        var destroyedSnapshot = root.readSnapshot()
        if (!destroyedSnapshot || JSON.stringify(destroyedSnapshot.widgets.vm) !== "{}") return
        root.snapshotBeforePreview = root.snapshotText
        root.previewPublicationBaseline = root.publicationCount
        fakeShell.previewMode = true
        check(!publisher.publisherActive, "attached publisher deactivates in preview")
        check(agentsFixtureService.consumerCount === 0 && audioFixtureService.consumerCount === 0
            && diskFixtureService.consumerCount === 0,
          "preview detaches attached service demand")
        check(!publisher.publishTimer.running, "preview stops the publish timer")
        publisher.publishSnapshot()
        check(!publisher.snapshotWritePending && !publisher.snapshotWriteQueued,
          "preview does not queue a write after attachment")
        root.phase = 8
        return
      }

      if (root.phase === 8) {
        check(root.publicationCount === root.previewPublicationBaseline,
          "preview does not publish after attachment")
        check(root.snapshotText === root.snapshotBeforePreview,
          "preview leaves the last snapshot unchanged")
        fakeShell.previewMode = false
        root.phase = 9
        return
      }

      if (root.phase === 9) {
        if (!publisher.publisherActive || !publisher.publishTimer.running) return
        if (agentsFixtureService.consumerCount !== 1 || audioFixtureService.consumerCount !== 1
            || diskFixtureService.consumerCount !== 1) return
        root.configuredDomains = Object.assign({}, root.configuredDomains, { "desktop.disk": false })
        root.phase = 10
        return
      }

      if (root.phase === 10) {
        if (diskFixtureService.consumerCount !== 0 || publisher.diskConsumer.active) return
        if (publisher.snapshotWritePending) return
        publisher.publishSnapshot()
        root.phase = 11
        return
      }

      if (root.phase === 11) {
        if (publisher.snapshotWritePending || publisher.snapshotWriteQueued) return
        var disabled = root.readSnapshot()
        if (!disabled || JSON.stringify(disabled.widgets.disk) !== "{}") return
        agentsFixtureService.remoteSummary = Object.assign({}, agentsFixtureService.remoteSummary, {
          tooltip: "Codex stop fixture " + String(root.publicationCount)
        })
        root.stopPublicationBaseline = root.publicationCount
        publisher.publishSnapshot()
        check(publisher.snapshotWritePending, "stop test starts an in-flight write")
        publisher.publishSnapshot()
        check(publisher.snapshotWriteQueued, "stop test queues a second write while pending")
        root.publisherConfig = ({ publish: false, host: "fixture-host", target: "" })
        root.stopSettlementObserved = false
        root.phase = 12
        return
      }

      if (root.phase === 12) {
        if (publisher.snapshotWritePending || publisher.snapshotWriteQueued) return
        check(root.publicationCount === root.stopPublicationBaseline + 1,
          "stop accepts only the first in-flight publication")
        check(agentsFixtureService.consumerCount === 0, "agents demand stops with publishing")
        check(audioFixtureService.consumerCount === 0, "audio demand stops with publishing")
        check(diskFixtureService.consumerCount === 0, "disk demand stops with publishing")
        check(!publisher.publisherActive, "publisher stops after config disable")
        check(!publisher.publishTimer.running, "publish timer stops with publishing")
        if (!root.stopSettlementObserved) {
          root.stopSettlementObserved = true
          root.stopSettledPublicationCount = root.publicationCount
          root.settledSnapshotAfterStop = root.snapshotText
          publisher.publishSnapshot()
          check(!publisher.snapshotWritePending && !publisher.snapshotWriteQueued,
            "stopped publisher rejects new writes")
          return
        }
        check(root.publicationCount === root.stopSettledPublicationCount,
          "stopped publisher has no later publications")
        check(root.snapshotText === root.settledSnapshotAfterStop,
          "stopped publisher output remains stable")
        finish()
      }
    } catch (error) {
      root.fail(error && error.message ? error.message : error)
    }
  }
}
