import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// Notification popups, top right of the primary monitor below the bar,
// newest on top.
PanelWindow {
    visible: Notifications.popups.length > 0
    anchors {
        top: true
        right: true
    }
    margins {
        top: 88 // bar: 20 margin + 58 high + 10
        right: 10
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    color: "transparent"

    implicitWidth: 500
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 6

        Repeater {
            model: [...Notifications.popups].reverse()

            NotificationCard {
                required property var modelData
                Layout.fillWidth: true
                notification: modelData
                popup: true
            }
        }
    }
}
