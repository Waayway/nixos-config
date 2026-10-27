import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// Notification history on the right of the primary monitor, SUPER+SHIFT+N
// (`qs ipc call notifications toggle`). Clear all and do-not-disturb at the top.
PanelWindow {
    visible: Notifications.panelOpen
    anchors {
        top: true
        right: true
        bottom: true
    }
    margins {
        top: 10
        right: 10
        bottom: 10
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notification-panel"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    implicitWidth: 500

    Rectangle {
        anchors.fill: parent
        radius: Theme.rounding
        color: Theme.bgDark
        border.width: 2
        border.color: Theme.blue7

        // Escape closes
        Item {
            focus: true
            Keys.onEscapePressed: Notifications.panelOpen = false
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: Theme.blue
                    font.family: Theme.font
                    font.pixelSize: 22
                }
                PanelButton {
                    text: Notifications.dnd ? "󰂛 DND" : "󰂚 DND"
                    active: Notifications.dnd
                    onClicked: Notifications.dnd = !Notifications.dnd
                }
                PanelButton {
                    text: "󰆴 Clear"
                    onClicked: Notifications.clear()
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: Notifications.history.length === 0
                text: "No notifications"
                color: Theme.comment
                font.family: Theme.font
                font.pixelSize: 14
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: [...Notifications.history].reverse()

                delegate: NotificationCard {
                    required property var modelData
                    width: ListView.view.width
                    notification: modelData
                }
            }
        }
    }

    component PanelButton: Rectangle {
        id: button
        property alias text: label.text
        property bool active: false
        signal clicked

        implicitWidth: label.implicitWidth + 20
        implicitHeight: 30
        radius: 8
        color: active ? Theme.red : buttonHover.hovered ? Theme.blue : Theme.bgHighlight

        HoverHandler {
            id: buttonHover
        }
        Text {
            id: label
            anchors.centerIn: parent
            color: button.active || buttonHover.hovered ? Theme.bg : Theme.fg
            font.family: Theme.font
            font.pixelSize: 14
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }
}
