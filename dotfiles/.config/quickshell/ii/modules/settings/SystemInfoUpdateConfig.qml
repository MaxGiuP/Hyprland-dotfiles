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
    readonly property bool settingsApp: Quickshell.env("II_SETTINGS_APP") === "1"

    property string _hostname: ""
    property string _kernel: ""
    property string _cpu: ""
    property string _memory: ""
    property string _gpu: ""
    property string _uptime: ""

    Process {
        running: true
        command: ["bash", "-c",
            "echo \"hostname:$(hostname 2>/dev/null)\"; " +
            "echo \"kernel:$(uname -r)\"; " +
            "cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -s ' ' | sed 's/^ //'); " +
            "echo \"cpu:${cpu:-Unknown}\"; " +
            "awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"memory:%.1f / %.1f GiB\\n\",(t-a)/1048576,t/1048576}' /proc/meminfo; " +
            "gpu=$(lspci 2>/dev/null | grep -Ei '3D controller|VGA compatible' | head -1 | sed 's/^[^:]*: //'); " +
            "echo \"gpu:${gpu:-Unknown}\"; " +
            "echo \"uptime:$(uptime -p 2>/dev/null | sed 's/^up //')\""
        ]
        stdout: SplitParser {
            onRead: data => {
                const idx = data.indexOf(":")
                if (idx < 0) return
                const key = data.slice(0, idx)
                const value = data.slice(idx + 1)
                switch (key) {
                    case "hostname": root._hostname = value; break
                    case "kernel": root._kernel = value; break
                    case "cpu": root._cpu = value; break
                    case "memory": root._memory = value; break
                    case "gpu": root._gpu = value; break
                    case "uptime": root._uptime = value; break
                }
            }
        }
    }

    component InfoRow: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.preferredWidth: 88
            text: parent.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledText {
            Layout.fillWidth: true
            text: parent.value || "…"
            color: Appearance.colors.colOnLayer1
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        icon: "info"
        title: Translation.tr("System info")

        InfoRow { label: Translation.tr("Host"); value: root._hostname }
        InfoRow { label: Translation.tr("Kernel"); value: root._kernel }
        InfoRow { label: Translation.tr("CPU"); value: root._cpu }
        InfoRow { label: Translation.tr("Memory"); value: root._memory }
        InfoRow { label: Translation.tr("GPU"); value: root._gpu }
        InfoRow { label: Translation.tr("Uptime"); value: root._uptime }
    }

    ContentSection {
        icon: "system_update"
        title: Translation.tr("Updates")

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            text: Updates.available
                ? Translation.tr("%1 pending package updates").arg(Updates.count)
                : Translation.tr("No update helper script is configured.")
        }

        ConfigRow {
            uniform: true

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "refresh"
                mainText: Translation.tr("Check updates")
                onClicked: Updates.refresh()
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "system_update"
                mainText: Translation.tr("Run update app")
                onClicked: Quickshell.execDetached(["bash", "-lc", Config.options.apps.update])
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "info"
                mainText: Translation.tr("Open project about page")
                onClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland")
            }
        }
    }
}
