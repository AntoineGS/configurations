pub const CLOSE: u32 = 1;
pub const MINIMIZE: u32 = 2;
pub const TOGGLE_MAXIMIZE: u32 = 3;
pub const FOCUS_LEFT: u32 = 4;
pub const FOCUS_DOWN: u32 = 5;
pub const FOCUS_UP: u32 = 6;
pub const FOCUS_RIGHT: u32 = 7;
pub const MOVE_LEFT: u32 = 8;
pub const MOVE_DOWN: u32 = 9;
pub const MOVE_UP: u32 = 10;
pub const MOVE_RIGHT: u32 = 11;
pub const TOGGLE_FLOAT: u32 = 12;
pub const TOGGLE_MONOCLE: u32 = 13;
pub const FLIP_HORIZONTAL: u32 = 14;
pub const FLIP_VERTICAL: u32 = 15;
pub const WORKSPACE_NEXT: u32 = 16;
pub const WORKSPACE_PREVIOUS: u32 = 17;
pub const FOCUS_MAIN: u32 = 18;
pub const FOCUS_SHELL: u32 = 19;
pub const FOCUS_BROWSER: u32 = 20;
pub const FOCUS_SECONDARY: u32 = 21;
pub const FOCUS_GIT: u32 = 22;
pub const FOCUS_SQL: u32 = 23;
pub const FOCUS_EXPLORER: u32 = 24;
pub const MOVE_MAIN: u32 = 25;
pub const MOVE_SHELL: u32 = 26;
pub const MOVE_BROWSER: u32 = 27;
pub const MOVE_SECONDARY: u32 = 28;
pub const MOVE_GIT: u32 = 29;
pub const MOVE_SQL: u32 = 30;
pub const MOVE_EXPLORER: u32 = 31;
pub const RESIZE_HORIZONTAL_DECREASE: u32 = 32;
pub const RESIZE_HORIZONTAL_INCREASE: u32 = 33;
pub const RESIZE_VERTICAL_DECREASE: u32 = 34;
pub const RESIZE_VERTICAL_INCREASE: u32 = 35;

#[cfg(test)]
const FIRST_COMMAND: u32 = CLOSE;
#[cfg(test)]
const LAST_COMMAND: u32 = RESIZE_VERTICAL_INCREASE;

