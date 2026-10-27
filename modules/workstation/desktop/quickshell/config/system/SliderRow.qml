import QtQuick
import QtQuick.Layouts
import qs.services

// Icon (clickable) + slider + percentage.
RowLayout {
    id: root

    property string icon
    property real value: 0 // 0..1
    property bool muted: false
    signal moved(real value)
    signal iconClicked

    spacing: 10

    Text {
        Layout.preferredWidth: 22
        horizontalAlignment: Text.AlignHCenter
        text: root.icon
        color: root.muted ? Theme.comment : Theme.fg
        font.family: Theme.iconFont
        font.pixelSize: 18

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: root.iconClicked()
        }
    }

    Item {
        id: track
        Layout.fillWidth: true
        implicitHeight: 20

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: Theme.bgHighlight

            Rectangle {
                width: parent.width * root.value
                height: parent.height
                radius: 3
                color: root.muted ? Theme.comment : Theme.blue
            }
        }

        Rectangle {
            x: (track.width - width) * root.value
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: 8
            color: Theme.fg
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function update(mouse) {
                root.moved(Math.max(0, Math.min(1, mouse.x / track.width)));
            }
            onPressed: mouse => update(mouse)
            onPositionChanged: mouse => update(mouse)
            onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }

    Text {
        Layout.preferredWidth: 40
        horizontalAlignment: Text.AlignRight
        text: `${Math.round(root.value * 100)}%`
        color: Theme.fgDark
        font.family: Theme.font
        font.pixelSize: 13
    }
}
