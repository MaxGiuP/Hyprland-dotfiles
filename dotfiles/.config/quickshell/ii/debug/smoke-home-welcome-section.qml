//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1
//@ pragma Env II_SETTINGS_APP=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    visible: true
    width: 960
    height: 720
    title: "smoke-home-welcome-section"
    color: Appearance.m3colors.m3background

    ContentPage {
        anchors.fill: parent
        forceWidth: true
        baseWidth: 760

        ContentSection {
            icon: "person"
            title: `${SystemInfo.username} \u2014 ${SystemInfo.distroName}`

            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Layout.topMargin: 4
                Layout.bottomMargin: 4

                Rectangle {
                    implicitWidth: 200
                    implicitHeight: 112
                    radius: Appearance.rounding.normal
                    color: "transparent"
                    clip: true

                    StyledImage {
                        anchors.fill: parent
                        sourceSize.width: parent.implicitWidth
                        sourceSize.height: parent.implicitHeight
                        fillMode: Image.PreserveAspectCrop
                        source: Config.options.background.wallpaperPath
                        cache: false
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        spacing: 6
                        Layout.fillWidth: true

                        Repeater {
                            model: [
                                { dark: false, icon: "light_mode", label: Translation.tr("Light") },
                                { dark: true, icon: "dark_mode", label: Translation.tr("Dark") }
                            ]

                            delegate: RippleButton {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 48
                                buttonRadius: Appearance.rounding.normal
                                toggled: Appearance.m3colors.darkmode === modelData.dark
                                colBackground: Appearance.colors.colLayer2

                                contentItem: ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        iconSize: 22
                                        text: modelData.icon
                                        color: parent.parent.toggled
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer2
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: parent.parent.toggled
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "wallpaper"
                        mainText: Translation.tr("Change wallpaper")
                    }
                }
            }
        }
    }
}
