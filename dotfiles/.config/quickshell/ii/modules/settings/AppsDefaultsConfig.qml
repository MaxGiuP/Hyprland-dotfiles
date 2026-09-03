import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760

    property int currentTab: 0
    property var defaults: ({})
    property var pendingDefaults: ({})
    property var installedDesktopIds: []
    property var pendingDesktopIds: []
    property var startupServices: []
    property var pendingStartupServices: []
    property var autostartEntries: []
    property var pendingAutostartEntries: []
    property bool defaultsLoading: false
    property bool startupLoading: false
    property string defaultStatus: ""
    property string startupStatus: ""

    readonly property var tabs: [
        { name: Translation.tr("Defaults"), icon: "apps" },
        { name: Translation.tr("Startup"), icon: "rocket_launch" }
    ]

    readonly property var defaultKinds: [
        {
            key: "web",
            title: Translation.tr("Web links"),
            icon: "language",
            mime: "x-scheme-handler/https",
            candidates: [
                { id: "brave-browser.desktop", name: "Brave" },
                { id: "firefox.desktop", name: "Firefox" },
                { id: "chromium.desktop", name: "Chromium" },
                { id: "google-chrome.desktop", name: "Google Chrome" },
                { id: "com.google.Chrome.desktop", name: "Google Chrome" }
            ]
        },
        {
            key: "mail",
            title: Translation.tr("Email links"),
            icon: "mail",
            mime: "x-scheme-handler/mailto",
            candidates: [
                { id: "io.github.MaxGiuP.QuickMail.desktop", name: "QuickMail" },
                { id: "thunderbird.desktop", name: "Thunderbird" },
                { id: "org.mozilla.Thunderbird.desktop", name: "Thunderbird" },
                { id: "org.gnome.Geary.desktop", name: "Geary" }
            ]
        },
        {
            key: "files",
            title: Translation.tr("Folders"),
            icon: "folder",
            mime: "inode/directory",
            candidates: [
                { id: "org.kde.dolphin.desktop", name: "Dolphin" },
                { id: "org.gnome.Nautilus.desktop", name: "Files" },
                { id: "thunar.desktop", name: "Thunar" },
                { id: "pcmanfm-qt.desktop", name: "PCManFM-Qt" },
                { id: "pcmanfm.desktop", name: "PCManFM" }
            ]
        },
        {
            key: "pdf",
            title: Translation.tr("PDF documents"),
            icon: "picture_as_pdf",
            mime: "application/pdf",
            candidates: [
                { id: "org.gnome.Evince.desktop", name: "Document Viewer" },
                { id: "org.kde.okular.desktop", name: "Okular" },
                { id: "org.pwmt.zathura.desktop", name: "Zathura" }
            ]
        },
        {
            key: "images",
            title: Translation.tr("Images"),
            icon: "image",
            mime: "image/png",
            candidates: [
                { id: "imv.desktop", name: "imv" },
                { id: "org.gnome.Loupe.desktop", name: "Image Viewer" },
                { id: "org.kde.gwenview.desktop", name: "Gwenview" }
            ]
        },
        {
            key: "video",
            title: Translation.tr("Video"),
            icon: "movie",
            mime: "video/mp4",
            candidates: [
                { id: "mpv.desktop", name: "mpv" },
                { id: "vlc.desktop", name: "VLC" },
                { id: "org.kde.haruna.desktop", name: "Haruna" }
            ]
        }
    ]

    function applySubTab(subTab, sectionId = "") {
        currentTab = Math.max(0, Math.min(Number(subTab), tabs.length - 1))
        contentY = 0
    }

    function refreshDefaults() {
        defaultsReadProc.running = false
        defaultsReadProc.running = true
    }

    function refreshStartup() {
        startupReadProc.running = false
        startupReadProc.running = true
    }

    function desktopLabel(desktopId) {
        return String(desktopId || "")
            .replace(/\.desktop$/i, "")
            .replace(/^org\.(kde|gnome|mozilla)\./i, "")
            .replace(/^io\.github\.[^.]+\./i, "")
            .replace(/[._-]+/g, " ")
    }

    function choicesFor(entry) {
        const choices = entry.candidates.filter(candidate => installedDesktopIds.indexOf(candidate.id) >= 0)
        const current = defaults[entry.key] || ""
        if (current.length > 0 && !choices.some(candidate => candidate.id === current))
            choices.unshift({ id: current, name: desktopLabel(current), currentOnly: true })
        return choices
    }

    function setDefault(entry, desktopId) {
        const current = defaults[entry.key] || ""
        if (desktopId === current)
            return
        const allowed = entry.candidates.some(candidate => candidate.id === desktopId)
            && installedDesktopIds.indexOf(desktopId) >= 0
        if (!allowed || defaultWriteProc.running)
            return

        defaultStatus = Translation.tr("Setting %1…").arg(entry.title)
        defaultWriteProc.categoryTitle = entry.title
        defaultWriteProc.desktopId = desktopId
        defaultWriteProc.mimeType = entry.mime
        defaultWriteProc.running = true
    }

    Component.onCompleted: {
        refreshDefaults()
        refreshStartup()
    }

    Process {
        id: defaultsReadProc
        command: ["bash", "-lc",
            "printf 'default\\tweb\\t%s\\n' \"$(xdg-mime query default x-scheme-handler/https 2>/dev/null)\"; " +
            "printf 'default\\tmail\\t%s\\n' \"$(xdg-mime query default x-scheme-handler/mailto 2>/dev/null)\"; " +
            "printf 'default\\tfiles\\t%s\\n' \"$(xdg-mime query default inode/directory 2>/dev/null)\"; " +
            "printf 'default\\tpdf\\t%s\\n' \"$(xdg-mime query default application/pdf 2>/dev/null)\"; " +
            "printf 'default\\timages\\t%s\\n' \"$(xdg-mime query default image/png 2>/dev/null)\"; " +
            "printf 'default\\tvideo\\t%s\\n' \"$(xdg-mime query default video/mp4 2>/dev/null)\"; " +
            "for directory in /usr/share/applications \"$HOME/.local/share/applications\"; do " +
            "  [ -d \"$directory\" ] || continue; " +
            "  find \"$directory\" -maxdepth 1 -type f -name '*.desktop' -printf 'desktop\\t%s\\n'; " +
            "done"
        ]

        onRunningChanged: {
            if (running) {
                root.defaultsLoading = true
                root.pendingDefaults = ({})
                root.pendingDesktopIds = []
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const fields = line.split("\t")
                if (fields[0] === "default" && fields.length >= 3) {
                    const nextDefaults = Object.assign({}, root.pendingDefaults)
                    nextDefaults[fields[1]] = fields.slice(2).join("\t").trim()
                    root.pendingDefaults = nextDefaults
                } else if (fields[0] === "desktop" && fields[1]) {
                    const id = fields[1].trim()
                    if (id.length > 0 && root.pendingDesktopIds.indexOf(id) < 0)
                        root.pendingDesktopIds = root.pendingDesktopIds.concat([id])
                }
            }
        }

        onExited: exitCode => {
            root.defaults = root.pendingDefaults
            root.installedDesktopIds = root.pendingDesktopIds.sort()
            root.defaultsLoading = false
            if (exitCode !== 0)
                root.defaultStatus = Translation.tr("XDG default-app service is unavailable.")
        }
    }

    Process {
        id: defaultWriteProc
        property string categoryTitle: ""
        property string desktopId: ""
        property string mimeType: ""
        command: ["xdg-mime", "default", desktopId, mimeType]

        onExited: exitCode => {
            if (exitCode === 0) {
                root.defaultStatus = Translation.tr("%1 updated.").arg(categoryTitle)
                root.refreshDefaults()
            } else {
                root.defaultStatus = Translation.tr("Could not update %1.").arg(categoryTitle)
            }
        }
    }

    Process {
        id: startupReadProc
        command: ["bash", "-lc",
            "if command -v systemctl >/dev/null 2>&1; then " +
            "  systemctl --user --no-pager --plain list-unit-files --type=service --state=enabled --legend=no 2>/dev/null " +
            "    | awk 'NF >= 2 { printf \"service\\t%s\\t%s\\n\", $1, $2 }'; " +
            "fi; " +
            "if [ -d \"$HOME/.config/autostart\" ]; then " +
            "  find \"$HOME/.config/autostart\" -maxdepth 1 -type f -name '*.desktop' -printf 'autostart\\t%f\\n'; " +
            "fi"
        ]

        onRunningChanged: {
            if (running) {
                root.startupLoading = true
                root.pendingStartupServices = []
                root.pendingAutostartEntries = []
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const fields = line.split("\t")
                if (fields[0] === "service" && fields[1]) {
                    root.pendingStartupServices = root.pendingStartupServices.concat([{
                        unit: fields[1].trim(),
                        state: fields[2]?.trim() || Translation.tr("enabled")
                    }])
                } else if (fields[0] === "autostart" && fields[1]) {
                    root.pendingAutostartEntries = root.pendingAutostartEntries.concat([fields[1].trim()])
                }
            }
        }

        onExited: exitCode => {
            root.startupServices = root.pendingStartupServices
            root.autostartEntries = root.pendingAutostartEntries
            root.startupLoading = false
            root.startupStatus = exitCode === 0
                ? ""
                : Translation.tr("User startup information is unavailable.")
        }
    }

    component DefaultCard: Rectangle {
        id: defaultCard
        required property var entry
        readonly property var choices: root.choicesFor(entry)
        readonly property string currentDesktop: root.defaults[entry.key] || ""

        Layout.fillWidth: true
        Layout.preferredWidth: 350
        implicitHeight: cardContent.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: defaultCard.entry.icon
                    iconSize: 21
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: defaultCard.entry.title
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Medium
                }
            }

            StyledComboBox {
                Layout.fillWidth: true
                enabled: defaultCard.choices.length > 0 && !defaultWriteProc.running
                textRole: "name"
                model: defaultCard.choices
                currentIndex: Math.max(0, defaultCard.choices.findIndex(choice => choice.id === defaultCard.currentDesktop))
                onActivated: index => root.setDefault(defaultCard.entry, defaultCard.choices[index].id)
            }

            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideMiddle
                text: defaultCard.currentDesktop.length > 0
                    ? defaultCard.currentDesktop
                    : Translation.tr("No default is registered")
            }
        }
    }

    component StartupRow: Rectangle {
        id: startupRow
        property string iconName: "settings"
        property string title: ""
        property string detail: ""

        Layout.fillWidth: true
        implicitHeight: startupContent.implicitHeight + 18
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        RowLayout {
            id: startupContent
            anchors.fill: parent
            anchors.margins: 9
            spacing: 10

            MaterialSymbol {
                text: startupRow.iconName
                iconSize: 20
                color: Appearance.colors.colOnLayer1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: startupRow.title
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideMiddle
                }

                StyledText {
                    Layout.fillWidth: true
                    text: startupRow.detail
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentTab
        onCurrentIndexChanged: {
            root.currentTab = currentIndex
            root.contentY = 0
        }

        Repeater {
            model: root.tabs
            delegate: SecondaryTabButton {
                required property var modelData
                buttonIcon: modelData.icon
                buttonText: modelData.name
            }
        }
    }

    ContentSection {
        visible: root.currentTab === 0
        icon: "apps"
        title: Translation.tr("Default applications")
        description: Translation.tr("Uses the cross-desktop XDG MIME database")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "verified_user"
            text: Translation.tr("Only installed applications are offered. Changes are written through xdg-mime to your user MIME configuration; no KDE or GNOME settings service is involved.")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width >= 700 ? 2 : 1
            columnSpacing: 8
            rowSpacing: 8
            uniformCellWidths: true

            Repeater {
                model: root.defaultKinds
                delegate: DefaultCard {
                    required property var modelData
                    entry: modelData
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.defaultsLoading || root.defaultStatus.length > 0
            text: root.defaultsLoading ? Translation.tr("Reading XDG defaults…") : root.defaultStatus
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            enabled: !root.defaultsLoading && !defaultWriteProc.running
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh defaults")
            onClicked: root.refreshDefaults()
        }
    }

    ContentSection {
        visible: root.currentTab === 1
        icon: "manufacturing"
        title: Translation.tr("User services")
        description: Translation.tr("%1 enabled systemd services").arg(root.startupServices.length)

        Repeater {
            model: root.startupServices
            delegate: StartupRow {
                required property var modelData
                iconName: "settings_suggest"
                title: modelData.unit
                detail: modelData.state
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.startupLoading && root.startupServices.length === 0
            text: Translation.tr("No enabled user services were reported.")
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        visible: root.currentTab === 1
        icon: "rocket_launch"
        title: Translation.tr("XDG autostart")
        description: Translation.tr("%1 desktop entries").arg(root.autostartEntries.length)

        Repeater {
            model: root.autostartEntries
            delegate: StartupRow {
                required property string modelData
                iconName: "desktop_windows"
                title: root.desktopLabel(modelData)
                detail: modelData
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.startupLoading && root.autostartEntries.length === 0
            text: Translation.tr("No per-user XDG autostart entries were found.")
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.startupLoading || root.startupStatus.length > 0
            text: root.startupLoading ? Translation.tr("Reading startup entries…") : root.startupStatus
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            enabled: !root.startupLoading
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh startup list")
            onClicked: root.refreshStartup()
        }
    }
}
