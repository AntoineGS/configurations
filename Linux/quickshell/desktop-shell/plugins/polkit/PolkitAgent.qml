import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import qs.Commons
import qs.Ui
import "PolkitModel.js" as PolkitModel

Item {
  id: root

  property var shell: null
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

  property string fontFamily: Style.font.family
  property color accent: Color.polkit.accent
  property color foreground: Color.barPanels.text
  property color borderError: Color.polkit.borderError
  property var borderSpec: root.errorFlash
    ? Border.surfaceSpec("polkit", "border-error", root.borderError, Math.max(1, Style.space(2)), "border-alpha")
    : Border.surfaceSpec("bar-panels", "border", Color.barPanels.border, Math.max(1, Style.space(2)))
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
  readonly property bool contextVisible: root.currentMessage !== "" || root.currentActionId !== ""
  readonly property int authBodyHeight: root.fingerprintMode ? Style.space(112) : root.fieldHeight
  readonly property int authFixedHeight: panel.topSpacing + panel.contentPadding * 2
    + Border.top(root.borderSpec) + Border.bottom(root.borderSpec)
    + (root.contextVisible ? Style.space(10) : 0) + root.authBodyHeight
  readonly property int authHeaderHeight: root.contextVisible
    ? Math.max(0, Math.min(contextColumn.implicitHeight,
      panel.availableCardHeight - root.authFixedHeight)) : 0
  readonly property int authContentSpacing: root.authHeaderHeight > 0 ? Style.space(10) : 0
  readonly property int authCardWidth: Style.centeredMenuWidth(
    Style.space(520), panel.width - Style.gapsOut * 2)
  readonly property int authCardHeight: panel.topSpacing + panel.contentPadding * 2
    + Border.top(root.borderSpec) + Border.bottom(root.borderSpec)
    + root.authHeaderHeight + root.authContentSpacing + root.authBodyHeight

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

  TopBarOverlay {
    id: panel
    overlayId: "desktop.polkit"
    layerNamespace: "desktop-shell-polkit"
    shell: root.shell
    screen: root.activeScreen
    opened: !root.testSurfaceSuppressed && root.activeScreen !== null && root.dialogVisible
    contentReady: root.activeScreen !== null
    persistent: true
    requestedCardWidth: root.authCardWidth
    requestedCardHeight: root.authCardHeight
    headerHeight: root.authHeaderHeight
    contentSpacing: root.authContentSpacing
    surfaceBorderSpec: root.borderSpec
    surfaceHorizontalOffset: root.shakeOffset
    onDismissRequested: root.refocus()

    headerData: Flickable {
      id: contextViewport
      width: parent.width
      height: root.authHeaderHeight
      contentWidth: width
      contentHeight: contextColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: contextColumn
        width: contextViewport.width
        spacing: Style.space(2)

        Text {
          width: parent.width
          visible: root.currentMessage !== ""
          text: "Request message: " + root.authorizationLabel(root.currentMessage)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
        }

        Text {
          width: parent.width
          visible: root.currentActionId !== ""
          text: "Trusted action ID: " + root.currentActionId
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
        }
      }
    }

    Item {
      id: authBody
      width: parent.width
      height: root.authBodyHeight

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
        visible: !root.fingerprintMode
        anchors.fill: parent
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

          TextField {
            id: passwordInput
            anchors.fill: parent
            cornerRadius: Style.cornerRadius
            foreground: root.errorFlash ? Color.polkit.textError : root.foreground
            accent: root.errorFlash ? Color.polkit.textError : root.accent
            placeholderText: root.errorFlash ? "Wrong" : (root.submitted ? "Checking..." : "Enter password")
            echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
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
        }
      }
    }
  }
}
