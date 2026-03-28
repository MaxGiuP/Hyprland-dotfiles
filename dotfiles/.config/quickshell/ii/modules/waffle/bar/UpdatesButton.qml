import QtQuick
import Quickshell
import qs
import qs.services as Services
import qs.modules.common
import qs.modules.waffle.looks
import qs.modules.waffle.bar.tray

BarIconButton {
    id: root

    visible: Services.Updates.updateAdvised || Services.Updates.updateStronglyAdvised
    padding: 4
    iconName: "arrow-sync"
    iconSize: 20 // Needed because the icon appears to have some padding
    iconMonochrome: true
    tooltipText: Translation.tr("Get the latest features and security improvements with\nthe newest feature update.\n\n%1 packages").arg(Services.Updates.count)

    onClicked: {
        Quickshell.execDetached(["bash", "-c", Config.options.apps.update]);
    }

    overlayingItems: Item {
        id: badge
        property int displayCount: Services.Updates.count >= 0 ? Services.Updates.count : 0
        visible: displayCount > 0
        z: 1000
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: -4
            topMargin: -4
        }

        property int badgeH: 13
        property string badgeTextValue: displayCount > 999 ? "999+" : String(displayCount)

        width: Math.max(badgeH, badgeText.implicitWidth + 7)
        height: badgeH

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            antialiasing: true
            color: displayCount > 0 ? "white" : Looks.colors.bg2
            border.width: 1
            border.color: Looks.colors.bg2Border
        }

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: badge.badgeTextValue
            font.pixelSize: 9
            font.weight: Font.DemiBold
            color: displayCount > 0 ? "black" : Looks.colors.fg1
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
