//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env II_STANDALONE_APP=1
//@ pragma Env II_SETTINGS_APP=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: window
    visible: true
    width: 960
    height: 720
    title: "smoke-home-system-section"
    color: Appearance.m3colors.m3background

    ContentPage {
        id: root
        anchors.fill: parent
        forceWidth: true
        baseWidth: 760

        property string _hostname: ""
        property string _memory: ""
        property string _uptime: ""

        Process {
            running: true
            command: ["bash", "-c",
                "echo \"hostname:$(hostname 2>/dev/null)\"; " +
                "awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf \"memory:%.1f / %.1f GiB\\n\",(t-a)/1048576,t/1048576}' /proc/meminfo; " +
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
                        case 'memory': root._memory = val; break
                        case 'uptime': root._uptime = val; break
                    }
                }
            }
        }

        ContentSection {
            icon: "monitor_heart"
            title: Translation.tr("System")

            ConfigRow {
                uniform: true

                ContentSubsection {
                    title: Translation.tr("Memory")
                    StyledText {
                        text: root._memory || "\u2026"
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Uptime")
                    StyledText {
                        text: root._uptime || "\u2026"
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Host")
                    StyledText {
                        text: root._hostname || "\u2026"
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
            }
        }
    }
}
