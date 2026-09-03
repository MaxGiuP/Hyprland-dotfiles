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
    property int currentSubTab: 0
    property var portalPermissions: []
    property string permissionStatus: ""
    property string secureBootStatus: Translation.tr("Checking…")
    property string encryptedRootStatus: Translation.tr("Checking…")

    readonly property var tabs: [
        { name: Translation.tr("Privacy"), icon: "privacy_tip" },
        { name: Translation.tr("App permissions"), icon: "app_badging" },
        { name: Translation.tr("Security"), icon: "shield_lock" }
    ]

    function applySubTab(subTab, sectionId = "") {
        root.currentSubTab = Math.max(0, Math.min(subTab, root.tabs.length - 1))
        root.contentY = 0
        if (root.currentSubTab === 1 && !portalPermissionProc.running)
            portalPermissionProc.running = true
        if (root.currentSubTab === 2 && !securityStatusProc.running)
            securityStatusProc.running = true
    }

    Process {
        id: portalPermissionProc
        command: ["flatpak", "permission-list"]
        onRunningChanged: if (running) {
            root.portalPermissions = []
            root.permissionStatus = Translation.tr("Reading portal permissions…")
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const fields = line.split("\t")
                if (fields.length < 3 || fields[0] === "Table")
                    return
                root.portalPermissions = root.portalPermissions.concat([{
                    table: fields[0],
                    resource: fields[1],
                    application: fields[2],
                    permission: fields.slice(3).join(" ")
                }])
            }
        }
        onExited: exitCode => {
            root.permissionStatus = exitCode === 0
                ? (root.portalPermissions.length === 0
                    ? Translation.tr("No stored sandbox permissions")
                    : Translation.tr("%1 stored permission records").arg(root.portalPermissions.length))
                : Translation.tr("The XDG permission store is unavailable")
        }
    }

    Process {
        id: securityStatusProc
        command: ["bash", "-lc",
            "if [ -d /sys/firmware/efi/efivars ]; then " +
            "if bootctl status 2>/dev/null | grep -qi 'Secure Boot: enabled'; then echo 'secure:On'; else echo 'secure:Off'; fi; " +
            "else echo 'secure:Unavailable'; fi; " +
            "root_src=$(findmnt -no SOURCE / 2>/dev/null); " +
            "root_type=$(lsblk -ndo TYPE \"$root_src\" 2>/dev/null); " +
            "if [ \"$root_type\" = crypt ]; then echo 'encrypted:On'; " +
            "elif lsblk -sno TYPE \"$root_src\" 2>/dev/null | grep -qx crypt; then echo 'encrypted:On'; " +
            "else echo 'encrypted:Off'; fi"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const separator = line.indexOf(":")
                if (separator < 0) return
                const key = line.slice(0, separator)
                const value = line.slice(separator + 1)
                if (key === "secure") root.secureBootStatus = Translation.tr(value)
                if (key === "encrypted") root.encryptedRootStatus = Translation.tr(value)
            }
        }
    }

    Component.onCompleted: portalPermissionProc.running = true

    SecondaryTabBar {
        Layout.fillWidth: true
        currentIndex: root.currentSubTab
        onCurrentIndexChanged: root.applySubTab(currentIndex)

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
        visible: root.currentSubTab === 0
        icon: "policy"
        title: Translation.tr("Data and AI policy")
        description: Translation.tr("Shell-owned policy is saved in config.json")

        ContentSubsection {
            title: Translation.tr("AI access")

            ConfigSelectionArray {
                currentValue: Config.options.policies.ai
                onSelected: newValue => Config.options.policies.ai = newValue
                options: [
                    { displayName: Translation.tr("Disabled"), icon: "close", value: 0 },
                    { displayName: Translation.tr("Allowed"), icon: "check", value: 1 },
                    { displayName: Translation.tr("Local only"), icon: "sync_saved_locally", value: 2 }
                ]
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 0
        icon: "shield"
        title: Translation.tr("Content safety")

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide potentially sensitive clipboard images")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: Config.options.workSafety.enable.clipboard = checked
        }

        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide potentially sensitive wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: Config.options.workSafety.enable.wallpaper = checked
        }
    }

    ContentSection {
        visible: root.currentSubTab === 1
        icon: "app_badging"
        title: Translation.tr("Sandbox permissions")
        description: root.permissionStatus

        StyledText {
            visible: root.portalPermissions.length === 0
            Layout.fillWidth: true
            text: root.permissionStatus
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
        }

        Repeater {
            model: root.portalPermissions.slice(0, 60)

            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: permissionRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                RowLayout {
                    id: permissionRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    MaterialSymbol {
                        text: "deployed_code_account"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.application || Translation.tr("Shared portal resource")
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: `${modelData.table} · ${modelData.resource}`
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                            elide: Text.ElideMiddle
                        }
                    }

                    StyledText {
                        text: modelData.permission || Translation.tr("Stored")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "refresh"
            mainText: Translation.tr("Refresh permissions")
            enabled: !portalPermissionProc.running
            onClicked: portalPermissionProc.running = true
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("These are permissions enforced through XDG portals. Unsandboxed applications are not covered by a universal Linux permission layer.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "shield_lock"
        title: Translation.tr("Device security")

        ConfigRow {
            uniform: true

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: secureBootRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: secureBootRow
                    anchors.fill: parent
                    anchors.margins: 10
                    MaterialSymbol { text: "verified_user"; iconSize: 22; color: Appearance.colors.colOnLayer1 }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Secure Boot"); color: Appearance.colors.colOnLayer1 }
                    StyledText { text: root.secureBootStatus; color: Appearance.colors.colSubtext }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: encryptionRow.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                RowLayout {
                    id: encryptionRow
                    anchors.fill: parent
                    anchors.margins: 10
                    MaterialSymbol { text: "encrypted"; iconSize: 22; color: Appearance.colors.colOnLayer1 }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("System disk encryption"); color: Appearance.colors.colOnLayer1 }
                    StyledText { text: root.encryptedRootStatus; color: Appearance.colors.colSubtext }
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "key"
            text: Translation.tr("Unlock login keyring with the session")
            checked: Config.options.lock.security.unlockKeyring
            onCheckedChanged: Config.options.lock.security.unlockKeyring = checked
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Require password for power actions on lock screen")
            checked: Config.options.lock.security.requirePasswordToPower
            onCheckedChanged: Config.options.lock.security.requirePasswordToPower = checked
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "lock"
            mainText: Translation.tr("Lock now")
            onClicked: GlobalStates.screenLocked = true
        }
    }
}
