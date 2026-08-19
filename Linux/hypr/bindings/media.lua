-- Laptop multimedia keys for volume and LCD brightness (with OSD)
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("desktop-osd volume-up 5"),
	{ locked = true, repeating = true, description = "Volume up" }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("desktop-osd volume-down 5"),
	{ locked = true, repeating = true, description = "Volume down" }
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("desktop-osd volume-toggle"),
	{ locked = true, repeating = true, description = "Mute" }
)
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd("desktop-osd mic-toggle"),
	{ locked = true, repeating = true, description = "Mute microphone" }
)
hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("desktop-osd brightness-up 5"),
	{ locked = true, repeating = true, description = "Brightness up" }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("desktop-osd brightness-down 5"),
	{ locked = true, repeating = true, description = "Brightness down" }
)
hl.bind(
	"XF86KbdBrightnessUp",
	hl.dsp.exec_cmd("desktop-osd keyboard-up"),
	{ locked = true, repeating = true, description = "Keyboard brightness up" }
)
hl.bind(
	"XF86KbdBrightnessDown",
	hl.dsp.exec_cmd("desktop-osd keyboard-down"),
	{ locked = true, repeating = true, description = "Keyboard brightness down" }
)
hl.bind(
	"XF86KbdLightOnOff",
	hl.dsp.exec_cmd("desktop-osd keyboard-cycle"),
	{ locked = true, description = "Keyboard backlight cycle" }
)

-- Precise 1% multimedia adjustments with Alt modifier
hl.bind(
	"ALT + XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("desktop-osd volume-up 1"),
	{ locked = true, repeating = true, description = "Volume up precise" }
)
hl.bind(
	"ALT + XF86AudioLowerVolume",
	hl.dsp.exec_cmd("desktop-osd volume-down 1"),
	{ locked = true, repeating = true, description = "Volume down precise" }
)
hl.bind(
	"ALT + XF86MonBrightnessUp",
	hl.dsp.exec_cmd("desktop-osd brightness-up 1"),
	{ locked = true, repeating = true, description = "Brightness up precise" }
)
hl.bind(
	"ALT + XF86MonBrightnessDown",
	hl.dsp.exec_cmd("desktop-osd brightness-down 1"),
	{ locked = true, repeating = true, description = "Brightness down precise" }
)

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("desktop-osd media-next"), { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("desktop-osd media-play-pause"), { locked = true, description = "Pause" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("desktop-osd media-play-pause"), { locked = true, description = "Play" })
hl.bind(
	"XF86AudioPrev",
	hl.dsp.exec_cmd("desktop-osd media-previous"),
	{ locked = true, description = "Previous track" }
)

-- Switch audio output with Super + Mute
hl.bind(
	"SUPER + XF86AudioMute",
	hl.dsp.exec_cmd("cmd-audio-switch"),
	{ locked = true, description = "Switch audio output" }
)

-- Super + F-key media controls. This laptop's F6-F10 keys emit plain F-keys
-- (no XF86 media codes), so bind them here for brightness and volume.
hl.bind(
	"SUPER + F6",
	hl.dsp.exec_cmd("desktop-osd brightness-down 5"),
	{ locked = true, repeating = true, description = "Brightness down" }
)
hl.bind(
	"SUPER + F7",
	hl.dsp.exec_cmd("desktop-osd brightness-up 5"),
	{ locked = true, repeating = true, description = "Brightness up" }
)
hl.bind("SUPER + F8", hl.dsp.exec_cmd("desktop-osd volume-toggle"), { locked = true, description = "Mute" })
hl.bind(
	"SUPER + F9",
	hl.dsp.exec_cmd("desktop-osd volume-down 5"),
	{ locked = true, repeating = true, description = "Volume down" }
)
hl.bind(
	"SUPER + F10",
	hl.dsp.exec_cmd("desktop-osd volume-up 5"),
	{ locked = true, repeating = true, description = "Volume up" }
)
