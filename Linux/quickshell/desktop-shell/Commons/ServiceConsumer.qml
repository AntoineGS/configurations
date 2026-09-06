import QtQml

QtObject {
  id: consumer

  property var service: null
  property bool active: true
  property bool details: false
  property var attachedService: null
  property bool ready: false

  function sync() {
    if (!ready) return
    var next = active ? service : null
    if (attachedService && attachedService !== next)
      attachedService.removeConsumer(consumer)
    attachedService = next
    if (attachedService) attachedService.setConsumer(consumer, details)
  }

  onServiceChanged: sync()
  onActiveChanged: sync()
  onDetailsChanged: sync()

  property Connections serviceDestroyedConnection: Connections {
    target: consumer.service
    ignoreUnknownSignals: true

    function onInvalidated() {
      consumer.attachedService = null
      consumer.service = null
    }
  }

  Component.onCompleted: { ready = true; sync() }
  Component.onDestruction: {
    ready = false
    if (attachedService) attachedService.removeConsumer(consumer)
  }
}
