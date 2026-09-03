import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    property int currentTab: 0
    readonly property var tabs: [
        { name: Translation.tr("Alerts"), icon: "notifications" },
        { name: Translation.tr("History"), icon: "history" },
        { name: Translation.tr("Focus"), icon: "center_focus_strong" }
    ]

    function applySubTab(subTab, sectionId = "") {
        currentTab = Math.max(0, Math.min(Number(subTab), tabs.length - 1))
        contentY = 0
    }

    function formatNotificationTime(timestamp) {
        if (!timestamp)
            return ""
        const date = new Date(timestamp)
        const today = new Date()
        const sameDay = date.getFullYear() === today.getFullYear()
            && date.getMonth() === today.getMonth()
            && date.getDate() === today.getDate()
        return sameDay
            ? Translation.locale.toString(date, "HH:mm")
            : Translation.locale.toString(date, "d MMM, HH:mm")
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentTab
        onCurrentIndexChanged: {
            root.currentTab = currentIndex
            root.contentY = 0
        }

        Repeater {
            model: root.tabs
            delegate: SecondaryTabButton {
                required property var modelData
                buttonIcon: modelData.icon
                buttonText: modelData.name
            }
        }
    }

    Connections {
        target: Notifications
        function onSilentChanged() {
            quietSwitch.checked = Notifications.silent
            focusQuietSwitch.checked = Notifications.silent
        }
    }

    Connections {
        target: Idle
        function onInhibitChanged() {
            focusAwakeSwitch.checked = Idle.inhibit
        }
    }

    ContentSection {
        visible: root.currentTab === 0
        icon: "notifications_active"
        title: Translation.tr("Notification delivery")
        description: Notifications.silent
            ? Translation.tr("Pop-up alerts are currently silenced")
            : Translation.tr("Pop-up alerts are enabled")

        ConfigSwitch {
            id: quietSwitch
            buttonIcon: Notifications.silent ? "notifications_off" : "notifications"
            text: Translation.tr("Do not disturb")
            checked: Notifications.silent
            onClicked: Notifications.silent = quietSwitch.checked
        }

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Default pop-up duration (ms)")
            value: Config.options.notifications.timeout
            from: 0
            to: 60000
            stepSize: 500
            onValueChanged: Config.options.notifications.timeout = value

            StyledToolTip {
                text: Translation.tr("Zero keeps pop-ups visible until they are dismissed. App-provided durations still take priority.")
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "info"
            text: Translation.tr("Do not disturb suppresses shell pop-ups while retaining notifications in history. Applications control their own in-app alerts.")
        }
    }

    ContentSection {
        visible: root.currentTab === 0
        icon: "notification_sound"
        title: Translation.tr("System sounds")
        description: Translation.tr("Uses the freedesktop sound-theme lookup directly")

        MaterialTextField {
            id: soundThemeField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Sound theme")
            text: Config.options.sounds.theme
            onEditingFinished: {
                const value = text.trim()
                if (value.length > 0)
                    Config.options.sounds.theme = value
                else
                    text = Config.options.sounds.theme
            }
        }

        ConfigRow {
            uniform: true

            ConfigSwitch {
                buttonIcon: "battery_android_full"
                text: Translation.tr("Battery event sounds")
                checked: Config.options.sounds.battery
                onCheckedChanged: Config.options.sounds.battery = checked
            }

            ConfigSwitch {
                buttonIcon: "av_timer"
                text: Translation.tr("Pomodoro sounds")
                checked: Config.options.sounds.pomodoro
                onCheckedChanged: Config.options.sounds.pomodoro = checked
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "play_arrow"
            mainText: Translation.tr("Preview notification sound")
            onClicked: Audio.playSystemSound("message-new-instant")
        }
    }

    ContentSection {
        visible: root.currentTab === 1
        icon: "history"
        title: Translation.tr("Notification history")
        description: Translation.tr("%1 saved · %2 unread").arg(Notifications.list.length).arg(Notifications.unread)

        ConfigSpinBox {
            icon: "inventory_2"
            text: Translation.tr("Maximum saved notifications")
            value: Config.options.notifications.maxHistory
            from: 0
            to: 500
            stepSize: 5
            onValueChanged: Config.options.notifications.maxHistory = value

            StyledToolTip {
                text: Translation.tr("Set to zero to stop retaining new notification history.")
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: Notifications.unread > 0
                materialIcon: "done_all"
                mainText: Translation.tr("Mark all read")
                onClicked: Notifications.markAllRead()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                enabled: Notifications.list.length > 0
                materialIcon: "delete_sweep"
                mainText: Translation.tr("Clear history")
                onClicked: Notifications.discardAllNotifications()
            }
        }
    }

    ContentSection {
        visible: root.currentTab === 1 && Notifications.list.length > 0
        icon: "view_list"
        title: Translation.tr("Recent")

        Repeater {
            model: Math.min(Notifications.list.length, 8)

            delegate: Rectangle {
                id: historyCard
                required property int index
                readonly property var notificationItem: Notifications.list[Notifications.list.length - 1 - index]

                Layout.fillWidth: true
                implicitHeight: historyRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: historyRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSecondaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "notifications"
                            iconSize: 21
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: historyCard.notificationItem?.summary
                                || historyCard.notificationItem?.appName
                                || Translation.tr("Notification")
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: historyCard.notificationItem?.body || ""
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideRight
                        }
                    }

                    StyledText {
                        text: root.formatNotificationTime(historyCard.notificationItem?.time)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    RippleButtonWithIcon {
                        Layout.preferredWidth: implicitWidth
                        materialIcon: "close"
                        mainText: ""
                        onClicked: Notifications.discardNotification(historyCard.notificationItem.notificationId)

                        StyledToolTip {
                            text: Translation.tr("Dismiss")
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        visible: root.currentTab === 1 && Notifications.list.length === 0
        icon: "notifications_none"
        title: Translation.tr("No notifications")
        description: Translation.tr("New alerts will appear here when history is enabled.")
    }

    ContentSection {
        visible: root.currentTab === 2
        icon: "center_focus_strong"
        title: Translation.tr("Focus modes")
        description: Translation.tr("Current mode: %1").arg(DesktopModes.currentMode)

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Modes coordinate notifications, desktop chrome, power policy and idle inhibition as one reversible change.")
        }

        ConfigRow {
            preferredColumns: 3
            collapseWidth: 680
            uniform: true

            Repeater {
                model: DesktopModes.modes
                delegate: RippleButtonWithIcon {
                    required property var modelData
                    Layout.fillWidth: true
                    materialIcon: modelData.icon
                    mainText: Translation.tr(modelData.name)
                    toggled: DesktopModes.currentMode === modelData.id
                    onClicked: DesktopModes.apply(modelData.id)

                    StyledToolTip {
                        text: Translation.tr(modelData.detail)
                    }
                }
            }
        }
    }

    ContentSection {
        visible: root.currentTab === 2
        icon: "tune"
        title: Translation.tr("Focus controls")

        ConfigRow {
            uniform: true

            ConfigSwitch {
                id: focusQuietSwitch
                buttonIcon: Notifications.silent ? "notifications_off" : "notifications"
                text: Translation.tr("Silence pop-ups")
                checked: Notifications.silent
                onClicked: Notifications.silent = focusQuietSwitch.checked
            }

            ConfigSwitch {
                id: focusAwakeSwitch
                buttonIcon: Idle.inhibit ? "bedtime_off" : "bedtime"
                text: Translation.tr("Keep display awake")
                checked: Idle.inhibit
                onClicked: Idle.toggleInhibit(focusAwakeSwitch.checked)
            }
        }
    }
}
