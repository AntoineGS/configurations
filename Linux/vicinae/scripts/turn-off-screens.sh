#!/bin/bash
# @vicinae.schemaVersion 1
# @vicinae.title Turn Off Screens
# @vicinae.mode silent
# @vicinae.exec ["/bin/bash"]

exec </dev/null # vicinae gives script commands a never-closing stdin; detach it so hyprctl does not hang
nohup bash -c "sleep 2; exec hyprctl eval 'hl.dispatch(hl.dsp.dpms({action=\"off\"}))'" >/dev/null 2>&1 &
