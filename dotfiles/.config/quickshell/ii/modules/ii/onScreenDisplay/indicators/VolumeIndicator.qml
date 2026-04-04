import qs.services
import QtQuick
import qs.modules.ii.onScreenDisplay

OsdValueIndicator {
    id: osdValues
    value: Audio.value
    icon: Audio.muted ? "volume_off" : "volume_up"
    name: Translation.tr("Volume")
}
