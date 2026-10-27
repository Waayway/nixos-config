import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// Full-screen power menu over the primary monitor: lock, logout, suspend,
// hibernate, reboot, shutdown. Click, or press the underlined key; Escape or
// a click on the background closes it.
PanelWindow {
    id: menu

    visible: Session.menuOpen
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-power-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: Qt.alpha(Theme.bgDark, 0.85)

    MouseArea {
        anchors.fill: parent
        onClicked: Session.menuOpen = false
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Session.menuOpen = false;
                return;
            }
            const action = Session.actions.find(a => a.key === event.text.toLowerCase());
            if (action)
                Session.run(action);
        }
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: 24

        Repeater {
            model: Session.actions

            Rectangle {
                id: button
                required property var modelData

                implicitWidth: 180
                implicitHeight: 200
                radius: Theme.rounding * 2
                color: hover.hovered ? Theme.blue : Theme.bg
                border.width: 2
                border.color: hover.hovered ? Theme.blue : Theme.blue7

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }

                HoverHandler {
                    id: hover
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: button.modelData.icon
                        color: hover.hovered ? Theme.bg : Theme.fg
                        font.family: Theme.iconFont
                        font.pixelSize: 72
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        // underline the shortcut letter
                        text: {
                            const l = button.modelData.label;
                            const i = l.toLowerCase().indexOf(button.modelData.key);
                            return i < 0 ? l : `${l.slice(0, i)}<u>${l[i]}</u>${l.slice(i + 1)}`;
                        }
                        textFormat: Text.StyledText
                        color: hover.hovered ? Theme.bg : Theme.fgDark
                        font.family: Theme.font
                        font.pixelSize: 18
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Session.run(button.modelData)
                }
            }
        }
    }
}
