import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services

// Fan pill (Framework laptops only): CPU temperature and fan speed, coloured
// by temperature. Click for the fw-fanctrl strategies; "auto" goes back to the
// configured default.
Rectangle {
    id: pill

    property bool open: false

    visible: Fan.available
    implicitWidth: row.implicitWidth + 24
    implicitHeight: 30
    radius: 15
    color: Fan.temperature >= 70 ? Theme.red : Fan.temperature >= 62 ? Theme.yellow : Theme.bgHighlight

    Behavior on color {
        ColorAnimation {
            duration: 300
        }
    }

    readonly property color textColor: Fan.temperature >= 62 ? Theme.bg : Theme.fg

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: "\u{f0210}" // nf-md-fan
            color: pill.textColor
            font.family: Theme.iconFont
            font.pixelSize: 16
        }
        Text {
            text: `${Math.round(Fan.temperature)}° ${Fan.speed}%`
            color: pill.textColor
            font.family: Theme.font
            font.pixelSize: 15
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.open = !pill.open
    }

    PopupWindow {
        visible: pill.open
        anchor.item: pill
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 14
        implicitWidth: 180
        implicitHeight: list.implicitHeight + 16
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: Theme.rounding
            color: Theme.bg
            border.width: 2
            border.color: Theme.blue7

            ColumnLayout {
                id: list
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Choice {
                    label: "auto"
                    selected: Fan.isDefault
                    onPicked: Fan.reset()
                }
                Repeater {
                    model: Fan.strategies

                    Choice {
                        required property string modelData
                        label: modelData
                        selected: !Fan.isDefault && Fan.strategy === modelData
                        current: Fan.strategy === modelData
                        onPicked: Fan.use(modelData)
                    }
                }
            }
        }
    }

    component Choice: Rectangle {
        id: choice
        property string label
        property bool selected: false
        property bool current: false // what's running, e.g. under "auto"
        signal picked

        Layout.fillWidth: true
        implicitHeight: 28
        radius: 8
        color: selected ? Theme.blue : hover.hovered ? Theme.bgHighlight : "transparent"

        HoverHandler {
            id: hover
        }
        Text {
            anchors.fill: parent
            anchors.leftMargin: 10
            verticalAlignment: Text.AlignVCenter
            text: choice.label + (choice.current && !choice.selected ? "  ·" : "")
            color: choice.selected ? Theme.bg : Theme.fg
            font.family: Theme.font
            font.pixelSize: 14
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                choice.picked();
                pill.open = false;
            }
        }
    }
}
