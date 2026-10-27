import QtQuick
import Quickshell
import qs.services

Rectangle {
    implicitWidth: 52
    implicitHeight: 40
    radius: Theme.rounding
    color: Theme.blue

    Text {
        id: label
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "\uf313" // nf-linux-nixos
        color: Theme.bg
        font.family: Theme.iconFont
        font.pixelSize: 22
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["sh", "-c", "rofi -show drun -theme ~/.config/rofi/theme.rasi"])
    }
}
