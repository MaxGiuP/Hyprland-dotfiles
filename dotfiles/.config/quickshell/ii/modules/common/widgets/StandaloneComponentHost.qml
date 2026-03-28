import QtQuick

Item {
    id: root

    property string source
    property bool active: true
    property Item currentItem: null

    function sourceUrl() {
        if (!root.source) return "";
        if (root.source.startsWith("file:") || root.source.startsWith("qrc:") || root.source.startsWith("qs:")) return root.source;
        if (root.source.startsWith("/")) return `file://${root.source}`;
        return Qt.resolvedUrl(root.source);
    }

    function clearCurrent() {
        if (!root.currentItem) return;
        root.currentItem.destroy();
        root.currentItem = null;
    }

    function instantiate(component, requestedSource) {
        if (!root.active || requestedSource !== root.source) return;
        if (component.status === Component.Loading) return;
        if (component.status === Component.Error) {
            console.error(`[StandaloneComponentHost] Failed to load ${requestedSource}: ${component.errorString()}`);
            return;
        }

        const created = component.createObject(root, {
            x: 0,
            y: 0,
            width: Qt.binding(() => root.width),
            height: Qt.binding(() => root.height)
        });

        if (!created) {
            console.error(`[StandaloneComponentHost] Failed to create ${requestedSource}: ${component.errorString()}`);
            return;
        }

        root.currentItem = created;
    }

    function reload() {
        root.clearCurrent();
        if (!root.active || !root.source) return;

        const requestedSource = root.source;
        const component = Qt.createComponent(root.sourceUrl());
        if (component.status === Component.Loading) {
            component.statusChanged.connect(() => root.instantiate(component, requestedSource));
            return;
        }

        root.instantiate(component, requestedSource);
    }

    onSourceChanged: reload()
    onActiveChanged: reload()
    Component.onCompleted: reload()
    Component.onDestruction: clearCurrent()
}
