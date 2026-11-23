import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services

// Screen-share picker (replaces hyprland-share-picker): a full-screen overlay on the primary
// monitor with a live preview of every monitor and every shareable window. Click one to
// share it; Escape or a click on the background cancels. State: services/SharePicker.qml.
PanelWindow {
    id: picker

    visible: SharePicker.open
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-share-picker"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: Qt.alpha(Theme.bgDark, 0.85)

    MouseArea {
        anchors.fill: parent
        onClicked: SharePicker.cancel()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                SharePicker.cancel();
        }
    }

    // A preview card: live capture on top, a label underneath.
    component Card: Rectangle {
        id: card

        property var source: null
        property string label: ""
        property string sublabel: ""
        property string fallbackIcon: ""
        property real previewWidth: 320
        signal chosen

        implicitWidth: previewWidth + 24
        implicitHeight: content.implicitHeight + 24
        radius: Theme.rounding
        color: hover.hovered ? Theme.bgHighlight : Theme.bg
        border.width: 2
        border.color: hover.hovered ? Theme.blue : Theme.blue7

        Behavior on border.color {
            ColorAnimation {
                duration: 120
            }
        }

        HoverHandler {
            id: hover
        }
        TapHandler {
            onTapped: card.chosen()
        }

        ColumnLayout {
            id: content
            anchors.centerIn: parent
            width: card.previewWidth
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: card.previewWidth * 9 / 16
                radius: Theme.rounding / 2
                color: Theme.bgDark
                clip: true

                // Only exists while the picker is open. A hidden ScreencopyView still holds its
                // screen, and when outputs go away and come back (resume from suspend) Quickshell
                // 0.3.0 captures the destroyed QScreen and segfaults.
                Loader {
                    id: preview
                    anchors.fill: parent
                    active: picker.visible && card.source !== null
                    sourceComponent: ScreencopyView {
                        captureSource: card.source
                        live: true
                        constraintSize: Qt.size(card.previewWidth * 2, card.previewWidth * 9 / 8)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !(preview.item && preview.item.hasContent)
                    text: card.fallbackIcon
                    color: Theme.comment
                    font.family: Theme.iconFont
                    font.pixelSize: 48
                }
            }

            Text {
                Layout.fillWidth: true
                text: card.label
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 15
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.sublabel
                color: Theme.comment
                font.family: Theme.font
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }
    }

    component SectionTitle: Text {
        color: Theme.fgDark
        font.family: Theme.font
        font.pixelSize: 14
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.5
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: Math.min(parent.width - 96, 1500)
        height: Math.min(parent.height - 96, layout.implicitHeight + 48)
        radius: Theme.rounding * 2
        color: Theme.bgDark
        border.width: 2
        border.color: Theme.blue7

        // Clicks on the panel itself must not cancel.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "\u{f0a3e}  Share your screen" // nf-md-monitor_share
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 22
                    font.bold: true
                }
                Item {
                    Layout.fillWidth: true
                }

                // Remember: the app may restore this choice next time without asking.
                Rectangle {
                    implicitWidth: rememberRow.implicitWidth + 24
                    implicitHeight: 38
                    radius: 19
                    color: SharePicker.allowToken ? Theme.blue7 : Theme.bg
                    border.width: 1
                    border.color: SharePicker.allowToken ? Theme.blue : Theme.comment

                    RowLayout {
                        id: rememberRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: SharePicker.allowToken ? "\u{f0132}" : "\u{f0131}" // checkbox marked / blank
                            color: SharePicker.allowToken ? Theme.blue : Theme.comment
                            font.family: Theme.iconFont
                            font.pixelSize: 18
                        }
                        Text {
                            text: "Remember for this app"
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 14
                        }
                    }
                    TapHandler {
                        onTapped: SharePicker.allowToken = !SharePicker.allowToken
                    }
                }

                Rectangle {
                    implicitWidth: cancelText.implicitWidth + 32
                    implicitHeight: 38
                    radius: 19
                    color: cancelHover.hovered ? Theme.red : Theme.bg
                    border.width: 1
                    border.color: Theme.red
                    Text {
                        id: cancelText
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: cancelHover.hovered ? Theme.bgDark : Theme.red
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.bold: true
                    }
                    HoverHandler {
                        id: cancelHover
                    }
                    TapHandler {
                        onTapped: SharePicker.cancel()
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: sections.implicitHeight
                contentHeight: sections.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: sections
                    width: parent.width
                    spacing: 14

                    SectionTitle {
                        text: "Screens"
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 16

                        Repeater {
                            model: Quickshell.screens

                            Card {
                                required property ShellScreen modelData
                                previewWidth: 400
                                source: modelData
                                label: modelData.name + (modelData.name === Primary.name ? "  \u{f04ce}" : "") // star on the primary
                                // Real pixels from Hyprland: Qt rounds a fractional scale (1.6) up.
                                readonly property var monitor: Hyprland.monitorFor(modelData)
                                sublabel: [modelData.model, monitor ? monitor.width + "×" + monitor.height : ""].filter(s => s).join("  ·  ")
                                fallbackIcon: "\u{f0379}" // nf-md-monitor
                                onChosen: SharePicker.chooseScreen(modelData.name)
                            }
                        }
                    }

                    SectionTitle {
                        Layout.topMargin: 8
                        visible: SharePicker.windows.length > 0
                        text: "Windows"
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 16

                        Repeater {
                            model: SharePicker.windows

                            Card {
                                required property var modelData
                                previewWidth: 280
                                source: SharePicker.toplevelFor(modelData.address)
                                label: modelData.title || modelData.cls
                                sublabel: modelData.title ? modelData.cls : ""
                                fallbackIcon: "\u{f05b6}" // nf-md-application
                                onChosen: SharePicker.chooseWindow(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
