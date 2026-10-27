import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// The bar: a floating pill at the top of the primary monitor, 70% wide.
PanelWindow {
    id: bar

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: 20
        left: Math.round((screen?.width ?? 0) * 0.15)
        right: Math.round((screen?.width ?? 0) * 0.15)
    }
    implicitHeight: 58
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: Theme.rounding
        color: Theme.bg

        // Left: launcher + numbered workspaces
        RowLayout {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Launcher {}
            Workspaces {
                named: false
            }
        }

        // Centre: media
        Media {
            anchors.centerIn: parent
        }

        // Right: named workspaces, clock + battery, tray
        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Workspaces {
                named: true
            }
            FanControl {}
            ClockBattery {}
            Tray {}
        }
    }
}
