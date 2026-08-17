import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "PolkitModel.js" as PolkitModel

Item {
  id: root

  property bool registrationEnabled: Quickshell.env("DESKTOP_SHELL_POLKIT_REGISTER") !== "0"
  property string objectPath: "/org/desktop_shell/PolkitAgent"
  property bool polkitRegistered: false
  property string polkitError: ""
  property string pamError: ""

  property string fontFamily: Style.font.menuFamily
  property color accent: Color.polkit.accent
  property color background: Color.polkit.background
  property color foreground: Color.polkit.text
  property color border: Color.polkit.border
  property color borderError: Color.polkit.borderError
  property var borderSpec: Border.surfaceSpec(
    "polkit",
    root.errorFlash ? "border-error" : "border",
    root.errorFlash ? root.borderError : root.border,
    Math.max(1, Style.space(2)),
    "border-alpha"
  )
  property color scrim: Color.polkit.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int fieldHeight: Math.max(Style.space(42), Style.spacing.controlHeight)

  property var screenList: Quickshell.screens
  readonly property var activeScreen: root.screenList.length > 0 ? root.screenList[0] : null
  readonly property var polkitBackend: polkitLoader.item
  readonly property var flow: root.polkitBackend ? root.polkitBackend.flow : null

  property bool closing: false
  property bool submitted: false
  property string currentMessage: ""
  property string currentPrompt: ""
  property string currentSupplementary: ""
  property bool responseRequired: false
  property bool responseVisible: false
  property bool failed: false
  property bool errorFlash: false
  property bool fingerprintConfigured: false
  property int shakeOffset: 0

  readonly property bool dialogVisible: !!root.polkitBackend && root.polkitBackend.isActive || root.closing
  readonly property bool fingerprintPrompt: PolkitModel.promptLooksFingerprint(
    root.currentPrompt + " " + root.currentSupplementary
  )
  readonly property bool fingerprintMode: (root.fingerprintConfigured || root.fingerprintPrompt)
    && root.dialogVisible && !root.responseRequired && !root.submitted && !root.errorFlash
  readonly property int cardHeight: panel.height > 0
    ? Math.min(root.fieldHeight + root.contentMargin * 2, panel.height - Style.gapsOut * 2)
    : root.fieldHeight + root.contentMargin * 2
  readonly property int cardWidth: root.fingerprintMode
    ? root.cardHeight
    : Math.min(
        Style.space(312),
        Math.max(Style.space(260), panel.width - Style.gapsOut * 2)
      )

  function authorizationLabel(message) {
    return PolkitModel.authorizationLabel(message)
  }

  function loadPamConfig(raw) {
    root.fingerprintConfigured = PolkitModel.fingerprintConfiguredFromPamConfig(raw)
  }

  function loaderError() {
    if (polkitLoader.status !== Loader.Error) return ""
    var detail = polkitLoader.errorString()
    return detail ? String(detail) : "polkit backend failed to load"
  }

  function syncRegistrationState() {
    var backend = root.polkitBackend
    var state = PolkitModel.registrationState(
      root.registrationEnabled,
      !!backend && !!backend.isRegistered,
      root.loaderError()
    )
    root.polkitRegistered = state.registered
    root.polkitError = state.error
  }

  function resetSnapshot() {
    root.currentMessage = ""
    root.currentPrompt = ""
    root.currentSupplementary = ""
    root.responseRequired = false
    root.responseVisible = false
    root.failed = false
    root.errorFlash = false
    root.submitted = false
    passwordInput.text = ""
  }

  function syncFromFlow() {
    var currentFlow = root.flow
    if (!currentFlow) return

    root.currentMessage = String(currentFlow.message || "Authentication is needed...")
    root.currentPrompt = String(currentFlow.inputPrompt || "")
    root.currentSupplementary = String(currentFlow.supplementaryMessage || "")
    root.responseRequired = !!currentFlow.isResponseRequired
    root.responseVisible = !!currentFlow.responseVisible
    root.failed = !!currentFlow.failed

    if (root.responseRequired) root.submitted = false
  }

  function beginFlow() {
    closeTimer.stop()
    root.closing = false
    root.submitted = false
    passwordInput.text = ""
    root.syncFromFlow()
    Qt.callLater(root.refocus)
  }

  function refocus() {
    if (!root.dialogVisible || !root.activeScreen) return
    if (root.fingerprintMode) keyCatcher.forceActiveFocus()
    else passwordInput.forceActiveFocus()
  }

  function submitResponse() {
    var flow = root.flow
    if (!flow || !flow.isResponseRequired) return
    var password = String(passwordInput.text || "")
    if (password.length === 0) return

    root.submitted = true
    root.errorFlash = false
    flow.submit(password)
    passwordInput.text = ""
    keyCatcher.forceActiveFocus()
  }

  function cancelRequest() {
    var flow = root.flow
    passwordInput.text = ""
    root.submitted = false
    root.closing = true
    closeTimer.restart()
    if (flow) flow.cancelAuthenticationRequest()
  }

  function triggerFailureFeedback() {
    root.submitted = false
    root.errorFlash = true
    passwordInput.text = ""
    errorTimer.restart()
    shakeAnimation.restart()
    Qt.callLater(root.refocus)
  }

  Timer {
    id: closeTimer
    interval: 300
    repeat: false
    onTriggered: {
      root.closing = false
      root.resetSnapshot()
    }
  }

  Timer {
    id: errorTimer
    interval: 1200
    repeat: false
    onTriggered: root.errorFlash = false
  }

  SequentialAnimation {
    id: shakeAnimation
    NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
  }

  FileView {
    id: pamFile
    path: "/etc/pam.d/polkit-1"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.pamError = ""
      root.loadPamConfig(text())
    }
    onLoadFailed: function(error) {
      root.pamError = "failed to read /etc/pam.d/polkit-1: " + String(error)
      root.fingerprintConfigured = false
    }
    onFileChanged: reload()
  }

  Loader {
    id: polkitLoader
    active: root.registrationEnabled
    sourceComponent: Component {
      PolkitAgent {
        id: nativeAgent
        path: root.objectPath

        Connections {
          target: nativeAgent.flow

          function onIsResponseRequiredChanged() {
            root.syncFromFlow()
            if (!root.flow || !root.flow.isResponseRequired) passwordInput.text = ""
            Qt.callLater(root.refocus)
          }

          function onInputPromptChanged() { root.syncFromFlow() }
          function onResponseVisibleChanged() { root.syncFromFlow() }
          function onSupplementaryMessageChanged() { root.syncFromFlow() }
          function onFailedChanged() { root.syncFromFlow() }

          function onAuthenticationFailed() {
            root.syncFromFlow()
            root.triggerFailureFeedback()
          }

          function onAuthenticationSucceeded() {
            root.closing = true
            closeTimer.restart()
          }

          function onAuthenticationRequestCancelled() {
            root.closing = true
            closeTimer.restart()
          }
        }

        onAuthenticationRequestStarted: root.beginFlow()
        onIsActiveChanged: {
          if (isActive) root.syncFromFlow()
          else if (!root.closing) root.resetSnapshot()
        }
        onIsRegisteredChanged: root.syncRegistrationState()
      }
    }
    onStatusChanged: {
      root.syncRegistrationState()
      if (status === Loader.Error)
        console.warn("desktop-shell polkit agent load failed:", root.loaderError())
    }
  }

  onRegistrationEnabledChanged: root.syncRegistrationState()
  onActiveScreenChanged: if (root.dialogVisible) Qt.callLater(root.refocus)

  Component.onCompleted: root.syncRegistrationState()

  PanelWindow {
    id: panel
    visible: root.dialogVisible && root.activeScreen !== null
    screen: root.activeScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "desktop-shell-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.refocus()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.shakeOffset
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: root.refocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.cancelRequest()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.responseRequired) root.submitResponse()
            event.accepted = true
          }
        }
      }

      OpticalGlyph {
        anchors.centerIn: parent
        width: Math.round(root.fieldHeight * 0.7)
        height: width
        visible: root.fingerprintMode
        text: "\udb80\ude37"
        fontFamily: root.fontFamily
        fontSize: Math.round(root.fieldHeight * 0.7)
        color: root.errorFlash ? Color.polkit.textError : root.accent
      }

      Row {
        id: cardRow
        visible: !root.fingerprintMode
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(14)

        Text {
          text: "\uf023"
          color: root.errorFlash ? Color.polkit.textError : root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
          width: Style.space(26)
          height: root.fieldHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Item {
          width: parent.width - Style.space(40)
          height: root.fieldHeight

          TextInput {
            id: passwordInput
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            activeFocusOnPress: true
            clip: true
            selectionColor: Util.alpha(root.accent, 0.45)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
            echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
            passwordCharacter: "\u2022"
            color: root.errorFlash ? Color.polkit.textError : root.foreground
            cursorVisible: activeFocus && !root.submitted && !root.errorFlash
            readOnly: root.submitted || root.errorFlash
            enabled: root.dialogVisible
            onAccepted: root.submitResponse()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelRequest()
                event.accepted = true
              }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.errorFlash ? "Wrong" : (root.submitted ? "Checking..." : "Enter password")
            color: root.errorFlash ? Color.polkit.textError : root.foreground
            opacity: root.errorFlash ? 1 : 0.36
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
            elide: Text.ElideRight
            visible: passwordInput.text.length === 0
          }

          Rectangle {
            width: Math.max(1, Style.space(2))
            height: Style.space(24)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: root.errorFlash ? Color.polkit.textError : root.foreground
            visible: passwordInput.visible && passwordInput.activeFocus && passwordInput.text.length === 0
              && !root.submitted && !root.errorFlash
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            enabled: passwordInput.visible
            onClicked: passwordInput.forceActiveFocus()
          }
        }
      }
    }

    BorderSurface {
      width: Math.min(justificationText.implicitWidth + Style.space(24), panel.width - Style.gapsOut * 2)
      height: Style.space(28)
      anchors.horizontalCenter: card.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: Style.space(10)
      radius: root.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("polkit", "border", root.border, Math.max(1, Style.space(2)), "border-alpha")

      Text {
        id: justificationText
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        text: root.authorizationLabel(root.currentMessage)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideMiddle
      }
    }
  }
}