pub fn payload_for(id: u32) -> Option<&'static [u8]> {
    Some(match id {
        CLOSE => b"{\"type\":\"Close\"}\n",
        MINIMIZE => b"{\"type\":\"Minimize\"}\n",
        TOGGLE_MAXIMIZE => b"{\"type\":\"ToggleMaximize\"}\n",
        FOCUS_LEFT => b"{\"type\":\"FocusWindow\",\"content\":\"Left\"}\n",
        FOCUS_DOWN => b"{\"type\":\"FocusWindow\",\"content\":\"Down\"}\n",
        FOCUS_UP => b"{\"type\":\"FocusWindow\",\"content\":\"Up\"}\n",
        FOCUS_RIGHT => b"{\"type\":\"FocusWindow\",\"content\":\"Right\"}\n",
        MOVE_LEFT => b"{\"type\":\"MoveWindow\",\"content\":\"Left\"}\n",
        MOVE_DOWN => b"{\"type\":\"MoveWindow\",\"content\":\"Down\"}\n",
        MOVE_UP => b"{\"type\":\"MoveWindow\",\"content\":\"Up\"}\n",
        MOVE_RIGHT => b"{\"type\":\"MoveWindow\",\"content\":\"Right\"}\n",
        TOGGLE_FLOAT => b"{\"type\":\"ToggleFloat\"}\n",
        TOGGLE_MONOCLE => b"{\"type\":\"ToggleMonocle\"}\n",
        FLIP_HORIZONTAL => b"{\"type\":\"FlipLayout\",\"content\":\"Horizontal\"}\n",
        FLIP_VERTICAL => b"{\"type\":\"FlipLayout\",\"content\":\"Vertical\"}\n",
        WORKSPACE_NEXT => b"{\"type\":\"CycleFocusWorkspace\",\"content\":\"Next\"}\n",
        WORKSPACE_PREVIOUS => b"{\"type\":\"CycleFocusWorkspace\",\"content\":\"Previous\"}\n",
        FOCUS_MAIN => b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"main\"}\n",
        FOCUS_SHELL => b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"shell\"}\n",
        FOCUS_BROWSER => b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"browser\"}\n",
        FOCUS_SECONDARY => b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"secondary\"}\n",
        FOCUS_GIT => b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"git\"}\n",
        FOCUS_SQL => b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"sql\"}\n",
        FOCUS_EXPLORER => b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"explorer\"}\n",
        MOVE_MAIN => b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"main\"}\n",
        MOVE_SHELL => b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"shell\"}\n",
        MOVE_BROWSER => b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"browser\"}\n",
        MOVE_SECONDARY => {
            b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"secondary\"}\n"
        }
        MOVE_GIT => b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"git\"}\n",
        MOVE_SQL => b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"sql\"}\n",
        MOVE_EXPLORER => b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"explorer\"}\n",
        RESIZE_HORIZONTAL_DECREASE => {
            b"{\"type\":\"ResizeWindowAxis\",\"content\":[\"Horizontal\",\"Decrease\"]}\n"
        }
        RESIZE_HORIZONTAL_INCREASE => {
            b"{\"type\":\"ResizeWindowAxis\",\"content\":[\"Horizontal\",\"Increase\"]}\n"
        }
        RESIZE_VERTICAL_DECREASE => {
            b"{\"type\":\"ResizeWindowAxis\",\"content\":[\"Vertical\",\"Decrease\"]}\n"
        }
        RESIZE_VERTICAL_INCREASE => {
            b"{\"type\":\"ResizeWindowAxis\",\"content\":[\"Vertical\",\"Increase\"]}\n"
        }
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const EXPECTED: &[(u32, &[u8])] = &[
        (CLOSE, b"{\"type\":\"Close\"}\n"),
        (MINIMIZE, b"{\"type\":\"Minimize\"}\n"),
        (TOGGLE_MAXIMIZE, b"{\"type\":\"ToggleMaximize\"}\n"),
        (
            FOCUS_LEFT,
            b"{\"type\":\"FocusWindow\",\"content\":\"Left\"}\n",
        ),
        (
            FOCUS_DOWN,
            b"{\"type\":\"FocusWindow\",\"content\":\"Down\"}\n",
        ),
        (FOCUS_UP, b"{\"type\":\"FocusWindow\",\"content\":\"Up\"}\n"),
        (
            FOCUS_RIGHT,
            b"{\"type\":\"FocusWindow\",\"content\":\"Right\"}\n",
        ),
        (
            MOVE_LEFT,
            b"{\"type\":\"MoveWindow\",\"content\":\"Left\"}\n",
        ),
        (
            MOVE_DOWN,
            b"{\"type\":\"MoveWindow\",\"content\":\"Down\"}\n",
        ),
        (MOVE_UP, b"{\"type\":\"MoveWindow\",\"content\":\"Up\"}\n"),
        (
            MOVE_RIGHT,
            b"{\"type\":\"MoveWindow\",\"content\":\"Right\"}\n",
        ),
        (TOGGLE_FLOAT, b"{\"type\":\"ToggleFloat\"}\n"),
        (TOGGLE_MONOCLE, b"{\"type\":\"ToggleMonocle\"}\n"),
        (
            FLIP_HORIZONTAL,
            b"{\"type\":\"FlipLayout\",\"content\":\"Horizontal\"}\n",
        ),
        (
            FLIP_VERTICAL,
            b"{\"type\":\"FlipLayout\",\"content\":\"Vertical\"}\n",
        ),
        (
            WORKSPACE_NEXT,
            b"{\"type\":\"CycleFocusWorkspace\",\"content\":\"Next\"}\n",
        ),
        (
            WORKSPACE_PREVIOUS,
            b"{\"type\":\"CycleFocusWorkspace\",\"content\":\"Previous\"}\n",
        ),
        (
            FOCUS_MAIN,
            b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"main\"}\n",
        ),
        (
            FOCUS_SHELL,
            b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"shell\"}\n",
        ),
        (
            FOCUS_BROWSER,
            b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"browser\"}\n",
        ),
        (
            FOCUS_SECONDARY,
            b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"secondary\"}\n",
        ),
        (
            FOCUS_GIT,
            b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"git\"}\n",
        ),
        (
            FOCUS_SQL,
            b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"sql\"}\n",
        ),
        (
            FOCUS_EXPLORER,
            b"{\"type\":\"FocusNamedWorkspace\",\"content\":\"explorer\"}\n",
        ),
        (
            MOVE_MAIN,
            b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"main\"}\n",
        ),
        (
            MOVE_SHELL,
            b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"shell\"}\n",
        ),
        (
            MOVE_BROWSER,
            b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"browser\"}\n",
        ),
        (
            MOVE_SECONDARY,
            b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"secondary\"}\n",
        ),
        (
            MOVE_GIT,
            b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"git\"}\n",
        ),
        (
            MOVE_SQL,
            b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"sql\"}\n",
        ),
        (
            MOVE_EXPLORER,
            b"{\"type\":\"MoveContainerToNamedWorkspace\",\"content\":\"explorer\"}\n",
        ),
        (
            RESIZE_HORIZONTAL_DECREASE,
            b"{\"type\":\"ResizeWindowAxis\",\"content\":[\"Horizontal\",\"Decrease\"]}\n",
        ),
        (
            RESIZE_HORIZONTAL_INCREASE,
            b"{\"type\":\"ResizeWindowAxis\",\"content\":[\"Horizontal\",\"Increase\"]}\n",
        ),
        (
            RESIZE_VERTICAL_DECREASE,
            b"{\"type\":\"ResizeWindowAxis\",\"content\":[\"Vertical\",\"Decrease\"]}\n",
        ),
        (
            RESIZE_VERTICAL_INCREASE,
            b"{\"type\":\"ResizeWindowAxis\",\"content\":[\"Vertical\",\"Increase\"]}\n",
        ),
    ];

    #[test]
    fn numeric_command_ids_match_ipc_abi() {
        assert_eq!(CLOSE, 1);
        assert_eq!(MINIMIZE, 2);
        assert_eq!(TOGGLE_MAXIMIZE, 3);
        assert_eq!(FOCUS_LEFT, 4);
        assert_eq!(FOCUS_DOWN, 5);
        assert_eq!(FOCUS_UP, 6);
        assert_eq!(FOCUS_RIGHT, 7);
        assert_eq!(MOVE_LEFT, 8);
        assert_eq!(MOVE_DOWN, 9);
        assert_eq!(MOVE_UP, 10);
        assert_eq!(MOVE_RIGHT, 11);
        assert_eq!(TOGGLE_FLOAT, 12);
        assert_eq!(TOGGLE_MONOCLE, 13);
        assert_eq!(FLIP_HORIZONTAL, 14);
        assert_eq!(FLIP_VERTICAL, 15);
        assert_eq!(WORKSPACE_NEXT, 16);
        assert_eq!(WORKSPACE_PREVIOUS, 17);
        assert_eq!(FOCUS_MAIN, 18);
        assert_eq!(FOCUS_SHELL, 19);
        assert_eq!(FOCUS_BROWSER, 20);
        assert_eq!(FOCUS_SECONDARY, 21);
        assert_eq!(FOCUS_GIT, 22);
        assert_eq!(FOCUS_SQL, 23);
        assert_eq!(FOCUS_EXPLORER, 24);
        assert_eq!(MOVE_MAIN, 25);
        assert_eq!(MOVE_SHELL, 26);
        assert_eq!(MOVE_BROWSER, 27);
        assert_eq!(MOVE_SECONDARY, 28);
        assert_eq!(MOVE_GIT, 29);
        assert_eq!(MOVE_SQL, 30);
        assert_eq!(MOVE_EXPLORER, 31);
        assert_eq!(RESIZE_HORIZONTAL_DECREASE, 32);
        assert_eq!(RESIZE_HORIZONTAL_INCREASE, 33);
        assert_eq!(RESIZE_VERTICAL_DECREASE, 34);
        assert_eq!(RESIZE_VERTICAL_INCREASE, 35);
        assert_eq!(FIRST_COMMAND, 1);
        assert_eq!(LAST_COMMAND, 35);

        assert_eq!(EXPECTED.len(), (LAST_COMMAND - FIRST_COMMAND + 1) as usize);
        for (expected_id, (actual_id, _)) in (FIRST_COMMAND..=LAST_COMMAND).zip(EXPECTED.iter()) {
            assert_eq!(*actual_id, expected_id);
        }
    }

    #[test]
    fn maps_every_command_to_exact_wire_json() {
        assert_eq!(EXPECTED.len(), LAST_COMMAND as usize);
        for (id, expected) in EXPECTED {
            assert_eq!(payload_for(*id), Some(*expected), "command ID {id}");
        }
    }

    #[test]
    fn rejects_unknown_ids() {
        assert_eq!(payload_for(0), None);
        assert_eq!(payload_for(36), None);
        assert_eq!(payload_for(u32::MAX), None);
    }

    #[test]
    fn every_payload_is_valid_json_followed_by_one_lf() {
        for id in FIRST_COMMAND..=LAST_COMMAND {
            let payload = payload_for(id).unwrap();
            assert!(payload.ends_with(b"\n"));
            let json = &payload[..payload.len() - 1];
            assert!(!json.ends_with(b"\n"));
            serde_json::from_slice::<serde_json::Value>(json).unwrap();
        }
    }
}
