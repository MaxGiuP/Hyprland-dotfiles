import qs.modules.ii.bar.weather
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (useShortenedForm == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened : (useShortenedForm == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth
    readonly property real groupVerticalInset: 4 + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)

    // Light palettes need more depth than the generated Material surfaces provide.
    // Keep the existing dark-mode colors, but make the bar and its controls clearly
    // distinct from each other when the surrounding palette is bright.
    readonly property color barSurfaceColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colLayer0
        : ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colOnLayer0, 0.95)
    readonly property color controlSurfaceColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colLayer1
        : ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colOnLayer0, 0.88)
    readonly property color controlHoverColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colLayer1Hover
        : ColorUtils.mix(Appearance.colors.colLayer0Base, Appearance.colors.colOnLayer0, 0.80)
    readonly property color controlBorderColor: Appearance.m3colors.darkmode
        ? "transparent"
        : ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.55)


    // NEW: hide media + active window on narrow screens
    readonly property bool hideLeftHeavy: !!screen && screen.width < 1920


    component VerticalBarSeparator: Rectangle {
        Layout.topMargin: Appearance.sizes.baseBarHeight / 3
        Layout.bottomMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillHeight: true
        implicitWidth: 1
        color: Appearance.colors.colOutlineVariant
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && (Config.options.bar.backgroundOpacity ?? 0) < 2 && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        color: {
            if (!Config.options.bar.showBackground) return "transparent"
            const level = Config.options.bar.backgroundOpacity ?? 0
            if (level >= 2) return "transparent"
            if (level === 1) {
                const c = root.barSurfaceColor
                return Qt.rgba(c.r, c.g, c.b, 0.5)
            }
            return root.barSurfaceColor
        }
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.m3colors.darkmode
            ? Appearance.colors.colLayer0Border
            : ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.65)
    }







    FocusedScrollMouseArea { // Left side | scroll to change brightness
        id: barLeftSideMouseArea

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: middleSection.left
        }
        implicitWidth: leftSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness - 0.05)
        onScrollUp: root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness + 0.05)
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.toggleSidebarLeft(root.screen?.name ?? "");
        }

        // Visual content
        ScrollHint {
            reveal: barLeftSideMouseArea.hovered
            icon: "light_mode"
            tooltipText: Translation.tr("Scroll to change brightness")
            side: "left"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: leftSectionRowLayout
            anchors.fill: parent
            spacing: 0

            LeftSidebarButton { // Left sidebar button
                id: leftSidebarButton
                preferredScreen: root.screen?.name ?? ""
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Appearance.rounding.screenRounding
                colBackground: barLeftSideMouseArea.hovered
                    ? root.controlHoverColor
                    : (Appearance.m3colors.darkmode ? ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1) : root.controlSurfaceColor)
                colBackgroundHover: root.controlHoverColor
            }

            BarGroup {
                id: leftCenterGroup2
                Layout.fillHeight: true

                Media {
                    // HIDE on narrow screens
                    visible: !root.hideLeftHeavy && root.useShortenedForm < 2
                    Layout.fillWidth: true
                }
            }

            ActiveWindow {
                shellScreen: root.screen
                Layout.leftMargin: 10 + (leftSidebarButton.visible ? 0 : Appearance.rounding.screenRounding)
                Layout.rightMargin: Appearance.rounding.screenRounding
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.useShortenedForm === 0
            }
        }
    }








    Item { // Middle section
        id: middleSection
        readonly property real groupPadding: 5
        readonly property real contentSpacing: 4
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: centerSectionRow.implicitWidth + groupPadding * 2
        x: (parent?.width ?? 0) / 2 - (centerSectionRow.x + workspacesWidget.x + workspacesWidget.width / 2)

        Rectangle {
            anchors {
                fill: parent
                topMargin: root.groupVerticalInset
                bottomMargin: root.groupVerticalInset
            }
            color: Config.options?.bar.borderless ? "transparent" : root.controlSurfaceColor
            radius: Appearance.rounding.small
            border.width: (!Appearance.m3colors.darkmode && !Config.options?.bar.borderless) ? 1 : 0
            border.color: root.controlBorderColor
        }

        RowLayout {
            id: centerSectionRow
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                right: parent.right
                margins: middleSection.groupPadding
            }
            spacing: middleSection.contentSpacing

            Resources {
                alwaysShowAllResources: root.useShortenedForm === 2
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 6
            }

            Workspaces {
                id: workspacesWidget
                shellScreen: root.screen
                Layout.fillHeight: true
                MouseArea {
                    // Right-click to toggle overview
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton

                    onPressed: event => {
                        if (event.button === Qt.RightButton) {
                            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
                        }
                    }
                }
            }

            UtilButtons {
                visible: (Config.options.bar.verbose && root.useShortenedForm === 0)
                Layout.alignment: Qt.AlignVCenter
            }

            BatteryIndicator {
                visible: (root.useShortenedForm < 2 && Battery.available)
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }







    FocusedScrollMouseArea { // Right side | scroll to change volume
        id: barRightSideMouseArea

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: middleSection.right
            right: parent.right
        }
        implicitWidth: rightSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onScrollClick: Audio.toggleMute()

        onMovedAway: GlobalStates.osdVolumeOpen = false;
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.toggleSidebarRight(root.screen?.name ?? "");
            }
        }

        // Visual content
        ScrollHint {
            reveal: barRightSideMouseArea.hovered
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: rightSectionRowLayout
            anchors.fill: parent
            spacing: 5
            layoutDirection: Qt.RightToLeft

            RippleButton { // Right sidebar button
                id: rightSidebarButton

                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.rightMargin: Appearance.rounding.screenRounding
                Layout.fillWidth: false

                implicitWidth: indicatorsRowLayout.implicitWidth + 10 * 2
                implicitHeight: Math.min(indicatorsRowLayout.implicitHeight + 5 * 2, Appearance.sizes.barHeight)

                buttonRadius: Appearance.rounding.full
                colBackground: barRightSideMouseArea.hovered
                    ? root.controlHoverColor
                    : (Appearance.m3colors.darkmode ? ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1) : root.controlSurfaceColor)
                colBackgroundHover: root.controlHoverColor
                colRipple: Appearance.colors.colLayer1Active
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                toggled: GlobalStates.sidebarRightOpen && GlobalStates.sidebarRightScreen === (root.screen?.name ?? "")
                property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

                Behavior on colText {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                onPressed: {
                    GlobalStates.toggleSidebarRight(root.screen?.name ?? "");
                }

                ConnectionsPopup {
                    hoverTarget: connectivityHoverArea
                }

                RowLayout {
                    id: indicatorsRowLayout
                    anchors.centerIn: parent
                    property real realSpacing: 15
                    spacing: 0



                    Revealer {
                        reveal: Audio.muted
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "volume_off"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }
                    Revealer {
                        reveal: Audio.micMuted
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "mic_off"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }

                    Revealer {
                        reveal: !root.hideLeftHeavy && (Notifications.silent || Notifications.unread > 0)
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
                        implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        NotificationUnreadCount {
                            id: notificationUnreadCount
                        }
                    }
                    Loader {
                        Layout.leftMargin: 4
                        active: Config.options.bar.weather.enable

                        sourceComponent: BarGroup {
                            RowLayout {
                                spacing: 4

                                WeatherBar {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.minimumWidth: implicitWidth
                                    Layout.preferredWidth: implicitWidth
                                }
                                ClockWidget {
                                    showDate: (Config.options.bar.verbose && root.useShortenedForm < 2 && !root.hideLeftHeavy)
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.minimumWidth: implicitWidth
                                    Layout.preferredWidth: implicitWidth
                                }
                            }
                        }
                    }
                    Item {
                        Layout.leftMargin: indicatorsRowLayout.realSpacing
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: connectivityIndicators.implicitWidth
                        implicitHeight: connectivityIndicators.implicitHeight

                        MouseArea {
                            id: connectivityHoverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        RowLayout {
                            id: connectivityIndicators
                            anchors.fill: parent
                            spacing: indicatorsRowLayout.realSpacing

                            MaterialSymbol {
                                visible: BluetoothStatus.available
                                text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                                iconSize: Appearance.font.pixelSize.larger
                                color: rightSidebarButton.colText
                            }

                            MaterialSymbol {
                                text: Network.materialSymbol
                                iconSize: Appearance.font.pixelSize.larger
                                color: rightSidebarButton.colText
                            }
                        }
                    }
                }
            }

            SysTray {
                visible: root.useShortenedForm === 0 && !root.hideLeftHeavy
                Layout.fillWidth: false
                Layout.fillHeight: true
                invertSide: Config?.options.bar.bottom
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

        }
    }

    // Topmost overlay: middle-click anywhere on the bar mutes, same as scroll wheel click.
    // TapHandler (not MouseArea) is used so no cursorShape is set, allowing child items
    // to still display their own pointer cursors.
    Item {
        anchors.fill: parent
        TapHandler {
            acceptedButtons: Qt.MiddleButton
            onTapped: Audio.toggleMute()
        }
    }
}
