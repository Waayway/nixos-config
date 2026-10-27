pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Power menu state and actions (replaces wlogout).
//   qs ipc call power toggle      (SUPER+L)
Singleton {
    id: root

    property bool menuOpen: false

    // Same order and keys as wlogout's defaults.
    readonly property var actions: [
        {
            key: "l",
            icon: "\u{f033e}", // nf-md-lock
            label: "Lock",
            command: ["loginctl", "lock-session"]
        },
        {
            key: "e",
            icon: "\u{f0343}", // nf-md-logout
            label: "Logout",
            command: ["hyprctl", "dispatch", "hl.dsp.exit()"]
        },
        {
            key: "u",
            icon: "\u{f04b2}", // nf-md-sleep
            label: "Suspend",
            command: ["systemctl", "suspend"]
        },
        {
            key: "h",
            icon: "\u{f0717}", // nf-md-snowflake
            label: "Hibernate",
            command: ["systemctl", "hibernate"]
        },
        {
            key: "r",
            icon: "\u{f0709}", // nf-md-restart
            label: "Reboot",
            command: ["systemctl", "reboot"]
        },
        {
            key: "s",
            icon: "\u{f0425}", // nf-md-power
            label: "Shutdown",
            command: ["systemctl", "poweroff"]
        }
    ]

    function run(action) {
        menuOpen = false;
        Quickshell.execDetached(action.command);
    }

    IpcHandler {
        target: "power"

        function toggle(): void {
            root.menuOpen = !root.menuOpen;
        }
        function close(): void {
            root.menuOpen = false;
        }
    }
}
