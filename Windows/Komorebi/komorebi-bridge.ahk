#Requires AutoHotkey v2.0

class KomorebiCommand {
    static Close := 1
    static Minimize := 2
    static ToggleMaximize := 3
    static FocusLeft := 4
    static FocusDown := 5
    static FocusUp := 6
    static FocusRight := 7
    static MoveLeft := 8
    static MoveDown := 9
    static MoveUp := 10
    static MoveRight := 11
    static ToggleFloat := 12
    static ToggleMonocle := 13
    static FlipHorizontal := 14
    static FlipVertical := 15
    static WorkspaceNext := 16
    static WorkspacePrevious := 17
    static FocusMain := 18
    static FocusShell := 19
    static FocusBrowser := 20
    static FocusSecondary := 21
    static FocusGit := 22
    static FocusSql := 23
    static FocusExplorer := 24
    static MoveMain := 25
    static MoveShell := 26
    static MoveBrowser := 27
    static MoveSecondary := 28
    static MoveGit := 29
    static MoveSql := 30
    static MoveExplorer := 31
    static ResizeHorizontalDecrease := 32
    static ResizeHorizontalIncrease := 33
    static ResizeVerticalDecrease := 34
    static ResizeVerticalIncrease := 35

    static FocusWorkspace(workspace) {
        switch workspace {
            case "main": return this.FocusMain
            case "shell": return this.FocusShell
            case "browser": return this.FocusBrowser
            case "secondary": return this.FocusSecondary
            case "git": return this.FocusGit
            case "sql": return this.FocusSql
            case "explorer": return this.FocusExplorer
            default: return 0
        }
    }

    static MoveWorkspace(workspace) {
        switch workspace {
            case "main": return this.MoveMain
            case "shell": return this.MoveShell
            case "browser": return this.MoveBrowser
            case "secondary": return this.MoveSecondary
            case "git": return this.MoveGit
            case "sql": return this.MoveSql
            case "explorer": return this.MoveExplorer
            default: return 0
        }
    }
}

class KomorebiBridge {
    static windowClass := "Configurations.Komorebi.Bridge.v1"
    static windowTitle := "Configurations.Komorebi.Bridge.v1"
    static messageName := "Configurations.Komorebi.Bridge.Command.v1"
    static executable := EnvGet("USERPROFILE") . "\.local\bin\komorebi-ahk-bridge.exe"
    static messageId := 0
    static hwnd := 0
    static startupInProgress := false

    static GetMessageId() {
        if this.messageId
            return this.messageId

        try messageId := DllCall(
            "User32\RegisterWindowMessageW",
            "Str", this.messageName,
            "UInt"
        )
        catch
            return 0

        if !messageId
            return 0

        this.messageId := messageId
        return messageId
    }

    static Send(command) {
        if !IsInteger(command) || command < 1 || command > 35
            return false

        messageId := this.GetMessageId()
        if !messageId || !this.EnsureRunning()
            return false

        if this.Post(command, messageId)
            return true

        this.hwnd := 0
        if !this.EnsureRunning()
            return false
        return this.Post(command, messageId)
    }

    static EnsureRunning() {
        foundHwnd := this.FindWindow()
        if (foundHwnd && DllCall("User32\IsWindow", "Ptr", foundHwnd, "Int")) {
            this.hwnd := foundHwnd
            return true
        }
        this.hwnd := 0

        previousCritical := A_IsCritical
        Critical
        if this.startupInProgress {
            Critical previousCritical
            return this.WaitForWindow(1500)
        }
        this.startupInProgress := true

        try {
            launchSucceeded := true
            try Run this.executable,, "Hide"
            catch
                launchSucceeded := false
        } finally {
            Critical previousCritical
        }

        try {
            if !launchSucceeded
                return false
            return this.WaitForWindow(1500)
        } finally {
            this.startupInProgress := false
        }
    }

    static WaitForWindow(timeoutMs) {
        started := this.GetTickCount64()
        while (this.GetTickCount64() - started < timeoutMs) {
            Sleep 10
            foundHwnd := this.FindWindow()
            if (foundHwnd && DllCall("User32\IsWindow", "Ptr", foundHwnd, "Int")) {
                this.hwnd := foundHwnd
                return true
            }
            this.hwnd := 0
        }

        return false
    }

    static GetTickCount64() {
        return DllCall("Kernel32\GetTickCount64", "UInt64")
    }

    static FindWindow() {
        try return DllCall(
            "User32\FindWindowW",
            "Str", this.windowClass,
            "Str", this.windowTitle,
            "Ptr"
        )
        catch
            return 0
    }

    static Post(command, messageId) {
        if !this.hwnd
            return false

        try return !!DllCall(
            "User32\PostMessageW",
            "Ptr", this.hwnd,
            "UInt", messageId,
            "UPtr", command,
            "Ptr", 0,
            "Int"
        )
        catch
            return false
    }
}
