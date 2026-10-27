pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Screen backlight through brightnessctl (laptops). `available` is false where
// there is no backlight, e.g. the desktop.
Singleton {
    id: root

    property bool available: false
    property real value: 0 // 0..1

    function refresh() {
        read.running = true;
    }

    // Slider drags call this often; apply at most every 50 ms.
    function set(v) {
        value = Math.max(0.01, Math.min(1, v));
        apply.restart();
    }

    Process {
        id: read
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                // amdgpu_bl1,backlight,65535,100%,65535
                const f = text.trim().split(",");
                root.available = f.length >= 5;
                if (root.available)
                    root.value = Number(f[2]) / Number(f[4]);
            }
        }
    }

    Timer {
        id: apply
        interval: 50
        onTriggered: Quickshell.execDetached(["brightnessctl", "-c", "backlight", "-q", "s", `${Math.round(root.value * 100)}%`])
    }

    Component.onCompleted: refresh()
}
