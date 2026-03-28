import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FocusScope {
    id: root
    focus: true
    activeFocusOnTab: true

    property string homeUrl: "https://duckduckgo.com/html/?q=quickshell"
    property var history: []
    property int historyIndex: -1
    property string currentUrl: ""
    property string pageText: "<p>Open a page or search the web.</p>"
    property bool loading: false

    function normalizeUrl(value) {
        const text = (value || "").trim();
        if (text.length === 0) return root.homeUrl;
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(text)) return text;
        if (text.includes(" ") || !text.includes(".")) {
            return `https://duckduckgo.com/html/?q=${encodeURIComponent(text)}`;
        }
        return `https://${text}`;
    }

    function navigate(value, pushHistory = true) {
        const target = root.normalizeUrl(value);
        root.currentUrl = target;
        addressField.text = target;
        root.loading = true;
        root.pageText = `<p>Loading ${StringUtils.escapeHtml(target)}...</p>`;

        if (pushHistory) {
            const nextHistory = root.history.slice(0, root.historyIndex + 1);
            nextHistory.push(target);
            root.history = nextHistory;
            root.historyIndex = nextHistory.length - 1;
        }

        fetchProc.command = [
            "python3",
            Quickshell.shellPath("scripts/browser/fetch_page.py"),
            target
        ];
        fetchProc.running = true;
    }

    function goBack() {
        if (root.historyIndex <= 0) return;
        root.historyIndex -= 1;
        root.navigate(root.history[root.historyIndex], false);
    }

    function goForward() {
        if (root.historyIndex >= root.history.length - 1) return;
        root.historyIndex += 1;
        root.navigate(root.history[root.historyIndex], false);
    }

    Component.onCompleted: navigate(root.homeUrl)

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Repeater {
                    model: [
                        { icon: "arrow_back", enabled: root.historyIndex > 0, action: () => root.goBack(), tooltip: Translation.tr("Back") },
                        { icon: "arrow_forward", enabled: root.historyIndex >= 0 && root.historyIndex < root.history.length - 1, action: () => root.goForward(), tooltip: "Forward" },
                        { icon: "refresh", enabled: root.currentUrl.length > 0, action: () => root.navigate(root.currentUrl, false), tooltip: "Reload" },
                        { icon: "open_in_new", enabled: root.currentUrl.length > 0, action: () => Quickshell.execDetached(["xdg-open", root.currentUrl]), tooltip: "Open externally" }
                    ]

                    delegate: RippleButton {
                        required property var modelData
                        property var buttonModel: modelData
                        implicitWidth: 30
                        implicitHeight: 30
                        enabled: buttonModel.enabled
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        onClicked: buttonModel.action()

                        contentItem: MaterialSymbol {
                            text: buttonModel.icon
                            iconSize: 18
                            color: Appearance.colors.colOnLayer3
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        StyledToolTip {
                            text: buttonModel.tooltip
                        }
                    }
                }

                TextField {
                    id: addressField
                    Layout.fillWidth: true
                    background: null
                    color: Appearance.colors.colOnLayer2
                    placeholderText: "Search or enter address"
                    placeholderTextColor: Appearance.colors.colSubtext
                    selectByMouse: true
                    text: root.currentUrl

                    font.family: Appearance.font.family.monospace
                    font.variableAxes: Appearance.font.variableAxes.monospace
                    font.pixelSize: Appearance.font.pixelSize.small

                    onAccepted: root.navigate(text)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colLayer2Hover
            clip: true

            StyledFlickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 10
                contentWidth: width
                contentHeight: pageLabel.implicitHeight
                clip: true

                Text {
                    id: pageLabel
                    width: flick.width
                    text: root.pageText
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    font.family: Appearance.font.family.monospace
                    font.variableAxes: Appearance.font.variableAxes.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                    linkColor: Appearance.colors.colPrimary

                    onLinkActivated: link => root.navigate(link)
                }
            }
        }
    }

    Process {
        id: fetchProc

        stdout: StdioCollector {
            id: fetchOut
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: fetchErr
            waitForEnd: true
        }

        onExited: exitCode => {
            root.loading = false;
            if (exitCode === 0 && fetchOut.text.trim().length > 0) {
                root.pageText = fetchOut.text.trim();
            } else {
                root.pageText = `<h3>Failed to load</h3><p>${StringUtils.escapeHtml(root.currentUrl)}</p><p>${StringUtils.escapeHtml(fetchErr.text.trim() || "Unknown error")}</p>`;
            }
            flick.contentY = 0;
        }
    }
}
