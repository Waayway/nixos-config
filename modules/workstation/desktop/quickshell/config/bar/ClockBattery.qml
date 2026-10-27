import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.services

// Clock, with the battery attached on laptops. Hovering the battery shows the
// time left (or until full).
RowLayout {
    id: root

    readonly property UPowerDevice battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false
    readonly property bool charging: battery?.state !== UPowerDeviceState.Discharging

    spacing: 0

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    function duration(seconds) {
        const mins = Math.round(seconds / 60);
        const h = Math.floor(mins / 60);
        return h > 0 ? `${h}h ${mins % 60}m` : `${mins}m`;
    }

    Rectangle {
        implicitWidth: clockText.implicitWidth + 24
        implicitHeight: 30
        color: Theme.bgHighlight
        topLeftRadius: 15
        bottomLeftRadius: 15
        topRightRadius: root.hasBattery ? 0 : 15
        bottomRightRadius: root.hasBattery ? 0 : 15

        Text {
            id: clockText
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 16
        }
    }

    Rectangle {
        visible: root.hasBattery
        implicitWidth: batteryText.implicitWidth + 29
        implicitHeight: 30
        color: root.charging ? Theme.green : Theme.red1
        topRightRadius: 15
        bottomRightRadius: 15

        // the 5px gap between clock and battery
        Rectangle {
            width: 5
            height: parent.height
            color: Theme.bg
        }

        HoverHandler {
            id: hover
        }

        Text {
            id: batteryText
            anchors.fill: parent
            anchors.leftMargin: 5 // past the gap strip
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Theme.bg
            font.family: Theme.font
            font.pixelSize: 16
            text: {
                const pct = `${Math.round((root.battery?.percentage ?? 0) * 100)}%`;
                if (!hover.hovered || !root.battery)
                    return pct;
                if (root.battery.state === UPowerDeviceState.Discharging && root.battery.timeToEmpty > 0)
                    return `${pct} · ${root.duration(root.battery.timeToEmpty)} left`;
                if (root.battery.state === UPowerDeviceState.Charging && root.battery.timeToFull > 0)
                    return `${pct} · full in ${root.duration(root.battery.timeToFull)}`;
                return pct;
            }
        }
    }
}
