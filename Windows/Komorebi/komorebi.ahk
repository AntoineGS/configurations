#Requires AutoHotkey v2.0
#SingleInstance Force

; ==========================================================================
; Komorebi Window Manager - AutoHotkey v2 Hotkeys
; Win key (LWin/RWin) is the main modifier (replaces F13)
;
; NOTE: Some Win+key combos conflict with Windows built-in shortcuts.
; AHK overrides most of them, EXCEPT Win+L (lock screen) which is
; handled at the OS level and cannot be intercepted.
; Conflicting native shortcuts that ARE overridden by this script:
;   Win+R (Run), Win+M (Minimize all), Win+W (Widgets),
;   Win+H (Voice typing), Win+T (Taskbar), Win+P (Project),
;   Win+I (Settings), Win+F (Feedback Hub), Win+0-9 (Taskbar apps)
; ==========================================================================

; --- Helpers ---------------------------------------------------------------

FocusOrLaunch(windowTitle, execPath) {
    if WinExist(windowTitle) {
        WinActivate
    } else {
        Run execPath
    }
}

Komorebic(args) {
    Run "komorebic " args,, "Hide"
}

; --- Reload ----------------------------------------------------------------

#r::Reload
#i::Komorebic("toggle-shortcuts")

; --- App shortcuts (focus or launch) ---------------------------------------

#!b::FocusOrLaunch("Chrome", "chrome")
#!g::FocusOrLaunch("GitKraken", "gitkraken")
#!e::FocusOrLaunch("MD Explorer", "C:/Multidev/DBExplorer/MDExplorer.exe")
#!c::FocusOrLaunch("Total Commander", "C:/Program Files/totalcmd/TOTALCMD64.exe")
#!m::FocusOrLaunch("ahk_exe ms-teams.exe", "ms-teams.exe")
#!o::FocusOrLaunch("ahk_exe olk.exe", "olk.exe")
#!t::{
    if WinExist("ahk_class btop") {
        WinClose
        return
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &mLeft, &mTop, &mRight, &mBottom)
    w := Round((mRight - mLeft) * 0.8)
    h := Round((mBottom - mTop) * 0.8)
    cols := Round(w / 9)
    rows := Round(h / 19)
    cmd := "wezterm-gui.exe --config initial_cols=" cols " --config initial_rows=" rows " start --class btop -- btop"
    Run cmd
}
#!f::FocusOrLaunch("Everything", "C:\Program Files\Everything 1.5a\Everything.exe")
#Enter::Run "wezterm-gui.exe"

; --- Window management -----------------------------------------------------

#w::Komorebic("close")
#m::Komorebic("minimize")
#f::Komorebic("toggle-maximize")

; --- Focus windows ---------------------------------------------------------

#h::Komorebic("focus left")
#j::Komorebic("focus down")
#k::Komorebic("focus up")
#l::Komorebic("focus right")

; --- Move windows ----------------------------------------------------------

#+h::Komorebic("move left")
#+j::Komorebic("move down")
#+k::Komorebic("move up")
#+l::Komorebic("move right")
#+Enter::Komorebic("promote")

; --- Stack windows ---------------------------------------------------------

#Left::Komorebic("stack left")
#Down::Komorebic("stack down")
#Up::Komorebic("stack up")
#Right::Komorebic("stack right")
#vkBA::Komorebic("unstack")            ; semicolon key
#[::Komorebic("cycle-stack previous")
#]::Komorebic("cycle-stack next")

; --- Resize ----------------------------------------------------------------

#=::Komorebic("resize-axis horizontal increase")
#-::Komorebic("resize-axis horizontal decrease")
#+=::Komorebic("resize-axis vertical increase")
#+-::Komorebic("resize-axis vertical decrease")

; --- Manipulate windows ----------------------------------------------------

#t::Komorebic("toggle-float")
#+f::Komorebic("toggle-monocle")

; --- Window manager options ------------------------------------------------

#+r::Komorebic("retile")
#p::Komorebic("toggle-pause")

; --- Layouts ---------------------------------------------------------------

#x::Komorebic("flip-layout horizontal")
#y::Komorebic("flip-layout vertical")

; --- Workspaces ------------------------------------------------------------

#2::Komorebic('focus-named-workspace "main"')
#5::Komorebic('focus-named-workspace "shell"')
#8::Komorebic('focus-named-workspace "browser"')
#3::Komorebic('focus-named-workspace "secondary"')
#6::Komorebic('focus-named-workspace "git"')
#9::Komorebic('focus-named-workspace "sql"')
#0::Komorebic('focus-named-workspace "explorer"')

; --- Move windows across workspaces ----------------------------------------

#+2::Komorebic('move-to-named-workspace "main"')
#+5::Komorebic('move-to-named-workspace "shell"')
#+8::Komorebic('move-to-named-workspace "browser"')
#+3::Komorebic('move-to-named-workspace "secondary"')
#+6::Komorebic('move-to-named-workspace "git"')
#+9::Komorebic('move-to-named-workspace "sql"')
#+0::Komorebic('move-to-named-workspace "explorer"')
