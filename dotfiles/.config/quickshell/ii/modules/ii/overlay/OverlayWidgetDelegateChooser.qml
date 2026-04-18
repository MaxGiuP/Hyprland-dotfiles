pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.modules.ii.overlay.crosshair
import qs.modules.ii.overlay.volumeMixer
import qs.modules.ii.overlay.floatingImage
import qs.modules.ii.overlay.fpsLimiter
import qs.modules.ii.overlay.recorder
import qs.modules.ii.overlay.resources
import qs.modules.ii.overlay.notes
import qs.modules.ii.overlay.liveCaptions
import qs.modules.ii.overlay.liveCaptionsTranslation
import qs.modules.ii.overlay.liveScreenTranslation
import qs.modules.ii.overlay.liveScreenTranslationOutput
import qs.modules.ii.overlay.liveCaptionsSettings
import qs.modules.ii.overlay.settingsMenu
import qs.modules.ii.overlay.terminal

DelegateChooser {
    id: root
    role: "identifier"

    DelegateChoice { roleValue: "crosshair"; Crosshair {} }
    DelegateChoice { roleValue: "floatingImage"; FloatingImage {} }
    DelegateChoice { roleValue: "fpsLimiter"; FpsLimiter {} }
    DelegateChoice { roleValue: "recorder"; Recorder {} }
    DelegateChoice { roleValue: "resources"; Resources {} }
    DelegateChoice { roleValue: "notes"; Notes {} }
    DelegateChoice { roleValue: "volumeMixer"; VolumeMixer {} }
    DelegateChoice { roleValue: "liveCaptions"; LiveCaptionsOverlay {} }
    DelegateChoice { roleValue: "liveCaptionsTranslation"; LiveCaptionsTranslationOverlay {} }
    DelegateChoice { roleValue: "liveScreenTranslation"; LiveScreenTranslationOverlay {} }
    DelegateChoice { roleValue: "liveScreenTranslationOutput"; LiveScreenTranslationOutputOverlay {} }
    DelegateChoice { roleValue: "liveCaptionsSettings"; LiveCaptionsSettings {} }
    DelegateChoice { roleValue: "settingsMenu"; SettingsMenu {} }
    DelegateChoice { roleValue: "terminal"; Terminal {} }
}
