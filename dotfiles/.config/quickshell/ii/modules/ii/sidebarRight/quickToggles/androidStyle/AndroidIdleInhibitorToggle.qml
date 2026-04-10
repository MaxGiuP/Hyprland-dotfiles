import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

AndroidQuickToggleButton {
    signal openIdleLockDialog()

    toggleModel: IdleInhibitorToggle {}

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        enabled: !parent.editMode
        onClicked: openIdleLockDialog()
    }
}
