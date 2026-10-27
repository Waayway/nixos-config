import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services

// Clock, with the battery attached on laptops. The battery reads relative to
// the charge limit (charge_control_end_threshold, 80% on hermes), so a battery
// charged up to its limit shows 100%. Hovering shows the real charge and the
// time left (or until the limit).
RowLayout {
    id: root

    readonly property UPowerDevice battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isLaptopBattery ?? false
    readonly property bool charging: battery?.state !== UPowerDeviceState.Discharging

    // Charge limit in %, 100 when there is none.
    readonly property string batteryName: UPower.devices.values.find(d => d.isLaptopBattery)?.nativePath ?? ""
    readonly property int limit: {
        const n = parseInt(limitFile.text());
        return n > 0 && n <= 100 ? n : 100;
    }
    readonly property real raw: (battery?.percentage ?? 0) * 100 // real charge, %
    readonly property int shown: Math.min(100, Math.round(raw / limit * 100))

    FileView {
        id: limitFile
        path: root.batteryName ? `/sys/class/power_supply/${root.batteryName}/charge_control_end_threshold` : ""
        printErrors: false
    }

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
                const pct = `${root.shown}%`;
                if (!hover.hovered || !root.battery)
                    return pct;
                const real = root.limit < 100 ? ` (${Math.round(root.raw)}% of ${root.limit}%)` : "";
                if (root.battery.state === UPowerDeviceState.Discharging && root.battery.timeToEmpty > 0)
                    return `${pct}${real} · ${root.duration(root.battery.timeToEmpty)} left`;
                if (root.battery.state === UPowerDeviceState.Charging && root.battery.timeToFull > 0 && root.raw < root.limit) {
                    // UPower counts to 100%; scale its estimate to the limit.
                    const toLimit = root.battery.timeToFull * (root.limit - root.raw) / (100 - root.raw);
                    return `${pct}${real} · full in ${root.duration(toLimit)}`;
                }
                return pct + real;
            }
        }
    }
}
