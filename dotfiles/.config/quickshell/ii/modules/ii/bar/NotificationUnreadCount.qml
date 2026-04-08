import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MaterialSymbol {
    id: root
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    readonly property int badgeHeight: 14
    readonly property int badgeHorizontalPadding: 4
    readonly property string badgeTextValue: Notifications.unread > 999 ? "999+" : String(Notifications.unread)
    text: Notifications.silent ? "notifications_paused" : "notifications"
    iconSize: Appearance.font.pixelSize.larger
    color: rightSidebarButton.colText

    Rectangle {
        id: notifPing
        visible: !Notifications.silent && Notifications.unread > 0
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1
            topMargin: root.showUnreadCount ? 0 : 3
        }
        radius: Appearance.rounding.full
        color: "#FFFFFF"
        z: 1

        implicitHeight: root.showUnreadCount ? root.badgeHeight : 8
        implicitWidth: root.showUnreadCount
            ? Math.max(implicitHeight, notificationCounterText.implicitWidth + root.badgeHorizontalPadding * 2)
            : implicitHeight
        width: implicitWidth
        height: implicitHeight

        StyledText {
            id: notificationCounterText
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: "#000000"
            text: root.badgeTextValue
        }
    }
}
