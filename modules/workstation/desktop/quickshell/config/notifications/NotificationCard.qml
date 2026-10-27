import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.services

// One notification. As a popup it hides itself after its timeout (paused
// while hovered); clicking runs the default action, × dismisses it for good.
Rectangle {
    id: card

    required property Notification notification
    property bool popup: false

    readonly property bool critical: notification.urgency === NotificationUrgency.Critical

    implicitHeight: content.implicitHeight + 24
    radius: Theme.rounding
    color: Theme.bg
    border.width: 2
    border.color: critical ? Theme.red : Theme.blue7

    HoverHandler {
        id: hover
    }

    Timer {
        running: card.popup && !hover.hovered && interval > 0
        interval: Notifications.timeout(card.notification)
        onTriggered: Notifications.hidePopup(card.notification)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            const def = card.notification.actions.find(a => a.identifier === "default");
            if (def)
                def.invoke();
            else if (card.popup)
                Notifications.hidePopup(card.notification);
        }
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        IconImage {
            Layout.alignment: Qt.AlignTop
            visible: source != ""
            implicitSize: 64
            source: card.notification.image || (card.notification.appIcon ? Quickshell.iconPath(card.notification.appIcon, true) : "")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: card.notification.summary
                    elide: Text.ElideRight
                    color: card.critical ? Theme.red : Theme.green
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    text: card.notification.appName
                    color: Theme.comment
                    font.family: Theme.font
                    font.pixelSize: 12
                }
                Text {
                    text: "×"
                    color: Theme.red
                    font.pixelSize: 20

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.notification.dismiss()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notification.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 4 : 10
                elide: Text.ElideRight
                color: Theme.fgDark
                font.family: Theme.font
                font.pixelSize: 14
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            RowLayout {
                Layout.fillWidth: true
                visible: actionRepeater.count > 0
                spacing: 6

                Repeater {
                    id: actionRepeater
                    model: card.notification.actions.filter(a => a.identifier !== "default")

                    Rectangle {
                        required property NotificationAction modelData

                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: 8
                        color: actionHover.hovered ? Theme.blue : Theme.bgHighlight

                        HoverHandler {
                            id: actionHover
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.text
                            color: actionHover.hovered ? Theme.bg : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.invoke()
                        }
                    }
                }
            }
        }
    }
}
