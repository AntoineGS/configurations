import QtQuick
import qs.Commons

SharedService {
  id: root

  property bool lifecycleRecorded: false

  onShellChanged: {
    if (root.shell && !root.lifecycleRecorded
        && typeof root.shell.recordTestServiceObjectCreated === "function") {
      root.lifecycleRecorded = true
      root.shell.recordTestServiceObjectCreated()
    }
  }

  Component.onDestruction: {
    if (root.lifecycleRecorded && root.shell
        && typeof root.shell.recordTestServiceObjectDestroyed === "function")
      root.shell.recordTestServiceObjectDestroyed()
  }
}
