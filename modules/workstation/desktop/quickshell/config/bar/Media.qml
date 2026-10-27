import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.services

// Now playing: prev / play-pause (title + artist) / next on a gradient.
// Hover slides in the volume: scroll to change, click to mute.
Item {
    id: root

    // The playing player, else the first one.
    readonly property MprisPlayer player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property PwNode sink: Pipewire.defaultAudioSink

    visible: player !== null
    implicitWidth: Math.max(280, row.implicitWidth + 32)
    implicitHeight: 42

    PwObjectTracker {
        objects: [root.sink]
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rounding
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.4
                color: Qt.alpha(Theme.blue, 0.8)
            }
            GradientStop {
                position: 1.0
                color: Qt.alpha(Theme.purple, 0.7)
            }
        }
    }

    HoverHandler {
        id: hover
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        // Volume, revealed on hover
        Item {
            Layout.preferredWidth: hover.hovered ? volume.implicitWidth : 0
            Layout.preferredHeight: volume.implicitHeight
            clip: true

            Behavior on Layout.preferredWidth {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                id: volume
                spacing: 10

                MediaText {
                    text: {
                        const a = root.sink?.audio;
                        if (!a)
                            return "";
                        return a.muted ? "󰝟" : `${Math.round(a.volume * 100)}%`;
                    }
                    onClicked: if (root.sink?.audio)
                        root.sink.audio.muted = !root.sink.audio.muted
                }
                MediaText {
                    text: "󰋎"
                    font.family: Theme.iconFont
                    onClicked: Quickshell.execDetached(["pavucontrol"])
                }
            }

            WheelHandler {
                onWheel: event => {
                    const a = root.sink?.audio;
                    if (!a)
                        return;
                    const step = event.angleDelta.y > 0 ? 0.05 : -0.05;
                    a.volume = Math.max(0, Math.min(1, a.volume + step));
                }
            }
        }

        MediaText {
            text: "󰒮"
            font.family: Theme.iconFont
            onClicked: root.player?.previous()
        }

        ColumnLayout {
            spacing: 0

            MediaText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 200
                elide: Text.ElideRight
                text: root.player?.isPlaying ? (root.player.trackTitle || "Unknown") : "Paused"
                onClicked: root.player?.togglePlaying()
            }
            MediaText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 200
                elide: Text.ElideRight
                visible: root.player?.isPlaying ?? false
                text: root.player?.trackArtist ?? ""
                font.pixelSize: 9
                onClicked: root.player?.togglePlaying()
            }
        }

        MediaText {
            text: "󰒭"
            font.family: Theme.iconFont
            onClicked: root.player?.next()
        }
    }

    component MediaText: Text {
        signal clicked

        verticalAlignment: Text.AlignVCenter
        color: Theme.bg
        font.family: Theme.font
        font.pixelSize: 16

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
