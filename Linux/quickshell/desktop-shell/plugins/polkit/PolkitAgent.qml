import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "PolkitModel.js" as PolkitModel

Item {
  id: root

  property bool registrationEnabled: Quickshell.env("DESKTOP_SHELL_POLKIT_REGISTER") === "1"
  readonly property bool testSurfaceSuppressed: Quickshell.env("DESKTOP_SHELL_TEST_NO_SURFACES") === "1"
  property string objectPath: "/org/desktop_shell/PolkitAgent"
  property bool polkitRegistered: false
  property string polkitError: ""
  property string pamError: ""
  readonly property string pamProbeCommand: {
    var override = String(Quickshell.env("DESKTOP_SHELL_POLKIT_PAM_HELPER") || "")
    if (/^\//.test(override)) return override
    var home = String(Quickshell.env("HOME") || "")
    return home + "/.local/share/helpers/desktop-shell-polkit-pam"
  }

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
  readonly property string focusedMonitorName: Hyprland.focusedMonitor
    ? String(Hyprland.focusedMonitor.name || "") : ""
  readonly property var activeScreen: PolkitModel.screenForMonitor(root.screenList, root.focusedMonitorName)
  readonly property var polkitBackend: polkitLoader.item
  readonly property var flow: root.polkitBackend ? root.polkitBackend.flow : null

  property bool closing: false
  property bool submitted: false
  property string currentMessage: ""
  property string currentActionId: ""
  property string currentPrompt: ""
  property string currentSupplementary: ""
  property bool responseRequired: false
  property bool responseVisible: false
  property bool failed: false
  property bool errorFlash: false
  property bool fingerprintConfigured: false
  property bool pamProbeQueued: false
  property int pamProbeAttempt: 0
  property int pamProbeProcessAttempt: 0
  property bool pamProbeAttemptActive: false
  property bool pamProbeAttemptStarted: false
  property bool pamProbeAttemptExited: false
  property int pamProbeStartCheckAttempt: 0
  property int pamProbeTimeoutAttempt: 0
  property int pamProbeGraceAttempt: 0
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

  function refreshPamProbe() {
    if (pamProbe.running || root.pamProbeAttemptActive) {
      root.pamProbeQueued = true
      return
    }
    root.pamProbeQueued = false
    root.pamProbeAttempt += 1
    root.pamProbeProcessAttempt = root.pamProbeAttempt
    root.pamProbeAttemptActive = true
    root.pamProbeAttemptStarted = false
    root.pamProbeAttemptExited = false
    root.pamProbeStartCheckAttempt = 0
    root.pamProbeTimeoutAttempt = 0
    root.pamProbeGraceAttempt = 0
    pamProbe.running = true
    if (!pamProbe.running) {
      root.schedulePamProbeStartCheck(root.pamProbeAttempt)
      return
    }
    if (!root.pamProbeAttemptActive) return
    root.pamProbeTimeoutAttempt = root.pamProbeAttempt
    pamProbeTimeout.restart()
  }

  function boundedPamError(detail) {
    var prefix = "fingerprint PAM probe failed"
    var normalized = String(detail || "").replace(/\s+/g, " ").trim()
    var maximumDetailLength = 256 - prefix.length - 2
    if (normalized.length > maximumDetailLength) normalized = normalized.slice(0, maximumDetailLength)
    return prefix + (normalized.length > 0 ? ": " + normalized : "")
  }

  function isCurrentPamProbeAttempt(attempt) {
    return root.pamProbeAttemptActive
      && Number(attempt) === root.pamProbeAttempt
      && root.pamProbeProcessAttempt === root.pamProbeAttempt
  }

  function checkPamProbeStart(attempt) {
    if (!root.isCurrentPamProbeAttempt(attempt) || pamProbe.running) return
    if (root.pamProbeAttemptStarted || root.pamProbeAttemptExited) return
    root.failPamProbeAttempt(attempt, "helper is missing or not executable")
  }

  function schedulePamProbeStartCheck(attempt) {
    if (!root.isCurrentPamProbeAttempt(attempt)) return
    root.pamProbeStartCheckAttempt = attempt
    Qt.callLater(function() {
      if (root.pamProbeStartCheckAttempt !== attempt) return
      root.pamProbeStartCheckAttempt = 0
      root.checkPamProbeStart(attempt)
    })
  }

  function failPamProbeAttempt(attempt, detail) {
    if (!root.isCurrentPamProbeAttempt(attempt)) return false
    root.pamProbeAttemptExited = true
    root.pamProbeAttemptActive = false
    root.pamProbeStartCheckAttempt = 0
    root.pamProbeTimeoutAttempt = 0
    root.pamProbeGraceAttempt = 0
    pamProbeTimeout.stop()
    pamProbeGraceTimer.stop()
    root.fingerprintConfigured = false
    root.pamError = root.boundedPamError(detail)
    if (root.pamProbeQueued) {
      root.pamProbeQueued = false
      Qt.callLater(root.refreshPamProbe)
    }
    return true
  }

  function applyPamProbe(exitCode, output, errorOutput) {
    var result = PolkitModel.fingerprintConfiguredFromProbeOutput(output)
    if (Number(exitCode) !== 0 || result === null) {
      root.fingerprintConfigured = false
      root.pamError = root.boundedPamError(errorOutput)
      return
    }
    root.pamError = ""
    root.fingerprintConfigured = result
  }

  function loaderError() {
    return polkitLoader.status === Loader.Error ? "polkit backend failed to load" : ""
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

  // AuthFlow exposes actionId but not a requester PID or application identity;
  // the dialog therefore shows only its native message and trusted action ID.
  function clearPassword() {
    if (passwordInput) passwordInput.text = ""
  }

  // Clearing the TextInput synchronously is the strongest available boundary;
  // QML/JavaScript string copies cannot be guaranteed to be zeroized in memory.
  function finishRequest() {
    root.clearPassword()
    root.resetSnapshot()
    root.closing = true
    closeTimer.restart()
  }

  function handleBackendInactive() {
    root.clearPassword()
    root.resetSnapshot()
  }

  function resetSnapshot() {
    root.currentMessage = ""
    root.currentActionId = ""
    root.currentPrompt = ""
    root.currentSupplementary = ""
    root.responseRequired = false
    root.responseVisible = false
    root.failed = false
    root.errorFlash = false
    root.submitted = false
  }

  function syncFromFlow() {
    var currentFlow = root.flow
    if (!currentFlow) return

    root.currentPrompt = String(currentFlow.inputPrompt || "")
    root.currentSupplementary = String(currentFlow.supplementaryMessage || "")
    root.responseRequired = !!currentFlow.isResponseRequired
    root.responseVisible = !!currentFlow.responseVisible
    root.failed = !!currentFlow.failed

    if (root.responseRequired) root.submitted = false
  }

  function beginFlow() {
    var currentFlow = root.flow
    if (!currentFlow) return
    closeTimer.stop()
    root.resetSnapshot()
    root.closing = false
    root.submitted = false
    root.clearPassword()
    var context = PolkitModel.snapshotAuthContext(currentFlow.message, currentFlow.actionId)
    root.currentMessage = context.message || "Authentication is needed..."
    root.currentActionId = context.actionId
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
    root.clearPassword()
    keyCatcher.forceActiveFocus()
  }

  function cancelRequest() {
    var flow = root.flow
    root.submitted = false
    root.finishRequest()
    if (flow) flow.cancelAuthenticationRequest()
  }

  function triggerFailureFeedback() {
    root.submitted = false
    root.errorFlash = true
    root.clearPassword()
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
      root.clearPassword()
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

  Process {
    id: pamProbe
    command: [root.pamProbeCommand]
    stdout: StdioCollector {
      id: pamProbeStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: pamProbeStderr
      waitForEnd: true
    }
    onStarted: {
      if (!root.pamProbeAttemptActive || root.pamProbeProcessAttempt !== root.pamProbeAttempt) return
      root.pamProbeAttemptStarted = true
    }

    onRunningChanged: {
      if (pamProbe.running) return
      var attempt = root.pamProbeProcessAttempt
      if (!root.isCurrentPamProbeAttempt(attempt)) return
      if (root.pamProbeAttemptStarted || root.pamProbeAttemptExited) return
      root.schedulePamProbeStartCheck(attempt)
    }

    onExited: function(exitCode) {
      var attempt = root.pamProbeProcessAttempt
      if (!root.isCurrentPamProbeAttempt(attempt)) return
      root.pamProbeAttemptExited = true
      root.pamProbeAttemptActive = false
      root.pamProbeStartCheckAttempt = 0
      root.pamProbeTimeoutAttempt = 0
      root.pamProbeGraceAttempt = 0
      pamProbeTimeout.stop()
      pamProbeGraceTimer.stop()
      root.applyPamProbe(exitCode, pamProbeStdout.text || "", pamProbeStderr.text || "")
      if (!root.pamProbeQueued) return
      root.pamProbeQueued = false
      root.refreshPamProbe()
    }
  }

  Timer {
    id: pamProbeTimeout
    interval: 2000
    repeat: false
    onTriggered: {
      var attempt = root.pamProbeTimeoutAttempt
      if (attempt !== root.pamProbeAttempt || !root.pamProbeAttemptActive) return
      root.pamProbeTimeoutAttempt = 0
      if (!pamProbe.running) return
      pamProbe.signal(15)
      if (!root.isCurrentPamProbeAttempt(attempt) || !pamProbe.running) return
      root.pamProbeGraceAttempt = attempt
      pamProbeGraceTimer.restart()
    }
  }

  Timer {
    id: pamProbeGraceTimer
    interval: 500
    repeat: false
    onTriggered: {
      var attempt = root.pamProbeGraceAttempt
      if (attempt !== root.pamProbeAttempt || !root.pamProbeAttemptActive) return
      root.pamProbeGraceAttempt = 0
      if (pamProbe.running) pamProbe.signal(9)
    }
  }

  Timer {
    id: pamRefreshTimer
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.refreshPamProbe()
  }

  IpcHandler {
    target: "desktop.polkit"

    function refreshPamProbe(): string {
      root.refreshPamProbe()
      return "ok"
    }
  }

  Loader {
    id: polkitLoader
    active: root.registrationEnabled
    sourceComponent: Component {
      Item {
        id: backendContainer

        readonly property var flow: nativeAgent.flow
        readonly property bool isActive: nativeAgent.isActive
        readonly property bool isRegistered: nativeAgent.isRegistered

        PolkitAgent {
          id: nativeAgent
          path: root.objectPath

          onAuthenticationRequestStarted: root.beginFlow()
          onIsActiveChanged: {
            if (isActive) root.syncFromFlow()
            else root.handleBackendInactive()
          }
          onFlowChanged: if (!flow) root.handleBackendInactive()
          onIsRegisteredChanged: root.syncRegistrationState()
        }

        Connections {
          target: nativeAgent.flow

          function onIsResponseRequiredChanged() {
            root.syncFromFlow()
            if (!root.flow || !root.flow.isResponseRequired) root.clearPassword()
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
            root.finishRequest()
          }

          function onAuthenticationRequestCancelled() {
            root.finishRequest()
          }
        }
      }
    }
    onStatusChanged: {
      root.syncRegistrationState()
      if (status === Loader.Error) {
        root.handleBackendInactive()
        console.warn("desktop-shell polkit agent load failed:", root.loaderError())
      }
    }
    onItemChanged: if (!item) root.handleBackendInactive()
  }

  onRegistrationEnabledChanged: root.syncRegistrationState()
  onPamProbeCommandChanged: root.refreshPamProbe()
  onActiveScreenChanged: if (root.dialogVisible) Qt.callLater(root.refocus)

  Component.onCompleted: {
    root.syncRegistrationState()
    root.refreshPamProbe()
  }

  PanelWindow {
    id: panel
    visible: !root.testSurfaceSuppressed && root.dialogVisible && root.activeScreen !== null
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
      id: contextCard
      width: Math.min(Style.space(520), Math.max(Style.space(260), panel.width - Style.gapsOut * 2))
      height: contextColumn.implicitHeight + Style.space(12)
      anchors.horizontalCenter: card.horizontalCenter
      anchors.bottom: card.top
      anchors.bottomMargin: Style.space(10)
      radius: root.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("polkit", "border", root.border, Math.max(1, Style.space(2)), "border-alpha")
      visible: root.dialogVisible && (root.currentMessage !== "" || root.currentActionId !== "")

      Column {
        id: contextColumn
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        anchors.topMargin: Style.space(6)
        anchors.bottomMargin: Style.space(6)
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: "Request message: " + root.authorizationLabel(root.currentMessage)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
        }

        Text {
          id: actionIdText
          width: parent.width
          text: "Trusted action ID: " + root.currentActionId
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
        }
      }
    }
  }
}
