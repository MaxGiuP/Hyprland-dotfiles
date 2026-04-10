import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    function normalizeGpuName(value) {
        let s = (value || "")
            .replace(/^[^:]*controller:\s*/i, "")
            .replace(/\s+\(rev .*?\)\s*$/i, "")
            .trim()
        // Extract bracketed model name if present (e.g. "NVIDIA Corp GB206 [GeForce RTX 5060]")
        const bracketed = s.match(/\[([^\]]+)\]/)
        if (bracketed) return bracketed[1]
        // Otherwise strip leading vendor + chip code (e.g. "Advanced Micro Devices GB206 ")
        return s.replace(/^(NVIDIA Corporation|Advanced Micro Devices, Inc\. \[AMD\/ATI\]|Intel Corporation)\s+[A-Z0-9]+\s+/i, "").trim() || s
    }

    // ── Hardware spec properties ──────────────────────────────────────────
    property string _hostname: ""
    property string _kernel: ""
    property string _cpu: ""
    property string _memory: ""
    property string _memtype: ""
    property string _gpu: ""
    property string _shell: ""
    property string _uptime: ""

    Process {
        id: hwInfoProc
        running: true
        command: ["bash", "-c",
            "echo \"hostname:$(cat /proc/sys/kernel/hostname 2>/dev/null)\"; " +
            "echo \"kernel:$(uname -r)\"; " +
            "cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -s ' ' | sed 's/^ //'); " +
            "cores=$(awk -F': ' '/^physical id/{pid=$2} /^core id/{print pid\"_\"$2}' /proc/cpuinfo | sort -u | wc -l 2>/dev/null); " +
            "threads=$(nproc 2>/dev/null); " +
            "echo \"cpu:${cpu:-Unknown} (${cores}C / ${threads}T)\"; " +
            "awk '/MemTotal/{t=$2}END{total_gib=t/1048576; rounded=4; while(rounded<total_gib*0.98) rounded*=2; printf \"memtotal:%d GiB\\n\",rounded}' /proc/meminfo; " +
            "dmi=$(sudo -n dmidecode -t 17 2>/dev/null); " +
            "if [ -n \"$dmi\" ]; then " +
            "  memtype=$(echo \"$dmi\" | awk '/^\\tType:/ && !/Detail/ && $2 != \"Unknown\"{print $2; exit}'); " +
            "  memspeed=$(echo \"$dmi\" | awk '/^\\tSpeed:/ && $2 != \"Unknown\"{print $2,$3; exit}'); " +
            "  echo \"memtype:${memtype:-?} @ ${memspeed:-?}\"; " +
            "else echo \"memtype:\"; fi; " +
            "gpu=$(lspci 2>/dev/null | grep -Ei '3D controller' | head -1 | awk -F': ' '{print $2}' | sed -E 's/ \\(rev .*$//'); " +
            "[ -z \"$gpu\" ] && gpu=$(lspci 2>/dev/null | grep -Ei 'VGA compatible controller' | head -1 | awk -F': ' '{print $2}' | sed -E 's/ \\(rev .*$//'); " +
            "echo \"gpu:${gpu:-Unknown}\"; " +
            "echo \"shell:$(basename ${SHELL:-sh})\"; " +
            "echo \"uptime:$(uptime -p 2>/dev/null | sed 's/^up //' || echo Unknown)\""
        ]
        stdout: SplitParser {
            onRead: data => {
                const idx = data.indexOf(':')
                if (idx < 0) return
                const key = data.slice(0, idx)
                const val = data.slice(idx + 1)
                switch (key) {
                    case 'hostname': root._hostname = val; break
                    case 'kernel':   root._kernel   = val; break
                    case 'cpu':      root._cpu      = val; break
                    case 'memtotal': root._memory   = val; break
                    case 'memtype':  root._memtype  = val; break
                    case 'gpu':      root._gpu      = root.normalizeGpuName(val); break
                    case 'shell':    root._shell    = val; break
                    case 'uptime':   root._uptime   = val; break
                }
            }
        }
    }

    // Reusable spec row — property bindings on specValue are reactive
    component SpecRow: RowLayout {
        property string specIcon: ""
        property string specLabel: ""
        property string specValue: ""
        Layout.fillWidth: true
        spacing: 10

        MaterialSymbol {
            text: parent.specIcon
            iconSize: 18
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.preferredWidth: 80
            text: parent.specLabel
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            Layout.fillWidth: true
            text: parent.specValue || "\u2026"
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    // ── Hardware ─────────────────────────────────────────────────────────
    ContentSection {
        icon: "computer"
        title: Translation.tr("Hardware")

        SpecRow { specIcon: "computer";        specLabel: Translation.tr("Host");   specValue: root._hostname }
        SpecRow { specIcon: "memory";          specLabel: Translation.tr("Kernel"); specValue: root._kernel }
        SpecRow { specIcon: "developer_board"; specLabel: Translation.tr("CPU");    specValue: root._cpu }
        SpecRow { specIcon: "storage";         specLabel: Translation.tr("Memory"); specValue: root._memtype + (root._memory ? "  ·  " + root._memory : "") }
        SpecRow { specIcon: "monitor";         specLabel: Translation.tr("GPU");    specValue: root._gpu }
        SpecRow { specIcon: "terminal";        specLabel: Translation.tr("Shell");  specValue: root._shell }
        SpecRow { specIcon: "schedule";        specLabel: Translation.tr("Uptime"); specValue: root._uptime }
    }

    // ── Distro ────────────────────────────────────────────────────────────
    ContentSection {
        icon: "box"
        title: Translation.tr("Distro")

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            IconImage {
                implicitSize: 80
                source: Quickshell.iconPath(SystemInfo.logo)
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                StyledText {
                    text: SystemInfo.distroName
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    text: SystemInfo.homeUrl
                    textFormat: Text.MarkdownText
                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                    }
                    PointingHandLinkHover {}
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5

            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.documentationUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "support"
                mainText: Translation.tr("Help & Support")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.supportUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "bug_report"
                mainText: Translation.tr("Report a Bug")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.bugReportUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "policy"
                materialIconFill: false
                mainText: Translation.tr("Privacy Policy")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.privacyPolicyUrl)
                }
            }
        }
    }

    // ── Dotfiles ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "folder_managed"
        title: Translation.tr("Dotfiles")

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            IconImage {
                implicitSize: 80
                source: Quickshell.iconPath("illogical-impulse")
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                StyledText {
                    text: Translation.tr("illogical-impulse")
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    text: "https://github.com/end-4/dots-hyprland"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    textFormat: Text.MarkdownText
                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                    }
                    PointingHandLinkHover {}
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5

            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: {
                    Qt.openUrlExternally("https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "adjust"
                materialIconFill: false
                mainText: Translation.tr("Issues")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/end-4/dots-hyprland/issues")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "forum"
                mainText: Translation.tr("Discussions")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/end-4/dots-hyprland/discussions")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "favorite"
                mainText: Translation.tr("Donate")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/sponsors/end-4")
                }
            }
        }
    }
}
