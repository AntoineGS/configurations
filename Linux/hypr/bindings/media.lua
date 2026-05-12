-- Only display the OSD on the currently focused monitor
local osdclient = [[swayosd-client --monitor "$(hyprctl monitors -j | jq -r '.[] | select(.focused == true).name')"]]

-- Laptop multimedia keys for volume and LCD brightness (with OSD)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume raise"),  { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume lower"),  { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(osdclient .. " --output-volume mute-toggle"), { locked = true, repeating = true, description = "Mute" })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(osdclient .. " --input-volume mute-toggle"),  { locked = true, repeating = true, description = "Mute microphone" })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightness-display +5%"),                { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightness-display 5%-"),                { locked = true, repeating = true, description = "Brightness down" })
hl.bind("XF86KbdBrightnessUp",  hl.dsp.exec_cmd("brightness-keyboard up"),                { locked = true, repeating = true, description = "Keyboard brightness up" })
hl.bind("XF86KbdBrightnessDown",hl.dsp.exec_cmd("brightness-keyboard down"),              { locked = true, repeating = true, description = "Keyboard brightness down" })
hl.bind("XF86KbdLightOnOff",    hl.dsp.exec_cmd("brightness-keyboard cycle"),             { locked = true, description = "Keyboard backlight cycle" })

-- Precise 1% multimedia adjustments with Alt modifier
hl.bind("ALT + XF86AudioRaiseVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume +1"), { locked = true, repeating = true, description = "Volume up precise" })
hl.bind("ALT + XF86AudioLowerVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume -1"), { locked = true, repeating = true, description = "Volume down precise" })
hl.bind("ALT + XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightness-display +1%"),           { locked = true, repeating = true, description = "Brightness up precise" })
hl.bind("ALT + XF86MonBrightnessDown",hl.dsp.exec_cmd("brightness-display 1%-"),           { locked = true, repeating = true, description = "Brightness down precise" })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(osdclient .. " --playerctl next"),       { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(osdclient .. " --playerctl play-pause"), { locked = true, description = "Pause" })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(osdclient .. " --playerctl play-pause"), { locked = true, description = "Play" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(osdclient .. " --playerctl previous"),   { locked = true, description = "Previous track" })

-- Switch audio output with Super + Mute
hl.bind("SUPER + XF86AudioMute", hl.dsp.exec_cmd("cmd-audio-switch"), { locked = true, description = "Switch audio output" })
