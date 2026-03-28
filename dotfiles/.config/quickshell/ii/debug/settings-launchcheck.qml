//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env II_SETTINGS_APP=1
//@ pragma Env II_STANDALONE_APP=1

//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: root

    property real contentPadding: 8
    property int currentPage: 0
    property var pages: [
        { displayName: Translation.tr("Home"), component: "../modules/settings/HomeConfigStandalone.qml" },
        { displayName: Translation.tr("Bluetooth & devices"), component: "../modules/settings/BluetoothDevicesConfig.qml" },
        { displayName: Translation.tr("Display"), component: "../modules/settings/DisplayPowerConfig.qml" },
        { displayName: Translation.tr("Audio"), component: "../modules/settings/AudioControlConfig.qml" },
        { displayName: Translation.tr("Internet"), component: "../modules/settings/InternetConfig.qml" },
        { displayName: Translation.tr("Customisation"), component: "../modules/settings/DesktopThemeConfig.qml" },
        { displayName: Translation.tr("Apps"), component: "../modules/settings/AppsHubConfig.qml" },
        { displayName: Translation.tr("Account"), component: "../modules/settings/AccountsConfig.qml" },
        { displayName: Translation.tr("Date, time & language"), component: "../modules/settings/DateTimeLanguageConfig.qml" },
        { displayName: Translation.tr("Accessibility"), component: "../modules/settings/AccessibilityConfig.qml" },
        { displayName: Translation.tr("Security & privacy"), component: "../modules/settings/PrivacySecurityConfig.qml" },
        { displayName: Translation.tr("System info & update"), component: "../modules/settings/SystemInfoUpdateConfig.qml" },
        { displayName: Translation.tr("Services"), component: "../modules/settings/ServicesConfig.qml" },
        { displayName: Translation.tr("Hyprland"), component: "../modules/settings/HyprConfig.qml" }
    ]

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings"
    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.contentPadding
        spacing: root.contentPadding

        RowLayout {
            id: titlebar
            readonly property bool showTitlebar: Config.options?.windows?.showTitlebar ?? true

            visible: showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                useDefaultVariableAxes: false
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.title
            }

            StyledComboBox {
                id: pageSelector
                Layout.preferredWidth: 320
                buttonIcon: "menu"
                textRole: "displayName"
                model: root.pages
                currentIndex: root.currentPage
                onActivated: index => root.currentPage = index
            }

            RippleButton {
                buttonRadius: Appearance.rounding.full
                implicitWidth: 35
                implicitHeight: 35
                onClicked: root.close()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: 20
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.windowRounding - root.contentPadding

            StandaloneComponentHost {
                anchors.fill: parent
                anchors.margins: 8
                active: Config.ready
                source: root.currentPage >= 0 && root.currentPage < root.pages.length
                    ? Quickshell.shellPath(root.pages[root.currentPage].component)
                    : ""
            }
        }
    }
}
