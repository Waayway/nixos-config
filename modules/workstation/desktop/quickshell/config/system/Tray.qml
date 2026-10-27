import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// System tray: left click activates (or opens the menu for menu-only items),
// right click opens the menu.
RowLayout {
    id: root

    spacing: 16

    Repeater {
        model: SystemTray.items

        IconImage {
            id: icon
            required property SystemTrayItem modelData

            implicitSize: 20
            source: modelData.icon

            QsMenuAnchor {
                id: menu
                menu: icon.modelData.menu
                anchor.item: icon
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton || icon.modelData.onlyMenu) {
                        if (icon.modelData.hasMenu)
                            menu.open();
                    } else {
                        icon.modelData.activate();
                    }
                }
            }
        }
    }
}
