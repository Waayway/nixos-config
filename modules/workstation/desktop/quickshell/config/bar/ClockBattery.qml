import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services

// Clock, with the battery attached on laptops. The battery reads relative to
// the charge limit (charge_control_end_threshold, 80% on hermes), so a battery
// charged up to its limit shows 100%. Hovering opens a popover with the real
// charge and the time left (or until the limit).
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
        id: batteryPill
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
            text: `${root.shown}%`
            color: Theme.bg
            font.family: Theme.font
            font.pixelSize: 16
        }

        // Details while hovering: real charge vs the limit, and time left.
        PopupWindow {
            visible: hover.hovered && root.battery !== null
            // 10 px below the bar, centred under the pill
            anchor.item: batteryPill
            anchor.rect: Qt.rect(0, 0, batteryPill.width, batteryPill.QsWindow.window ? batteryPill.QsWindow.window.height - batteryPill.mapToItem(null, 0, 0).y + 10 : batteryPill.height + 24)
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom
            implicitWidth: details.implicitWidth + 24
            implicitHeight: details.implicitHeight + 20
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                radius: Theme.rounding
                color: Theme.bg
                border.width: 2
                border.color: Theme.blue7

                Column {
                    id: details
                    anchors.centerIn: parent
                    spacing: 4

                    DetailText {
                        text: root.limit < 100 ? `${Math.round(root.raw)}% of the ${root.limit}% limit` : `${Math.round(root.raw)}%`
                    }
                    DetailText {
                        color: Theme.fgDark
                        text: {
                            const b = root.battery;
                            if (!b)
                                return "";
                            if (b.state === UPowerDeviceState.Discharging)
                                return b.timeToEmpty > 0 ? `${root.duration(b.timeToEmpty)} left` : "On battery";
                            if (b.state === UPowerDeviceState.Charging && b.timeToFull > 0 && root.raw < root.limit) {
                                // UPower counts to 100%; scale its estimate to the limit.
                                const toLimit = b.timeToFull * (root.limit - root.raw) / (100 - root.raw);
                                return `Full in ${root.duration(toLimit)}`;
                            }
                            return root.raw >= root.limit - 1 ? "Charged to the limit" : "Plugged in";
                        }
                    }
                }
            }
        }
    }

    component DetailText: Text {
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: 14
    }
}
