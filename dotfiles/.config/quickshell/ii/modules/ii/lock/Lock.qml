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
    readonly property int unlockAnimationDurationMs: 1250
    readonly property int unlockBlurTailDurationMs: 160
    readonly property int unlockBlurOutStartDelayMs: Math.max(0, unlockAnimationDurationMs - unlockBlurTailDurationMs)

    unlockReleaseDelayMs: unlockAnimationDurationMs
    lockBlurInDelayMs: 0
    lockBlurInDurationMs: lockBlurLeadInMs
    unlockBlurOutDelayMs: unlockBlurOutStartDelayMs
    unlockBlurOutDurationMs: unlockBlurTailDurationMs

    lockSurface: LockSurface {
        context: root.context
        lockpadRiseDurationMs: root.lockpadRiseDurationMs
        introStartDelayMs: root.lockBlurInDelayMs + root.lockBlurInDurationMs
        playUnlockAnimation: true
    }
}
