import QtQuick
import qs.Commons
import qs.Ui

BarMetricButton {
  id: root

  property string moduleName: ""
  property var settings: ({})
  readonly property var diskService: bar && bar.shell ? bar.shell.serviceFor("desktop.disk") : null
  readonly property string outputText: diskService ? String(diskService.outputText || "") : ""
  readonly property string outputIcon: diskService ? String(diskService.outputIcon || "") : ""
  readonly property string outputValue: diskService ? String(diskService.outputValue || "") : ""
  readonly property string outputTooltip: diskService ? String(diskService.outputTooltip || "") : ""
  readonly property bool outputActive: !!diskService && diskService.outputActive === true
  readonly property bool outputMuted: !!diskService && diskService.outputMuted === true

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    return root.diskService ? root.diskService.refresh() : false
  }

  text: root.outputText || String(root.setting("text", ""))
  iconText: root.outputIcon
  valueText: root.outputValue
  tooltipText: root.outputTooltip || String(root.setting("tooltip", ""))
  active: root.outputActive
  dimmed: root.outputMuted
  keepSpace: root.setting("keepSpace", false) === true
  horizontalMargin: Number(root.setting("horizontalMargin", 7.5))
  verticalPadding: Number(root.setting("verticalPadding", 6))
  fontSize: Number(root.setting("fontSize", bar && bar.fontSize ? bar.fontSize : Style.font.body))

  onPressed: function(button) {
    var command = button === Qt.RightButton
      ? String(root.setting("onRightClick", ""))
      : (button === Qt.MiddleButton ? String(root.setting("onMiddleClick", "")) : String(root.setting("onClick", "")))
    if (command && root.bar) root.bar.run(command)
  }

  ServiceConsumer {
    id: serviceConsumer
    service: root.diskService
    active: true
  }
}
