#Requires AutoHotkey v2.0
#Include ..\komorebi-bridge.ahk

AssertEqual(expected, actual, message) {
    if (expected !== actual)
        throw Error(message . "`nExpected: " . expected . "`nActual:   " . actual)
}

AssertTrue(actual, message) {
    if !actual
        throw Error(message)
}

ParseActiveLines(source) {
    lines := []
    inBlockComment := false

    for line in StrSplit(source, "`n", "`r") {
        trimmed := Trim(line)

        if (trimmed = "/*") {
            inBlockComment := true
            continue
        }

        if (inBlockComment) {
            if (trimmed = "*/")
                inBlockComment := false
            continue
        }

        if (trimmed = "" || SubStr(trimmed, 1, 1) = ";")
            continue

        lines.Push(trimmed)
    }

    AssertTrue(!inBlockComment, "komorebi.ahk contains an unterminated block comment")
    return lines
}

CountExact(lines, expected) {
    count := 0
    for line in lines {
        if (line = expected)
            count += 1
    }
    return count
}

RunStartupCriticalRegressionTest() {
    sourcePath := A_ScriptDir . "\..\komorebi-bridge.ahk"
    source := FileRead(sourcePath)
    ownerAssignment := InStr(source, "this.startupInProgress := true", true)
    AssertTrue(ownerAssignment > 0, "startup owner assignment must exist")

    runStatement := InStr(source, "try Run this.executable", true, ownerAssignment)
    AssertTrue(runStatement > ownerAssignment, "startup owner must execute Run")

    ownerToRun := SubStr(source, ownerAssignment, runStatement - ownerAssignment)
    AssertTrue(
        !InStr(ownerToRun, "Critical previousCritical", true),
        "owner must retain Critical through Run"
    )
}

Median(values) {
    if (values.Length = 0)
        throw ValueError("median requires at least one value")

    sorted := values.Clone()
    Loop sorted.Length - 1 {
        index := A_Index + 1
        value := sorted[index]
        previous := index - 1

        while (previous >= 1 && sorted[previous] > value) {
            sorted[previous + 1] := sorted[previous]
            previous -= 1
        }

        sorted[previous + 1] := value
    }

    middle := Floor(sorted.Length / 2)
    if Mod(sorted.Length, 2)
        return sorted[middle + 1]

    return (sorted[middle] + sorted[middle + 1]) / 2
}

ParseCommandId(value) {
    if !RegExMatch(value, "^\d+$")
        throw ValueError("command id must be an integer from 1 to 35")

    command := Integer(value)
    if (command < 1 || command > 35)
        throw ValueError("command id must be an integer from 1 to 35")
    return command
}

ParsePositiveCount(value) {
    if !RegExMatch(value, "^\d+$")
        throw ValueError("benchmark count must be a positive integer")

    count := Integer(value)
    if (count <= 0)
        throw ValueError("benchmark count must be a positive integer")
    return count
}

