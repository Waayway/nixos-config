import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.services

// The system button at the right of the bar and its popover: volume, mic,
// brightness, Bluetooth, fan (Framework), power profile, tray, do-not-disturb
// and the power menu. The button shows Bluetooth, a hot fan and DND at a glance.
Rectangle {
    id: root

    property bool open: false

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: adapter ? adapter.devices.values.filter(d => d.connected) : []
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool hot: Fan.available && Fan.temperature >= 62

    implicitWidth: buttonRow.implicitWidth + 24
    implicitHeight: 30
    radius: 15
    color: open || hover.hovered ? Theme.blue : Theme.bgHighlight

    readonly property color iconColor: open || hover.hovered ? Theme.bg : Theme.fg

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    HoverHandler {
        id: hover
    }

    RowLayout {
        id: buttonRow
        anchors.centerIn: parent
        spacing: 8

        ButtonIcon {
            visible: root.adapter !== null
            text: root.btConnected.length > 0 ? "\u{f00b1}" : root.adapter?.enabled ? "\u{f00af}" : "\u{f00b2}"
            opacity: root.adapter?.enabled ? 1 : 0.5
        }
        ButtonIcon {
            visible: root.hot
            text: "\u{f0210}" // fan
            color: Fan.temperature >= 70 ? Theme.red : Theme.yellow
        }
        ButtonIcon {
            visible: Notifications.dnd
            text: "\u{f009b}" // bell-off
        }
        ButtonIcon {
            text: "\u{f062e}" // tune
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.open = !root.open;
            if (root.open)
                Brightness.refresh();
        }
    }

    // qs ipc call system toggle
    IpcHandler {
        target: "system"
        function toggle(): void {
            root.open = !root.open;
            if (root.open)
                Brightness.refresh();
        }
    }

    // Clicking anywhere else closes it.
    HyprlandFocusGrab {
        active: root.open
        windows: [popup, root.QsWindow.window]
        onCleared: root.open = false
    }

    PopupWindow {
        id: popup
        visible: root.open
        // 10 px below the bar, right edge on the button's right edge
        anchor.item: root
        anchor.rect: Qt.rect(0, 0, root.width, root.QsWindow.window ? root.QsWindow.window.height - root.mapToItem(null, 0, 0).y + 10 : root.height + 24)
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        implicitWidth: 380
        implicitHeight: content.implicitHeight + 28
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: Theme.rounding
            color: Theme.bgDark
            border.width: 2
            border.color: Theme.blue7

            ColumnLayout {
                id: content
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Sound + screen
                Card {
                    SliderRow {
                        Layout.fillWidth: true
                        icon: root.sink?.audio?.muted ? "\u{f075f}" : "\u{f057e}" // volume-off / volume-high
                        muted: root.sink?.audio?.muted ?? false
                        value: root.sink?.audio?.volume ?? 0
                        onMoved: v => {
                            if (root.sink?.audio)
                                root.sink.audio.volume = v;
                        }
                        onIconClicked: if (root.sink?.audio)
                            root.sink.audio.muted = !root.sink.audio.muted
                    }
                    SliderRow {
                        Layout.fillWidth: true
                        visible: root.source?.audio !== undefined && root.source !== null
                        icon: root.source?.audio?.muted ? "\u{f036d}" : "\u{f036c}" // microphone-off / microphone
                        muted: root.source?.audio?.muted ?? false
                        value: root.source?.audio?.volume ?? 0
                        onMoved: v => {
                            if (root.source?.audio)
                                root.source.audio.volume = v;
                        }
                        onIconClicked: if (root.source?.audio)
                            root.source.audio.muted = !root.source.audio.muted
                    }
                    SliderRow {
                        Layout.fillWidth: true
                        visible: Brightness.available
                        icon: "\u{f00e0}" // brightness-6
                        value: Brightness.value
                        onMoved: v => Brightness.set(v)
                    }
                }

                // Bluetooth
                Card {
                    visible: root.adapter !== null

                    RowLayout {
                        Layout.fillWidth: true
                        CardTitle {
                            Layout.fillWidth: true
                            text: "\u{f00af}  Bluetooth"
                        }
                        Chip {
                            text: root.adapter?.enabled ? "On" : "Off"
                            selected: root.adapter?.enabled ?? false
                            onClicked: if (root.adapter)
                                root.adapter.enabled = !root.adapter.enabled
                        }
                    }
                    Repeater {
                        model: root.btConnected
                        CardText {
                            required property BluetoothDevice modelData
                            text: modelData.name + (modelData.batteryAvailable ? `  ·  ${Math.round(modelData.battery * 100)}%` : "")
                        }
                    }
                    CardText {
                        visible: (root.adapter?.enabled ?? false) && root.btConnected.length === 0
                        text: "Nothing connected"
                        color: Theme.comment
                    }
                    Chip {
                        text: "Pair or connect…"
                        onClicked: {
                            root.open = false;
                            Quickshell.execDetached(["adw-bluetooth"]);
                        }
                    }
                }

                // Fan (Framework laptops, fw-fanctrl)
                Card {
                    visible: Fan.available

                    CardTitle {
                        text: `\u{f0210}  ${Math.round(Fan.temperature)}°  ·  fan ${Fan.speed}%`
                        color: Fan.temperature >= 70 ? Theme.red : Fan.temperature >= 62 ? Theme.yellow : Theme.fg
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip {
                            text: "auto"
                            selected: Fan.isDefault
                            onClicked: Fan.reset()
                        }
                        Repeater {
                            model: Fan.strategies
                            Chip {
                                required property string modelData
                                text: modelData
                                selected: !Fan.isDefault && Fan.strategy === modelData
                                dot: Fan.isDefault && Fan.strategy === modelData
                                onClicked: Fan.use(modelData)
                            }
                        }
                    }
                }

                // Power profile (power-profiles-daemon)
                Card {
                    CardTitle {
                        text: "\u{f140b}  Power profile"
                    }
                    RowLayout {
                        spacing: 6
                        Chip {
                            text: "Power saver"
                            selected: PowerProfiles.profile === PowerProfile.PowerSaver
                            onClicked: PowerProfiles.profile = PowerProfile.PowerSaver
                        }
                        Chip {
                            text: "Balanced"
                            selected: PowerProfiles.profile === PowerProfile.Balanced
                            onClicked: PowerProfiles.profile = PowerProfile.Balanced
                        }
                        Chip {
                            visible: PowerProfiles.hasPerformanceProfile
                            text: "Performance"
                            selected: PowerProfiles.profile === PowerProfile.Performance
                            onClicked: PowerProfiles.profile = PowerProfile.Performance
                        }
                    }
                }

                // Tray, DND, power
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Tray {
                        Layout.leftMargin: 6
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Chip {
                        text: Notifications.dnd ? "\u{f009b}  DND" : "\u{f009a}  DND"
                        selected: Notifications.dnd
                        onClicked: Notifications.dnd = !Notifications.dnd
                    }
                    Chip {
                        text: "\u{f0425}  Power"
                        onClicked: {
                            root.open = false;
                            Session.menuOpen = true;
                        }
                    }
                }
            }
        }
    }

    component ButtonIcon: Text {
        color: root.iconColor
        font.family: Theme.iconFont
        font.pixelSize: 16
    }

    component Card: Rectangle {
        default property alias items: cardColumn.data

        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 24
        radius: Theme.rounding
        color: Theme.bg

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
        }
    }

    component CardTitle: Text {
        color: Theme.fg
        font.family: Theme.iconFont
        font.pixelSize: 15
    }

    component CardText: Text {
        color: Theme.fgDark
        font.family: Theme.font
        font.pixelSize: 13
    }
}
