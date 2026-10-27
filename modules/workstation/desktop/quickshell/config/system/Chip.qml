import QtQuick
import qs.services

// Small pill button; `selected` fills it blue.
Rectangle {
    id: root

    property string text
    property bool selected: false
    property bool dot: false // marks what's running under "auto"
    signal clicked

    implicitWidth: label.implicitWidth + 20
    implicitHeight: 28
    radius: 14
    color: selected ? Theme.blue : hover.hovered ? Theme.bgHighlight : "transparent"
    border.width: selected ? 0 : 1
    border.color: Theme.bgHighlight

    HoverHandler {
        id: hover
    }

    Text {
        id: label
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.text + (root.dot && !root.selected ? " ·" : "")
        color: root.selected ? Theme.bg : Theme.fg
        font.family: Theme.iconFont
        font.pixelSize: 13
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
