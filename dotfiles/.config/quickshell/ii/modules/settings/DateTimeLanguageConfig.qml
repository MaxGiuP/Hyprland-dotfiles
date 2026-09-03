import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    property int currentSubTab: 0
    readonly property var tabs: [
        { name: Translation.tr("Date & time"), icon: "schedule" },
        { name: Translation.tr("Language & region"), icon: "language" },
        { name: Translation.tr("Translation"), icon: "translate" }
    ]

    function applySubTab(subTab, sectionId = "") {
        root.currentSubTab = Math.max(0, Math.min(subTab, root.tabs.length - 1))
        root.contentY = 0
    }

    property var englishTranslations: ({})
    property var targetTranslations: ({})
    property string rawTargetJson: "{}"
    property string sysLocale: ""
    property string sysLangStatus: ""
    property bool nativeTimeActionPending: false
    property bool nativeTimeActionError: false
    property string nativeTimeActionStatus: ""
    readonly property var nativeTime: NativeSettings.snapshot?.native?.time ?? ({})
    readonly property bool nativeTimeAvailable: root.nativeTime.available === true
    readonly property string nativeTimezone: root.nativeTime.timezone
        ?? NativeSettings.snapshot?.time?.timezone
        ?? ""
    readonly property bool nativeCanNtp: root.nativeTime.can_ntp === true
    readonly property bool nativeNtpEnabled: root.nativeTime.ntp === true
    readonly property bool nativeNtpSynchronized: root.nativeTime.ntp_synchronized === true
    onRawTargetJsonChanged: {
        if (!rawJsonEditor.activeFocus)
            rawJsonEditor.text = rawTargetJson
    }

    function selectedLocaleCode() {
        const raw = localeInput.text.trim()
        if (!raw.length || raw === "auto")
            return Qt.locale().name
        return raw
    }

    function targetTranslationPath() {
        return `${Translation.translationsDir}/${selectedLocaleCode()}.json`
    }

    function parseJson(text, fallback) {
        try {
            return JSON.parse(text)
        } catch (error) {
            return fallback
        }
    }

    function prettyJson(value) {
        return JSON.stringify(value, null, 2)
    }

    function timezoneValidationMessage(value) {
        const timezone = String(value ?? "")
        if (!timezone.length)
            return Translation.tr("Enter an IANA time zone, for example Europe/London.")
        if (timezone.length > 255 || timezone.startsWith("/"))
            return Translation.tr("Use a relative IANA time-zone name.")
        const parts = timezone.split("/")
        if (parts.some(part => !part.length || part === "." || part === ".."
                || !/^[A-Za-z0-9_+.-]+$/.test(part)))
            return Translation.tr("Use a valid IANA time-zone name.")
        return ""
    }

    function setNetworkTime(enabled) {
        if (root.nativeTimeActionPending)
            return
        root.nativeTimeActionPending = true
        root.nativeTimeActionError = false
        root.nativeTimeActionStatus = enabled
            ? Translation.tr("Enabling network time…")
            : Translation.tr("Disabling network time…")
        NativeSettings.request("time.set_ntp", { enabled: enabled }, (result, error) => {
            root.nativeTimeActionPending = false
            if (error) {
                root.nativeTimeActionError = true
                root.nativeTimeActionStatus = Translation.tr("Network time could not be changed: %1")
                    .arg(error.message ?? Translation.tr("Unknown error"))
                NativeSettings.refresh()
                return
            }
            root.nativeTimeActionError = false
            root.nativeTimeActionStatus = enabled
                ? Translation.tr("Network time enabled.")
                : Translation.tr("Network time disabled.")
            NativeSettings.refresh()
        })
    }

    function setTimezone() {
        const timezone = timezoneInput.text.trim()
        const validationError = root.timezoneValidationMessage(timezone)
        if (root.nativeTimeActionPending || validationError.length > 0) {
            if (validationError.length > 0) {
                root.nativeTimeActionError = true
                root.nativeTimeActionStatus = validationError
            }
            return
        }
        root.nativeTimeActionPending = true
        root.nativeTimeActionError = false
        root.nativeTimeActionStatus = Translation.tr("Changing time zone…")
        NativeSettings.request("time.set_timezone", { timezone: timezone }, (result, error) => {
            root.nativeTimeActionPending = false
            if (error) {
                root.nativeTimeActionError = true
                root.nativeTimeActionStatus = Translation.tr("Time zone could not be changed: %1")
                    .arg(error.message ?? Translation.tr("Unknown error"))
                NativeSettings.refresh()
                return
            }
            root.nativeTimeActionError = false
            root.nativeTimeActionStatus = Translation.tr("Time zone changed to %1.").arg(timezone)
            NativeSettings.refresh()
        })
    }

    function syncTimezoneField() {
        if (!timezoneInput.activeFocus && !root.nativeTimeActionPending
                && root.nativeTimezone.length > 0)
            timezoneInput.text = root.nativeTimezone
    }

    readonly property var filteredTranslationKeys: {
        const term = translationSearchField.text.trim().toLowerCase()
        return Object.keys(englishTranslations).sort((a, b) => a.localeCompare(b)).filter(key => {
            const translated = `${targetTranslations[key] || ""}`.toLowerCase()
            if (!term.length) return true
            return key.toLowerCase().includes(term) || translated.includes(term)
        })
    }

    component NativeTimeStatusCard: Rectangle {
        id: statusCard
        property string iconName: "schedule"
        property string label: ""
        property string value: ""
        property string detail: ""

        Layout.fillWidth: true
        implicitHeight: nativeTimeStatusContent.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        RowLayout {
            id: nativeTimeStatusContent
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            MaterialSymbol {
                text: statusCard.iconName
                iconSize: 22
                color: Appearance.colors.colOnLayer1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: statusCard.label
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: statusCard.value || "…"
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: statusCard.detail.length > 0
                    text: statusCard.detail
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Connections {
        target: NativeSettings
        function onSnapshotChanged() { root.syncTimezoneField() }
    }

    Component.onCompleted: {
        root.syncTimezoneField()
        NativeSettings.refresh()
    }

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    Process {
        id: readSysLocaleProc
        running: true
        command: ["bash", "-c", "grep '^LANG=' /etc/locale.conf 2>/dev/null | head -1 | cut -d= -f2 | cut -d. -f1"]
        stdout: StdioCollector {
            id: sysLocaleCollector
            onStreamFinished: root.sysLocale = sysLocaleCollector.text.trim()
        }
    }

    Process {
        id: sysLangApplyProc
        property string targetLang: ""
        command: [
            "/usr/bin/pkexec",
            `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/set_language.sh`,
            sysLangApplyProc.targetLang
        ]
        stdout: StdioCollector { id: sysLangApplyOut }
        stderr: StdioCollector { id: sysLangApplyErr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.sysLangStatus = Translation.tr("System locale updated to %1.UTF-8. Re-login for full effect.").arg(sysLangApplyProc.targetLang)
                readSysLocaleProc.running = false
                readSysLocaleProc.running = true
            } else {
                const details = (sysLangApplyErr.text || sysLangApplyOut.text).trim()
                root.sysLangStatus = details.length > 0
                    ? Translation.tr("Failed to update system locale. %1").arg(details)
                    : Translation.tr("Failed to update system locale.")
            }
        }
    }

    FileView {
        id: englishTranslationFile
        path: `${Translation.translationsDir}/en_US.json`
        watchChanges: true
        onLoaded: root.englishTranslations = root.parseJson(text(), {})
        onLoadFailed: root.englishTranslations = ({})
        onFileChanged: reload()
    }

    FileView {
        id: targetTranslationFile
        path: root.targetTranslationPath()
        watchChanges: true
        onLoaded: {
            root.rawTargetJson = text() || "{}"
            root.targetTranslations = root.parseJson(root.rawTargetJson, {})
        }
        onLoadFailed: {
            root.rawTargetJson = "{}"
            root.targetTranslations = ({})
        }
        onFileChanged: reload()
    }

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentSubTab
        onCurrentIndexChanged: {
            root.currentSubTab = currentIndex
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
        visible: root.currentSubTab === 1
        icon: "language"
        title: Translation.tr("Date, time & language")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Keep language, clock formatting, and translation generation in one place instead of splitting them across general shell settings.")
        }
    }

    ContentSection {
        visible: root.currentSubTab === 1
        icon: "translate"
        title: Translation.tr("Language")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Selecting a locale updates the shell UI translation and the system-wide locale (/etc/locale.conf and Hyprland env.lua). Re-login for system changes to fully apply.")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: activeLocaleRow.implicitHeight + 20
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            RowLayout {
                id: activeLocaleRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                MaterialSymbol {
                    text: "public"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Active system locale")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    StyledText {
                        text: root.sysLocale.length > 0 ? root.sysLocale + ".UTF-8" : "…"
                        color: Appearance.colors.colOnLayer1
                        font.weight: Font.Medium
                    }
                }
            }
        }

        StyledComboBox {
            Layout.fillWidth: true
            buttonIcon: "language"
            textRole: "text"
            model: Translation.allAvailableLanguages.map(lang => ({ text: lang }))
            currentIndex: Math.max(0, Translation.allAvailableLanguages.indexOf(root.sysLocale))
            onActivated: index => localeInput.text = Translation.allAvailableLanguages[index]
        }

        ConfigRow {
            MaterialTextArea {
                id: localeInput
                Layout.fillWidth: true
                placeholderText: Translation.tr("Locale code, e.g. en_US, fr_FR, de_DE...")
                text: root.sysLocale
                onTextChanged: {
                    targetTranslationFile.path = root.targetTranslationPath()
                    targetTranslationFile.reload()
                }
            }

            RippleButtonWithIcon {
                Layout.fillHeight: true
                materialIcon: "save"
                enabled: !sysLangApplyProc.running && localeInput.text.trim().length > 0
                mainText: sysLangApplyProc.running ? Translation.tr("Applying…") : Translation.tr("Apply")
                onClicked: {
                    const lang = localeInput.text.trim()
                    if (!lang) return
                    root.sysLangStatus = ""
                    Config.options.language.ui = lang
                    sysLangApplyProc.targetLang = lang
                    sysLangApplyProc.running = false
                    sysLangApplyProc.running = true
                }
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "auto_awesome"
                enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                mainText: translationProc.running ? Translation.tr("Generating…") : Translation.tr("Generate translation")
                onClicked: {
                    translationProc.locale = localeInput.text.trim()
                    translationProc.running = false
                    translationProc.running = true
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "refresh"
                mainText: Translation.tr("Reload locale file")
                onClicked: {
                    targetTranslationFile.path = root.targetTranslationPath()
                    targetTranslationFile.reload()
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "edit_document"
                mainText: Translation.tr("Open locale JSON")
                onClicked: Qt.openUrlExternally(`file://${root.targetTranslationPath()}`)
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.sysLangStatus.length > 0
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: root.sysLangStatus
        }
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "dictionary"
        title: Translation.tr("Translation map")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("This shows the base English source string on the left and the current target locale translation on the right for %1.").arg(root.selectedLocaleCode())
        }

        MaterialTextField {
            id: translationSearchField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Filter English or translated text")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 420
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ListView {
                id: translationList
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 8
                model: root.filteredTranslationKeys

                delegate: Rectangle {
                    required property string modelData
                    width: translationList.width
                    implicitHeight: row.implicitHeight + 12
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        id: row
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            StyledText {
                                text: Translation.tr("English")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData
                                color: Appearance.colors.colOnLayer1
                                wrapMode: Text.Wrap
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            StyledText {
                                text: root.selectedLocaleCode()
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.targetTranslations[modelData] || ""
                                color: Appearance.colors.colOnLayer1
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "code"
        title: Translation.tr("Locale JSON editor")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Edit the raw translation JSON directly for %1. This writes to the locale file in the shell translations directory.").arg(root.selectedLocaleCode())
        }

        ScrollView {
            Layout.fillWidth: true
            implicitHeight: 360
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
            ScrollBar.vertical.policy: ScrollBar.AlwaysOn

            MaterialTextArea {
                id: rawJsonEditor
                width: parent.availableWidth
                wrapMode: TextEdit.NoWrap
                readOnly: false
                selectByMouse: true
                persistentSelection: true
                font.family: Appearance.font.family.monospace
                text: root.rawTargetJson
            }
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "save"
                mainText: Translation.tr("Save locale JSON")
                onClicked: {
                    const parsed = root.parseJson(rawJsonEditor.text, null)
                    if (parsed === null) return
                    const formatted = root.prettyJson(parsed)
                    targetTranslationFile.setText(formatted)
                    root.rawTargetJson = formatted
                    root.targetTranslations = parsed
                    targetTranslationFile.reload()
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "restore"
                mainText: Translation.tr("Reset editor from file")
                onClicked: {
                    targetTranslationFile.reload()
                }
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 0
        icon: "language"
        title: Translation.tr("System date & time")
        description: root.nativeTimeAvailable
            ? Translation.tr("Live systemd-timedated status")
            : Translation.tr("Native time service unavailable")

        ConfigRow {
            uniform: true

            NativeTimeStatusCard {
                iconName: "globe"
                label: Translation.tr("Time zone")
                value: root.nativeTimeAvailable
                    ? (root.nativeTimezone || Translation.tr("Unknown"))
                    : Translation.tr("Unavailable")
                detail: Translation.tr("System time zone")
            }

            NativeTimeStatusCard {
                iconName: root.nativeNtpEnabled ? "sync" : "sync_disabled"
                label: Translation.tr("Network time")
                value: !root.nativeTimeAvailable
                    ? Translation.tr("Unavailable")
                    : (!root.nativeCanNtp
                        ? Translation.tr("Not supported")
                        : (root.nativeNtpEnabled
                            ? Translation.tr("Enabled")
                            : Translation.tr("Disabled")))
                detail: root.nativeNtpEnabled
                    ? (root.nativeNtpSynchronized
                        ? Translation.tr("Clock synchronized")
                        : Translation.tr("Waiting for synchronization"))
                    : ""
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: !NativeSettings.connected || !root.nativeTimeAvailable
            materialIcon: "info"
            text: !NativeSettings.connected
                ? (NativeSettings.lastError || Translation.tr("Connecting to the native settings service…"))
                : Translation.tr("systemd-timedated is not available, so system time settings are read-only.")
        }

        ContentSubsection {
            title: Translation.tr("Automatic time")

            ConfigRow {
                uniform: true

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    enabled: NativeSettings.connected && root.nativeTimeAvailable
                        && root.nativeCanNtp && !root.nativeNtpEnabled
                        && !root.nativeTimeActionPending
                    materialIcon: "sync"
                    mainText: Translation.tr("Enable network time")
                    onClicked: root.setNetworkTime(true)
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    enabled: NativeSettings.connected && root.nativeTimeAvailable
                        && root.nativeCanNtp && root.nativeNtpEnabled
                        && !root.nativeTimeActionPending
                    materialIcon: "sync_disabled"
                    mainText: Translation.tr("Disable network time")
                    onClicked: root.setNetworkTime(false)
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Time zone")

            ConfigRow {
                MaterialTextField {
                    id: timezoneInput
                    Layout.fillWidth: true
                    maximumLength: 255
                    placeholderText: Translation.tr("IANA time zone, e.g. Europe/London")
                    enabled: NativeSettings.connected && root.nativeTimeAvailable
                        && !root.nativeTimeActionPending
                    onAccepted: root.setTimezone()
                }

                RippleButtonWithIcon {
                    Layout.fillHeight: true
                    materialIcon: "save"
                    mainText: root.nativeTimeActionPending
                        ? Translation.tr("Applying…")
                        : Translation.tr("Apply")
                    enabled: NativeSettings.connected && root.nativeTimeAvailable
                        && !root.nativeTimeActionPending
                        && root.timezoneValidationMessage(timezoneInput.text.trim()).length === 0
                        && timezoneInput.text.trim() !== root.nativeTimezone
                    onClicked: root.setTimezone()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: timezoneInput.text.length > 0
                    && root.timezoneValidationMessage(timezoneInput.text.trim()).length > 0
                text: root.timezoneValidationMessage(timezoneInput.text.trim())
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.nativeTimeActionStatus.length > 0
            text: root.nativeTimeActionStatus
            color: root.nativeTimeActionError
                ? Appearance.colors.colError
                : Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("System changes use typed native requests. Polkit may ask you to authorize them.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        visible: root.currentSubTab === 0
        icon: "schedule"
        title: Translation.tr("Clock appearance")

        ConfigSwitch {
            buttonIcon: "pace"
            text: Translation.tr("Second precision")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: Config.options.time.secondPrecision = checked
        }

        ContentSubsection {
            title: Translation.tr("Clock format")

            ConfigSelectionArray {
                currentValue: Config.options.time.format
                onSelected: newValue => {
                    if (newValue === "hh:mm")
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`])
                    else
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`])

                    Config.options.time.format = newValue
                }
                options: [
                    { displayName: Translation.tr("24h"), value: "hh:mm" },
                    { displayName: Translation.tr("12h am/pm"), value: "h:mm ap" },
                    { displayName: Translation.tr("12h AM/PM"), value: "h:mm AP" }
                ]
            }
        }
    }
}
