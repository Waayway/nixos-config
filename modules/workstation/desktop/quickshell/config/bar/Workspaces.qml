import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services

// Numbered workspaces 1-10 (always shown), or the named ones: the fixed list
// from hyprland/config/lua/rules.lua plus any other named workspace that exists.
// Purple = empty, blue = has windows, green = shown on a monitor.
RowLayout {
    id: root

    property bool named: false
    readonly property var fixedNames: ["󰝚", "󰭹", "󰊴"]

    readonly property var all: Hyprland.workspaces.values
    readonly property var entries: {
        if (!named)
            return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(id => ({
                        key: String(id),
                        selector: id,
                        ws: all.find(w => w.id === id) ?? null
                    }));
        const names = [...fixedNames];
        for (const w of all) {
            if (isNaN(Number(w.name)) && !w.name.startsWith("special:") && !names.includes(w.name))
                names.push(w.name);
        }
        return names.map(name => ({
                    key: name,
                    selector: `"name:${name}"`,
                    ws: all.find(w => w.name === name) ?? null
                }));
    }

    spacing: 10

    Repeater {
        model: root.entries

        Rectangle {
            required property var modelData
            readonly property var ws: modelData.ws
            readonly property bool shown: ws?.active ?? false
            readonly property bool occupied: (ws?.toplevels.values.length ?? 0) > 0

            implicitWidth: root.named ? 34 : 24
            implicitHeight: implicitWidth
            radius: implicitWidth / 2
            color: shown ? Theme.green : occupied ? Theme.blue : Theme.purple

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }

            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData.key
                color: Theme.bg
                font.family: root.named ? Theme.iconFont : Theme.font
                font.pixelSize: root.named ? 18 : 13
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ workspace = ${modelData.selector} })`])
            }
        }
    }
}
