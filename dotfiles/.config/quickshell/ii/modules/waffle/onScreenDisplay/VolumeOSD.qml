import QtQuick
import qs.services
import qs.modules.waffle.looks

OSDValue {
    id: root
    iconName: WIcons.volumeIcon
    value: Audio.value

    Connections {
        // Listen to volume changes
        target: Audio
        function onValueChanged() {
            if (Audio.ready)
                root.timer.restart();
        }
        function onMutedChanged() {
            if (Audio.ready)
                root.timer.restart();
        }
    }
}
