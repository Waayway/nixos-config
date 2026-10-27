import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.system

// The bar: a floating pill at the top of the primary monitor. 70% wide on
// wide screens; on narrow ones (the laptop panel, 1440 logical px) the full
// width minus Hyprland's gaps_out, or the contents don't fit.
PanelWindow {
    id: bar

    readonly property int side: {
        const w = screen?.width ?? 0;
        return w >= 1800 ? Math.round(w * 0.15) : 20;
    }

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: 20
        left: bar.side
        right: bar.side
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

        // Right: named workspaces, clock + battery, system popover (system/)
        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Workspaces {
                named: true
            }
            ClockBattery {}
            SystemMenu {}
        }
    }
}
