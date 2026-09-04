pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.services
import qs.modules.ii.overlay
import qs.modules.ii.sidebarLeft as SidebarLeft

StyledOverlayWidget {
    id: root

    title: Translation.tr("Calculator")
    showCenterButton: true
    minimumWidth: 440
    minimumHeight: 620

    function focusCalculator() {
        calculator.forceActiveFocus()
    }

    Component.onCompleted: {
        if (GlobalStates.overlayOpen)
            Qt.callLater(root.focusCalculator)
    }

    contentItem: OverlayBackground {
        radius: root.contentRadius

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: Qt.callLater(root.focusCalculator)
        }

        SidebarLeft.Calculator {
            id: calculator
            anchors.fill: parent
            autoFocusOnCompleted: false
            clearOnEscape: false
        }
    }
}
