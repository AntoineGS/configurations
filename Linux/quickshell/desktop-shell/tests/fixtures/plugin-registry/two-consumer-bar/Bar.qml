import QtQuick
import qs.Commons

Item {
  id: root

  property var shell: null
  property bool secondaryVmConsumerActive: true
  readonly property var vmService: root.shell ? root.shell.serviceFor("desktop.vm") : null
  readonly property int vmConsumerCount: root.vmService && typeof root.vmService.consumerCount === "number"
    ? root.vmService.consumerCount : 0
  readonly property bool vmConsumersAttached: !!root.vmService
    && vmLeftConsumer.ready && vmRightConsumer.ready
    && vmLeftConsumer.attachedService === root.vmService
    && vmRightConsumer.attachedService === root.vmService
    && root.vmConsumerCount === 2
  readonly property var vmLeftSample: vmLeftConsumer.attachedService
    ? vmLeftConsumer.attachedService.state : null
  readonly property var vmRightSample: vmRightConsumer.attachedService
    ? vmRightConsumer.attachedService.state : null
  readonly property bool vmConsumersShareSample: root.vmConsumersAttached
    && root.vmLeftSample !== null && root.vmLeftSample === root.vmRightSample
  readonly property bool vmSampleAvailable: root.vmConsumersShareSample
    && root.vmLeftSample.confirmedRunning === true
  readonly property bool vmCollecting: !!root.vmService && root.vmService.collecting === true
  readonly property int vmWatcherCount: root.vmService && root.vmService.watcherRunning ? 1 : 0

  readonly property var hotplugService: root.shell
    ? root.shell.serviceFor("acme.discovered-service") : null
  readonly property bool hotplugConsumerAttached: !!root.hotplugService
    && hotplugConsumer.ready && hotplugConsumer.attachedService === root.hotplugService
  readonly property bool hotplugCollecting: !!root.hotplugService && root.hotplugService.collecting === true

  ServiceConsumer {
    id: vmLeftConsumer
    service: root.vmService
    details: true
  }

  ServiceConsumer {
    id: vmRightConsumer
    service: root.vmService
    active: root.secondaryVmConsumerActive
    details: true
  }

  ServiceConsumer {
    id: hotplugConsumer
    service: root.hotplugService
  }
}