RunConstantTests() {
    RunStartupCriticalRegressionTest()
    AssertEqual(
        EnvGet("USERPROFILE") . "\.local\bin\komorebi-ahk-bridge.exe",
        KomorebiBridge.executable,
        "bridge executable must use the per-user install path"
    )

    AssertEqual(1, KomorebiCommand.Close, "Close ID")
    AssertEqual(2, KomorebiCommand.Minimize, "Minimize ID")
    AssertEqual(3, KomorebiCommand.ToggleMaximize, "ToggleMaximize ID")
    AssertEqual(4, KomorebiCommand.FocusLeft, "FocusLeft ID")
    AssertEqual(5, KomorebiCommand.FocusDown, "FocusDown ID")
    AssertEqual(6, KomorebiCommand.FocusUp, "FocusUp ID")
    AssertEqual(7, KomorebiCommand.FocusRight, "FocusRight ID")
    AssertEqual(8, KomorebiCommand.MoveLeft, "MoveLeft ID")
    AssertEqual(9, KomorebiCommand.MoveDown, "MoveDown ID")
    AssertEqual(10, KomorebiCommand.MoveUp, "MoveUp ID")
    AssertEqual(11, KomorebiCommand.MoveRight, "MoveRight ID")
    AssertEqual(12, KomorebiCommand.ToggleFloat, "ToggleFloat ID")
    AssertEqual(13, KomorebiCommand.ToggleMonocle, "ToggleMonocle ID")
    AssertEqual(14, KomorebiCommand.FlipHorizontal, "FlipHorizontal ID")
    AssertEqual(15, KomorebiCommand.FlipVertical, "FlipVertical ID")
    AssertEqual(16, KomorebiCommand.WorkspaceNext, "WorkspaceNext ID")
    AssertEqual(17, KomorebiCommand.WorkspacePrevious, "WorkspacePrevious ID")
    AssertEqual(18, KomorebiCommand.FocusMain, "FocusMain ID")
    AssertEqual(19, KomorebiCommand.FocusShell, "FocusShell ID")
    AssertEqual(20, KomorebiCommand.FocusBrowser, "FocusBrowser ID")
    AssertEqual(21, KomorebiCommand.FocusSecondary, "FocusSecondary ID")
    AssertEqual(22, KomorebiCommand.FocusGit, "FocusGit ID")
    AssertEqual(23, KomorebiCommand.FocusSql, "FocusSql ID")
    AssertEqual(24, KomorebiCommand.FocusExplorer, "FocusExplorer ID")
    AssertEqual(25, KomorebiCommand.MoveMain, "MoveMain ID")
    AssertEqual(26, KomorebiCommand.MoveShell, "MoveShell ID")
    AssertEqual(27, KomorebiCommand.MoveBrowser, "MoveBrowser ID")
    AssertEqual(28, KomorebiCommand.MoveSecondary, "MoveSecondary ID")
    AssertEqual(29, KomorebiCommand.MoveGit, "MoveGit ID")
    AssertEqual(30, KomorebiCommand.MoveSql, "MoveSql ID")
    AssertEqual(31, KomorebiCommand.MoveExplorer, "MoveExplorer ID")
    AssertEqual(32, KomorebiCommand.ResizeHorizontalDecrease, "ResizeHorizontalDecrease ID")
    AssertEqual(33, KomorebiCommand.ResizeHorizontalIncrease, "ResizeHorizontalIncrease ID")
    AssertEqual(34, KomorebiCommand.ResizeVerticalDecrease, "ResizeVerticalDecrease ID")
    AssertEqual(35, KomorebiCommand.ResizeVerticalIncrease, "last ID")

    AssertEqual(18, KomorebiCommand.FocusWorkspace("main"), "focus main")
    AssertEqual(19, KomorebiCommand.FocusWorkspace("shell"), "focus shell")
    AssertEqual(20, KomorebiCommand.FocusWorkspace("browser"), "focus browser")
    AssertEqual(21, KomorebiCommand.FocusWorkspace("secondary"), "focus secondary")
    AssertEqual(22, KomorebiCommand.FocusWorkspace("git"), "focus git")
    AssertEqual(23, KomorebiCommand.FocusWorkspace("sql"), "focus sql")
    AssertEqual(24, KomorebiCommand.FocusWorkspace("explorer"), "focus explorer")
    AssertEqual(0, KomorebiCommand.FocusWorkspace("unknown"), "unknown focus workspace")

    AssertEqual(25, KomorebiCommand.MoveWorkspace("main"), "move main")
    AssertEqual(26, KomorebiCommand.MoveWorkspace("shell"), "move shell")
    AssertEqual(27, KomorebiCommand.MoveWorkspace("browser"), "move browser")
    AssertEqual(28, KomorebiCommand.MoveWorkspace("secondary"), "move secondary")
    AssertEqual(29, KomorebiCommand.MoveWorkspace("git"), "move git")
    AssertEqual(30, KomorebiCommand.MoveWorkspace("sql"), "move sql")
    AssertEqual(31, KomorebiCommand.MoveWorkspace("explorer"), "move explorer")
    AssertEqual(0, KomorebiCommand.MoveWorkspace("unknown"), "unknown move workspace")

    RunSourceRegressionTests()
}

