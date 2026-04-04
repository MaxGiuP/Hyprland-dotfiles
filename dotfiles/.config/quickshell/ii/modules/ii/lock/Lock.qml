pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland

LockScreen {
    id: root
    readonly property int lockpadRiseDurationMs: 650
    readonly property int lockBlurLeadInMs: 180

    unlockReleaseDelayMs: 1250
    lockBlurInDelayMs: 0
    lockBlurInDurationMs: lockBlurLeadInMs
    unlockBlurOutDelayMs: 700
    unlockBlurOutDurationMs: 500

    lockSurface: LockSurface {
        context: root.context
        lockpadRiseDurationMs: root.lockpadRiseDurationMs
        introStartDelayMs: root.lockBlurInDelayMs + root.lockBlurInDurationMs
    }
}
