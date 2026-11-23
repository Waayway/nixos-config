pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Fan state from fw-fanctrl (Framework laptops, hardware/framework.nix).
// `available` stays false where fw-fanctrl isn't installed or running, so the
// bar hides the widget on every other machine.
Singleton {
    id: root

    property bool available: false
    // Whether fw-fanctrl is on PATH at all; checked once at startup so the poll below
    // doesn't fail every 3 s (and fill the log) on machines without it.
    property bool installed: false
    property string strategy: ""
    property bool isDefault: true // false while a strategy is chosen by hand
    property int speed: 0 // %
    property real temperature: 0 // °C, what the curve uses
    property var strategies: []

    function use(name) {
        Quickshell.execDetached(["fw-fanctrl", "use", name]);
        refresh.restart();
    }
    // back to the configured default (and its on-battery switch)
    function reset() {
        Quickshell.execDetached(["fw-fanctrl", "reset"]);
        refresh.restart();
    }

    Process {
        running: true
        command: ["sh", "-c", "command -v fw-fanctrl"]
        onExited: code => root.installed = code === 0
    }

    Process {
        id: poll
        command: ["fw-fanctrl", "--output-format", "JSON", "print", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d.status !== "success")
                        throw d.status;
                    root.strategy = d.strategy;
                    root.isDefault = d.default;
                    root.speed = d.speed;
                    root.temperature = d.temperature;
                    root.strategies = Object.keys(d.configuration?.data?.strategies ?? {}).sort();
                    root.available = true;
                } catch (e) {
                    root.available = false;
                }
            }
        }
        onExited: code => {
            if (code !== 0)
                root.available = false;
        }
    }

    Timer {
        id: refresh
        interval: 3000
        running: root.installed
        repeat: true
        triggeredOnStart: true
        onTriggered: poll.running = true
    }
}