RunSourceRegressionTests() {
    sourcePath := A_ScriptDir . "\..\komorebi.ahk"
    source := FileRead(sourcePath)
    activeLines := ParseActiveLines(source)

    AssertEqual(
        1,
        CountExact(activeLines, "#Include komorebi-bridge.ahk"),
        "the main script must include the bridge client exactly once"
    )
    AssertEqual(
        0,
        CountExact(activeLines, "#Include komorebi-ipc.ahk"),
        "the rejected direct IPC client must not be included"
    )
    AssertEqual(
        1,
        CountExact(activeLines, "DetectHiddenWindows true"),
        "hidden bridge windows must be discoverable"
    )
    AssertEqual(
        1,
        CountExact(activeLines, "KomorebiBridge.EnsureRunning()"),
        "the bridge must be started proactively exactly once"
    )

    detectHiddenWindowsIndex := 0
    ensureRunningIndex := 0
    for index, line in activeLines {
        if (line = "DetectHiddenWindows true")
            detectHiddenWindowsIndex := index
        if (line = "KomorebiBridge.EnsureRunning()")
            ensureRunningIndex := index
    }
    AssertTrue(
        ensureRunningIndex > detectHiddenWindowsIndex,
        "the proactive bridge startup must follow DetectHiddenWindows true"
    )

    expectedBindings := [
        '#w::KomorebiBridge.Send(KomorebiCommand.Close)',
        '#m::KomorebiBridge.Send(KomorebiCommand.Minimize)',
        '#f::KomorebiBridge.Send(KomorebiCommand.ToggleMaximize)',
        '#h::KomorebiBridge.Send(KomorebiCommand.FocusLeft)',
        '#j::KomorebiBridge.Send(KomorebiCommand.FocusDown)',
        '#k::KomorebiBridge.Send(KomorebiCommand.FocusUp)',
        '#l::KomorebiBridge.Send(KomorebiCommand.FocusRight)',
        '#vkBA::KomorebiBridge.Send(KomorebiCommand.FocusRight)',
        '#+h::KomorebiBridge.Send(KomorebiCommand.MoveLeft)',
        '#+j::KomorebiBridge.Send(KomorebiCommand.MoveDown)',
        '#+k::KomorebiBridge.Send(KomorebiCommand.MoveUp)',
        '#+l::KomorebiBridge.Send(KomorebiCommand.MoveRight)',
        '#t::KomorebiBridge.Send(KomorebiCommand.ToggleFloat)',
        '#+f::KomorebiBridge.Send(KomorebiCommand.ToggleMonocle)',
        '#x::KomorebiBridge.Send(KomorebiCommand.FlipHorizontal)',
        '#y::KomorebiBridge.Send(KomorebiCommand.FlipVertical)',
        '#n::KomorebiBridge.Send(KomorebiCommand.WorkspaceNext)',
        '#p::KomorebiBridge.Send(KomorebiCommand.WorkspacePrevious)',
        '#2::KomorebiBridge.Send(KomorebiCommand.FocusMain)',
        '#5::KomorebiBridge.Send(KomorebiCommand.FocusShell)',
        '#8::KomorebiBridge.Send(KomorebiCommand.FocusBrowser)',
        '#3::KomorebiBridge.Send(KomorebiCommand.FocusSecondary)',
        '#6::KomorebiBridge.Send(KomorebiCommand.FocusGit)',
        '#9::KomorebiBridge.Send(KomorebiCommand.FocusSql)',
        '#0::KomorebiBridge.Send(KomorebiCommand.FocusExplorer)',
        '#+2::KomorebiBridge.Send(KomorebiCommand.MoveMain)',
        '#+5::KomorebiBridge.Send(KomorebiCommand.MoveShell)',
        '#+8::KomorebiBridge.Send(KomorebiCommand.MoveBrowser)',
        '#+3::KomorebiBridge.Send(KomorebiCommand.MoveSecondary)',
        '#+6::KomorebiBridge.Send(KomorebiCommand.MoveGit)',
        '#+9::KomorebiBridge.Send(KomorebiCommand.MoveSql)',
        '#+0::KomorebiBridge.Send(KomorebiCommand.MoveExplorer)',
        'h::KomorebiBridge.Send(KomorebiCommand.ResizeHorizontalDecrease)',
        'l::KomorebiBridge.Send(KomorebiCommand.ResizeHorizontalIncrease)',
        'k::KomorebiBridge.Send(KomorebiCommand.ResizeVerticalDecrease)',
        'j::KomorebiBridge.Send(KomorebiCommand.ResizeVerticalIncrease)'
    ]
    for binding in expectedBindings {
        AssertEqual(
            1,
            CountExact(activeLines, binding),
            "binding must appear exactly once: " . binding
        )
    }

    focusWorkspaceLine := "KomorebiBridge.Send(KomorebiCommand.FocusWorkspace(workspace))"
    moveWorkspaceLine := "KomorebiBridge.Send(KomorebiCommand.MoveWorkspace(workspace))"
    AssertEqual(
        3,
        CountExact(activeLines, focusWorkspaceLine),
        "dynamic FocusWorkspace call must appear exactly three times"
    )
    AssertEqual(
        2,
        CountExact(activeLines, moveWorkspaceLine),
        "dynamic MoveWorkspace call must appear exactly twice"
    )

    allowedCliLines := [
        "Komorebic(args) {",
        'Run "komorebic " args,, "Hide"',
        '#i::Komorebic("toggle-shortcuts")',
        "'powershell -NoProfile -NonInteractive -Command " . Chr(34)
            . "komorebic stop; gsudo komorebic start" . Chr(34) . "',",
        "try RunWait('komorebic replace-configuration " . Chr(34)
            . "' configPath '" . Chr(34) . "',, " . Chr(34) . "Hide" . Chr(34) . ")"
    ]
    for expected in allowedCliLines {
        AssertEqual(
            1,
            CountExact(activeLines, expected),
            "CLI allowlist line must appear exactly once: " . expected
        )
    }

    for line in activeLines {
        if RegExMatch(line, "i)\bkomorebic\b")
            AssertEqual(1, CountExact(allowedCliLines, line), "unauthorized CLI use: " . line)

        AssertTrue(
            !InStr(StrLower(line), "komorebiipc"),
            "KomorebiIpc must not be used by an active line: " . line
        )
    }
}

