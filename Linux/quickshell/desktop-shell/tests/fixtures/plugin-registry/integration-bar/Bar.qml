import QtQuick
import qs.Commons

Item {
  id: root

  property var shell: null
  readonly property var serviceIds: [
    "desktop.agents",
    "desktop.audio",
    "desktop.bluetooth",
    "desktop.configuration-updates",
    "desktop.disk",
    "desktop.host-metrics",
    "desktop.monitor",
    "desktop.network",
    "desktop.power",
    "desktop.recording",
    "desktop.tailscale",
    "desktop.vm",
    "desktop.workspaces"
  ]
  readonly property var consumers: [
    agentsConsumer,
    audioConsumer,
    bluetoothConsumer,
    configurationUpdatesConsumer,
    diskConsumer,
    hostMetricsConsumer,
    monitorConsumer,
    networkConsumer,
    powerConsumer,
    recordingConsumer,
    tailscaleConsumer,
    vmConsumer,
    workspacesConsumer
  ]
  readonly property bool allServiceConsumersAttached: {
    if (!root.shell) return false
    for (var i = 0; i < root.consumers.length; i++) {
      var consumer = root.consumers[i]
      var service = root.shell.serviceFor(root.serviceIds[i])
      if (!service || !consumer.ready || consumer.attachedService !== service
          || typeof service.consumerCount !== "number" || service.consumerCount < 1) return false
    }
    return true
  }

  ServiceConsumer {
    id: agentsConsumer
    service: root.shell ? root.shell.serviceFor("desktop.agents") : null
  }
  ServiceConsumer {
    id: audioConsumer
    service: root.shell ? root.shell.serviceFor("desktop.audio") : null
  }
  ServiceConsumer {
    id: bluetoothConsumer
    service: root.shell ? root.shell.serviceFor("desktop.bluetooth") : null
  }
  ServiceConsumer {
    id: configurationUpdatesConsumer
    service: root.shell ? root.shell.serviceFor("desktop.configuration-updates") : null
  }
  ServiceConsumer {
    id: diskConsumer
    service: root.shell ? root.shell.serviceFor("desktop.disk") : null
  }
  ServiceConsumer {
    id: hostMetricsConsumer
    service: root.shell ? root.shell.serviceFor("desktop.host-metrics") : null
  }
  ServiceConsumer {
    id: monitorConsumer
    service: root.shell ? root.shell.serviceFor("desktop.monitor") : null
  }
  ServiceConsumer {
    id: networkConsumer
    service: root.shell ? root.shell.serviceFor("desktop.network") : null
  }
  ServiceConsumer {
    id: powerConsumer
    service: root.shell ? root.shell.serviceFor("desktop.power") : null
  }
  ServiceConsumer {
    id: recordingConsumer
    service: root.shell ? root.shell.serviceFor("desktop.recording") : null
  }
  ServiceConsumer {
    id: tailscaleConsumer
    service: root.shell ? root.shell.serviceFor("desktop.tailscale") : null
  }
  ServiceConsumer {
    id: vmConsumer
    service: root.shell ? root.shell.serviceFor("desktop.vm") : null
  }
  ServiceConsumer {
    id: workspacesConsumer
    service: root.shell ? root.shell.serviceFor("desktop.workspaces") : null
  }
}
