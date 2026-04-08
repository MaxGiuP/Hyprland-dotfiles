//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1
//@ pragma Env II_SETTINGS_APP=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: window
    visible: true
    width: 960
    height: 720
    title: "smoke-home-audio-section"
    color: Appearance.m3colors.m3background

    ContentPage {
        id: root
        anchors.fill: parent
        forceWidth: true
        baseWidth: 760

        readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"
        readonly property var trackedOutputDevices: root.settingsApp ? [] : Audio.outputDevices.filter(d => d.name !== "qs_mono_out")
        readonly property var realOutputDevices: root.settingsApp ? [] : Audio.selectableOutputDevices.filter(d => d.name !== "qs_mono_out")

        PwObjectTracker {
            objects: root.trackedOutputDevices
        }

        ContentSection {
            icon: "volume_up"
            title: Translation.tr("Audio output")

            StyledComboBox {
                Layout.fillWidth: true
                buttonIcon: "speaker"
                textRole: "displayName"
                model: root.realOutputDevices.map(d => ({ displayName: Audio.friendlyDeviceName(d) }))
                currentIndex: Math.max(0, root.realOutputDevices.findIndex(d => Audio.isCurrentDefaultSink(d)))
                onActivated: index => Audio.setDefaultSink(root.realOutputDevices[index])
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 40
                    implicitHeight: 40
                    onClicked: Audio.toggleMute()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 1.54
                    value: Audio.value
                    configuration: StyledSlider.Configuration.M
                    usePercentTooltip: false
                    tooltipContent: `${Math.round(value * 100)}%`
                    onMoved: {
                        if (Audio.sink?.audio) Audio.sink.audio.volume = value
                    }
                }

                StyledText {
                    text: `${Math.round(Audio.value * 100)}%`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }
}