RunMissingHelperTest() {
    originalClass := KomorebiBridge.windowClass
    originalTitle := KomorebiBridge.windowTitle
    originalMessageName := KomorebiBridge.messageName
    originalExecutable := KomorebiBridge.executable
    originalMessageId := KomorebiBridge.messageId
    originalHwnd := KomorebiBridge.hwnd

    try {
        KomorebiBridge.windowClass := "Configurations.Komorebi.Missing.Test.v1"
        KomorebiBridge.windowTitle := "Configurations.Komorebi.Missing.Test.v1"
        KomorebiBridge.executable := "definitely-missing-komorebi-bridge.exe"
        KomorebiBridge.hwnd := 0

        started := DllCall("Kernel32\GetTickCount64", "UInt64")
        AssertTrue(!KomorebiBridge.EnsureRunning(), "missing helper must fail")
        elapsed := DllCall("Kernel32\GetTickCount64", "UInt64") - started
        AssertTrue(elapsed < 500, "missing helper failure must be bounded")
    } finally {
        KomorebiBridge.windowClass := originalClass
        KomorebiBridge.windowTitle := originalTitle
        KomorebiBridge.messageName := originalMessageName
        KomorebiBridge.executable := originalExecutable
        KomorebiBridge.messageId := originalMessageId
        KomorebiBridge.hwnd := originalHwnd
    }
}

RunStaleHwndTest() {
    originalClass := KomorebiBridge.windowClass
    originalTitle := KomorebiBridge.windowTitle
    originalExecutable := KomorebiBridge.executable
    originalHwnd := KomorebiBridge.hwnd

    try {
        suffix := DllCall("Kernel32\GetTickCount64", "UInt64")
        KomorebiBridge.windowClass := "Configurations.Komorebi.Resilience.Stale." . suffix
        KomorebiBridge.windowTitle := "Configurations.Komorebi.Resilience.Stale." . suffix
        KomorebiBridge.executable := "definitely-missing-komorebi-bridge.exe"
        KomorebiBridge.hwnd := DllCall("User32\GetDesktopWindow", "Ptr")

        started := DllCall("Kernel32\GetTickCount64", "UInt64")
        AssertTrue(!KomorebiBridge.EnsureRunning(), "stale HWND must not be trusted")
        elapsed := DllCall("Kernel32\GetTickCount64", "UInt64") - started
        AssertTrue(elapsed < 500, "stale HWND failure must be bounded")
    } finally {
        KomorebiBridge.windowClass := originalClass
        KomorebiBridge.windowTitle := originalTitle
        KomorebiBridge.executable := originalExecutable
        KomorebiBridge.hwnd := originalHwnd
    }
}

