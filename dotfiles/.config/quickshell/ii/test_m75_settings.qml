import QtQuick
import Quickshell
import qs.modules.settings
import qs.services

ShellRoot {
    PeripheralsConfig {}

    Timer {
        interval: 1000
        running: true
        onTriggered: {
            console.info(`M75_SETTINGS_COMPONENT_OK connected=${MechlandsM75.connected} features=${MechlandsM75.features.length}`);
            Qt.quit();
        }
    }
}
