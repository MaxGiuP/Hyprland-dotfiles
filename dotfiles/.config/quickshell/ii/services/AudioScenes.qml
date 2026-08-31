pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property var scenes: [
        { id: "desktop", name: "Desktop", icon: "speaker_group", pattern: /combined|speaker|analog/i },
        { id: "headphones", name: "Headphones", icon: "headphones", pattern: /head|usb|dac/i },
        { id: "tv", name: "TV / HDMI", icon: "tv", pattern: /hdmi|displayport|tv|sony/i }
    ]
    property string lastScene: ""
    property string lastError: ""

    function apply(sceneId) {
        const scene = scenes.find(candidate => candidate.id === sceneId);
        if (!scene) return;
        const device = Audio.selectableOutputDevices.find(candidate => {
            const label = `${candidate?.name ?? ""} ${candidate?.description ?? ""} ${candidate?.nickname ?? ""}`;
            return scene.pattern.test(label);
        });
        if (!device) {
            lastError = `No ${scene.name} output is currently available`;
            return;
        }
        lastError = "";
        lastScene = sceneId;
        Audio.setDefaultSink(device);
    }
}