RunPollingTimeoutTest() {
    originalClass := KomorebiBridge.windowClass
    originalTitle := KomorebiBridge.windowTitle
    originalExecutable := KomorebiBridge.executable
    originalHwnd := KomorebiBridge.hwnd

    try {
        suffix := DllCall("Kernel32\GetTickCount64", "UInt64")
        KomorebiBridge.windowClass := "Configurations.Komorebi.Resilience.Timeout." . suffix
        KomorebiBridge.windowTitle := "Configurations.Komorebi.Resilience.Timeout." . suffix
        KomorebiBridge.executable := A_ComSpec . " /c exit 0"
        KomorebiBridge.hwnd := 0

        started := DllCall("Kernel32\GetTickCount64", "UInt64")
        AssertTrue(!KomorebiBridge.EnsureRunning(), "polling timeout must fail without a window")
        elapsed := DllCall("Kernel32\GetTickCount64", "UInt64") - started
        AssertTrue(elapsed >= 1400 && elapsed <= 2500, "polling timeout elapsed outside expected range: " . elapsed)
    } finally {
        KomorebiBridge.windowClass := originalClass
        KomorebiBridge.windowTitle := originalTitle
        KomorebiBridge.executable := originalExecutable
        KomorebiBridge.hwnd := originalHwnd
    }
}

RunClientResilienceTests() {
    RunStaleHwndTest()
    RunPollingTimeoutTest()
}

RunIntegration(command) {
    AssertTrue(KomorebiBridge.Send(command), "bridge PostMessage failed")
}

RunBenchmark(command, count) {
    timings := []
    frequency := 0
    if !DllCall("QueryPerformanceFrequency", "Int64*", &frequency)
        throw Error("QueryPerformanceFrequency failed")

    Loop count {
        started := 0
        finished := 0
        DllCall("QueryPerformanceCounter", "Int64*", &started)
        AssertTrue(KomorebiBridge.Send(command), "bridge benchmark dispatch failed")
        DllCall("QueryPerformanceCounter", "Int64*", &finished)
        timings.Push((finished - started) * 1000 / frequency)
    }

    FileAppend("BRIDGE_MEDIAN_MS=" . Format("{:.3f}", Median(timings)) . "`n", "*")
}

Main() {
    RunConstantTests()

    if (A_Args.Length = 0)
        return

    mode := A_Args[1]
    switch mode {
        case "--missing-helper":
            if (A_Args.Length != 1)
                throw ValueError("--missing-helper does not accept arguments")
            RunMissingHelperTest()
        case "--client-resilience":
            if (A_Args.Length != 1)
                throw ValueError("--client-resilience does not accept arguments")
            RunClientResilienceTests()
        case "--integration":
            if (A_Args.Length != 2)
                throw ValueError("--integration requires one command id")
            RunIntegration(ParseCommandId(A_Args[2]))
        case "--benchmark":
            if (A_Args.Length != 3)
                throw ValueError("--benchmark requires a command id and positive count")
            command := ParseCommandId(A_Args[2])
            count := ParsePositiveCount(A_Args[3])
            RunBenchmark(command, count)
        default:
            throw ValueError("invalid mode: " . mode)
    }
}

try {
    Main()
    try FileAppend("PASS komorebi-bridge-tests`n", "*")
    ExitApp 0
} catch Error as testError {
    try FileAppend(
        "FAIL " . testError.Message . " (" . testError.File . ":" . testError.Line . ")`n",
        "*"
    )
    ExitApp 1
}
