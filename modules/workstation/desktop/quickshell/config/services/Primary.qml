pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The primary monitor. Hyprland has none, so Hyprland's monitor policy
// (hyprland/config/lua/monitor_policy.lua) picks one, writes its connector name
// to $XDG_RUNTIME_DIR/hypr/primary-monitor and sends `custom>>primary>>NAME`.
// The file covers startup and restarts; the event covers changes.
Singleton {
    id: root

    property string name: ""

    // The matching screen; the first one until the policy has said anything,
    // or while the named screen isn't known to Quickshell yet.
    readonly property ShellScreen screen: {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === root.name)
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    FileView {
        id: file
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/primary-monitor"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const n = text().trim();
            if (n !== "")
                root.name = n;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "custom" && event.data.startsWith("primary>>"))
                root.name = event.data.slice("primary>>".length).trim();
        }
    }
}
