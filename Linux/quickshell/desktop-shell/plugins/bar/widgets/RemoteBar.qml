import QtQuick
import qs.Commons
import qs.Ui
import "../../panels/vm/Model.js" as VmModel

BarWidget {
  id: root

  moduleName: "desktop.remote-bar"
  readonly property var service: bar && bar.shell ? bar.shell.remoteBarService : null
  property string screenName: ""
  readonly property int modeRevision: service ? service.modeRevision : 0
  readonly property bool screenEligible: {
    var revision = root.modeRevision
    return !!service && service.screenEligible(screenName)
  }
  readonly property bool remoteSelected: {
    var revision = root.modeRevision
    return !!service && service.screenRemoteSelected(screenName)
  }
  readonly property bool remoteFresh: !!service && service.health === "fresh"
  readonly property color remoteColor: "#fab387"
  readonly property var agents: service ? service.agents : ({})
  readonly property var audio: service ? service.audio : ({})
  readonly property var disk: service ? service.disk : ({})
  readonly property var vm: service ? service.vm : ({})
  readonly property var hostMemory: vm && vm.hostMemory ? vm.hostMemory : ({})
  readonly property var hostCpu: vm && vm.hostCpu ? vm.hostCpu : ({})
  readonly property var guest: vm && vm.vm ? vm.vm : ({})
  readonly property color statForeground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property bool guestMemoryCritical: VmModel.memoryCritical(root.guest.memoryPercent)
  readonly property string guestTooltip: root.guest.stale
    ? String(root.guest.name || "VM") + " (stale): " + String(root.guest.error || "")
    : String(root.guest.name || "VM")

  visible: !!service && screenEligible
  implicitWidth: visible ? content.implicitWidth : 0
  implicitHeight: visible ? content.implicitHeight : 0

  Row {
    id: content
    spacing: 0

    WidgetButton {
      bar: root.bar
      text: root.remoteSelected ? "Remote" : "Local"
      tooltipText: root.service ? root.service.modeTooltip(root.screenName) : ""
      foreground: root.remoteSelected ? root.remoteColor : (root.bar ? root.bar.barForeground : Color.foreground)
      horizontalMargin: 6
      onPressed: function(button) {
        if (button === Qt.LeftButton && root.service)
          root.service.setRemoteSelected(root.screenName, !root.remoteSelected)
      }
    }

    WidgetButton {
      visible: root.remoteSelected && root.service && root.service.warning
      bar: root.bar
      text: "!"
      tooltipText: root.service ? root.service.modeTooltip(root.screenName) : ""
      foreground: root.bar ? root.bar.urgent : Color.urgent
      horizontalMargin: 2
      pressable: false
    }

    WidgetButton {
      visible: root.remoteSelected && root.agents.available === true && String(root.agents.text || "") !== ""
      bar: root.bar
      text: String(root.agents.text || "")
      tooltipText: String(root.agents.tooltip || "")
      dimmed: !root.remoteFresh || root.agents.muted === true
      pressable: false
    }

    BarMetricButton {
      visible: root.remoteSelected && root.audio.available === true
      bar: root.bar
      iconText: String(root.audio.icon || "")
      tooltipText: String(root.audio.tooltip || "")
      dimmed: !root.remoteFresh || root.audio.muted === true
      pressable: false
    }

    BarMetricButton {
      visible: root.remoteSelected && root.disk.available === true
      bar: root.bar
      iconText: String(root.disk.icon || "")
      valueText: String(root.disk.value || "")
      tooltipText: String(root.disk.tooltip || "")
      dimmed: !root.remoteFresh || root.disk.muted === true
      pressable: false
    }

    BarMetricButton {
      visible: root.remoteSelected && root.hostMemory.available === true
      bar: root.bar
      iconText: String(root.hostMemory.icon || "")
      valueText: String(root.hostMemory.value || "")
      tooltipText: String(root.hostMemory.tooltip || "")
      dimmed: !root.remoteFresh || root.hostMemory.stale === true
      pressable: false
    }

    WidgetButton {
      visible: root.remoteSelected && root.vm.available === true
        && root.guest.visible === true && root.guest.showMemoryUsage === true
      bar: root.bar
      text: VmModel.vmMetricText(root.guest.memoryPercent)
      tooltipText: root.guestTooltip
      foreground: root.guestMemoryCritical ? root.urgent : root.statForeground
      dimmed: !root.remoteFresh || !root.guestMemoryCritical
      horizontalMargin: 1
      pressable: false
    }

    BarMetricButton {
      visible: root.remoteSelected && root.hostCpu.available === true
      bar: root.bar
      iconText: String(root.hostCpu.icon || "")
      valueText: String(root.hostCpu.value || "")
      tooltipText: String(root.hostCpu.tooltip || "")
      dimmed: !root.remoteFresh || root.hostCpu.stale === true
      pressable: false
    }

    WidgetButton {
      visible: root.remoteSelected && root.vm.available === true && root.guest.visible === true
      bar: root.bar
      text: VmModel.vmMetricText(root.guest.cpuPercent)
      tooltipText: root.guestTooltip
      foreground: root.statForeground
      dimmed: true
      horizontalMargin: 1
      pressable: false
    }
  }
}
