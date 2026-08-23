import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    readonly property int badgeHeight: 14
    readonly property int badgeHorizontalPadding: 4
    readonly property int badgeOverlap: showUnreadCount ? 5 : 4
    readonly property string badgeTextValue: Notifications.unread > 999 ? "999+" : String(Notifications.unread)

    // Include the complete badge in this item's layout bounds. This prevents the
    // surrounding Revealer from clipping it while leaving the bell visible.
    implicitWidth: notificationIcon.implicitWidth
        + (notifPing.visible ? Math.max(0, notifPing.implicitWidth - badgeOverlap) : 0)
    implicitHeight: Math.max(notificationIcon.implicitHeight, notifPing.visible ? notifPing.implicitHeight : 0) + 4

    MaterialSymbol {
        id: notificationIcon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: Notifications.silent ? "notifications_paused" : "notifications"
        iconSize: Appearance.font.pixelSize.larger
        color: rightSidebarButton.colText
    }

    Rectangle {
        id: notifPing
        visible: !Notifications.silent && Notifications.unread > 0
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: root.showUnreadCount ? -4 : 0
        }
        radius: Appearance.rounding.full
        color: Appearance.m3colors.darkmode ? "#FFFFFF" : Appearance.colors.colPrimary
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
            color: Appearance.m3colors.darkmode ? "#000000" : Appearance.colors.colOnPrimary
            text: root.badgeTextValue
        }
    }
}
