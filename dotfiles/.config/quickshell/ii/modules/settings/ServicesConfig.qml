import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    baseWidth: 760
    property int currentSubTab: 0
    readonly property var tabs: [
        { name: Translation.tr("AI & search"), icon: "neurology" },
        { name: Translation.tr("Integrations"), icon: "hub" },
        { name: Translation.tr("Data & performance"), icon: "memory" }
    ]

    function applySubTab(subTab, sectionId = "") {
        root.currentSubTab = Math.max(0, Math.min(subTab, root.tabs.length - 1))
        root.contentY = 0
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
        visible: root.currentSubTab === 0
        icon: "neurology"
        title: Translation.tr("AI")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("System prompt")
            text: Config.options.ai.systemPrompt
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.ai.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 1
        icon: "music_cast"
        title: Translation.tr("Music Recognition")

        ConfigSpinBox {
            icon: "timer_off"
            text: Translation.tr("Total duration timeout (s)")
            value: Config.options.musicRecognition.timeout
            from: 10
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.musicRecognition.timeout = value;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (s)")
            value: Config.options.musicRecognition.interval
            from: 2
            to: 10
            stepSize: 1
            onValueChanged: {
                Config.options.musicRecognition.interval = value;
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 1
        icon: "cell_tower"
        title: Translation.tr("Networking")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("User agent (for services that require it)")
            text: Config.options.networking.userAgent
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.networking.userAgent = text;
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "memory"
        title: Translation.tr("Resources")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
        
    }

    ContentSection {
        visible: root.currentSubTab === 2
        icon: "file_open"
        title: Translation.tr("Save paths")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Video Recording Path")
            text: Config.options.screenRecord.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenRecord.savePath = text;
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Screenshot Path (leave empty to just copy)")
            text: Config.options.screenSnip.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenSnip.savePath = text;
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 0
        icon: "search"
        title: Translation.tr("Search")

        ConfigSwitch {
            text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
            checked: Config.options.search.sloppy
            onCheckedChanged: {
                Config.options.search.sloppy = checked;
            }
            StyledToolTip {
                text: Translation.tr("Could be better if you make a ton of typos,\nbut results can be weird and might not work with acronyms\n(e.g. \"GIMP\" might not give you the paint program)")
            }
        }

        ContentSubsection {
            title: Translation.tr("Prefixes")
            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Action")
                    text: Config.options.search.prefix.action
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.action = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Clipboard")
                    text: Config.options.search.prefix.clipboard
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.clipboard = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Emojis")
                    text: Config.options.search.prefix.emojis
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.emojis = text;
                    }
                }
            }

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Math")
                    text: Config.options.search.prefix.math
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.math = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Shell command")
                    text: Config.options.search.prefix.shellCommand
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.shellCommand = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Web search")
                    text: Config.options.search.prefix.webSearch
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.webSearch = text;
                    }
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Web search")
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Base URL")
                text: Config.options.search.engineBaseUrl
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.engineBaseUrl = text;
                }
            }
        }
    }

    ContentSection {
        visible: root.currentSubTab === 1
        icon: "weather_mix"
        title: Translation.tr("Weather")
        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.bar.weather.enable
            onCheckedChanged: {
                Config.options.bar.weather.enable = checked;
            }
        }
        ConfigRow {
            ConfigSwitch {
                buttonIcon: "assistant_navigation"
                text: Translation.tr("Enable GPS based location")
                checked: Config.options.bar.weather.enableGPS
                onCheckedChanged: {
                    Config.options.bar.weather.enableGPS = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "thermometer"
                text: Translation.tr("Fahrenheit unit")
                checked: Config.options.bar.weather.useUSCS
                onCheckedChanged: {
                    Config.options.bar.weather.useUSCS = checked;
                }
                StyledToolTip {
                    text: Translation.tr("It may take a few seconds to update")
                }
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("City name")
            text: Config.options.bar.weather.city
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.bar.weather.city = text;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (m)")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: {
                Config.options.bar.weather.fetchInterval = value;
            }
        }
    }
}
