import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 860

    property bool ready: false
    property bool initialRefreshStarted: false
    property int sectionLoadingStep: 0
    readonly property bool sectionsReady: styleHubLoader.status === Loader.Ready
        && personalisationLoader.status === Loader.Ready
        && shellAppearanceLoader.status === Loader.Ready
        && gtkLoader.status === Loader.Ready
        && gnomeLoader.status === Loader.Ready
        && kdeLoader.status === Loader.Ready
        && kdeStoreLoader.status === Loader.Ready

    function finishInitialLoadWhenSettled() {
        if (root.initialRefreshStarted && root.sectionsReady && !DesktopThemeSettings.scanning)
            readyTimer.restart()
    }

    function copyGtk4DraftToGnome(values) {
        if (gnomeLoader.item && typeof gnomeLoader.item.setGtkDraft === "function")
            gnomeLoader.item.setGtkDraft(values)
    }

    Component.onCompleted: {
        root.initialRefreshStarted = true
        DesktopThemeSettings.refreshAll()
        Qt.callLater(() => root.sectionLoadingStep = 1)
        root.finishInitialLoadWhenSettled()
    }

    Connections {
        target: DesktopThemeSettings
        function onScanningChanged() { root.finishInitialLoadWhenSettled() }
    }

    onSectionsReadyChanged: root.finishInitialLoadWhenSettled()

    Timer {
        id: readyTimer
        interval: 0
        repeat: false
        onTriggered: Qt.callLater(() => root.ready = true)
    }

    Timer {
        id: nextSectionTimer
        interval: 0
        repeat: false
        onTriggered: root.sectionLoadingStep += 1
    }

    Loader {
        id: styleHubLoader
        Layout.fillWidth: true
        active: root.sectionLoadingStep >= 1
        asynchronous: false
        source: "DesktopThemeStyleHubSection.qml"
        onLoaded: if (root.sectionLoadingStep === 1) nextSectionTimer.restart()
    }

    Loader {
        id: personalisationLoader
        Layout.fillWidth: true
        active: root.sectionLoadingStep >= 2
        asynchronous: false
        source: "DesktopThemePersonalisationSection.qml"
        onLoaded: if (root.sectionLoadingStep === 2) nextSectionTimer.restart()
    }

    Loader {
        id: shellAppearanceLoader
        Layout.fillWidth: true
        active: root.sectionLoadingStep >= 3
        asynchronous: false
        source: "DesktopThemeShellAppearanceSection.qml"
        onLoaded: if (root.sectionLoadingStep === 3) nextSectionTimer.restart()
    }

    Loader {
        id: gtkLoader
        Layout.fillWidth: true
        active: root.sectionLoadingStep >= 4
        asynchronous: false
        source: "DesktopThemeGtkSection.qml"
        onLoaded: {
            item.settingsHost = root
            if (root.sectionLoadingStep === 4)
                nextSectionTimer.restart()
        }
    }

    Loader {
        id: gnomeLoader
        Layout.fillWidth: true
        active: root.sectionLoadingStep >= 5
        asynchronous: false
        source: "DesktopThemeGnomeSection.qml"
        onLoaded: if (root.sectionLoadingStep === 5) nextSectionTimer.restart()
    }

    Loader {
        id: kdeLoader
        Layout.fillWidth: true
        active: root.sectionLoadingStep >= 6
        asynchronous: false
        source: "DesktopThemeKdeSection.qml"
        onLoaded: if (root.sectionLoadingStep === 6) nextSectionTimer.restart()
    }

    Loader {
        id: kdeStoreLoader
        Layout.fillWidth: true
        active: root.sectionLoadingStep >= 7
        asynchronous: false
        source: "DesktopThemeStoreSection.qml"
    }
}
