pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property alias states: persistentStatesJsonAdapter
    property string fileDir: Directories.state
    property string fileName: "states.json"
    property string filePath: `${root.fileDir}/${root.fileName}`

    property bool ready: false
    property string previousHyprlandInstanceSignature: ""
    property bool isNewHyprlandInstance: previousHyprlandInstanceSignature !== states.hyprlandInstanceSignature

    onReadyChanged: {
        root.previousHyprlandInstanceSignature = root.states.hyprlandInstanceSignature
        root.states.hyprlandInstanceSignature = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    }

    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.reload()
        }
    }

    Timer {
        id: fileWriteTimer
        interval: 100
        repeat: false
        onTriggered: {
            persistentStatesFileView.writeAdapter()
        }
    }

    FileView {
        id: persistentStatesFileView
        path: root.filePath

        // Quickshell 0.2.1 can crash when JsonAdapter reloads this file immediately
        // after its own startup writes. Keep persistence enabled but avoid self-watch reloads.
        watchChanges: false
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            console.log("Failed to load persistent states file:", error);
            if (error == FileViewError.FileNotFound) {
                fileWriteTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: persistentStatesJsonAdapter

            property string hyprlandInstanceSignature: ""

            property JsonObject ai: JsonObject {
                property string model: "gemini-flash-latest"
                property real temperature: 0.5
                property string lastAutoFreeGeminiModelId: ""
                property bool modelNotificationsInitialized: false
                property list<string> seenGeminiModelIds: []
                property list<string> seenRelevantOllamaModelIds: []
            }

            property JsonObject cheatsheet: JsonObject {
                property int tabIndex: 0
            }

            property JsonObject sidebar: JsonObject {
                property JsonObject bottomGroup: JsonObject {
                    property bool collapsed: false
                    property int tab: 0
                }
            }

            property JsonObject idle: JsonObject {
                property bool inhibit: false
            }

            property JsonObject liveCaptions: JsonObject {
                property string backend: "whisper"
                property string source: "system"
                property string displayMode: "bilingual"
                property string preferredLanguage: "auto"
                property string targetLanguage: "en"
                property string model: "tiny"
                property string tuningPreset: "realtime"
            }

            property JsonObject liveScreenTranslation: JsonObject {
                property string targetLanguage: "en"
                property string region: ""
                property string regionLabel: ""
            }

            property JsonObject audio: JsonObject {
                property JsonObject sink: JsonObject {
                    property string name: ""
                    property string description: ""
                    property string nickname: ""
                }
                property JsonObject source: JsonObject {
                    property string name: ""
                    property string description: ""
                    property string nickname: ""
                }
            }

            // Widget x/y are stored as fractions of the screen size (0.0–1.0)
            // so positions scale correctly across monitors of different resolutions.
            // Legacy saves with integer values >= 2 are handled transparently by
            // StyledOverlayWidget and converted to fractions on next save.
            property JsonObject overlay: JsonObject {
                property list<string> open: ["crosshair", "recorder", "volumeMixer", "resources"]
                property JsonObject crosshair: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property bool draggableWhenPinned: false
                    property real x: 0.4307  // ~827/1920
                    property real y: 0.4083  // ~441/1080
                    property real width: 250
                    property real height: 100
                }
                property JsonObject floatingImage: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property bool draggableWhenPinned: false
                    property real x: 0.8594  // ~1650/1920
                    property real y: 0.3611  // ~390/1080
                    property real width: 0
                    property real height: 0
                }
                property JsonObject fpsLimiter: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property bool draggableWhenPinned: false
                    property real x: 0.8177  // ~1570/1920
                    property real y: 0.5694  // ~615/1080
                    property real width: 280
                    property real height: 80
                }
                property JsonObject recorder: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property bool draggableWhenPinned: false
                    property real x: 0.0417  // ~80/1920
                    property real y: 0.0741  // ~80/1080
                    property real width: 350
                    property real height: 130
                }
                property JsonObject resources: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property bool draggableWhenPinned: false
                    property real x: 0.7813  // ~1500/1920
                    property real y: 0.7130  // ~770/1080
                    property real width: 350
                    property real height: 200
                    property int tabIndex: 0
                }
                property JsonObject volumeMixer: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property bool draggableWhenPinned: false
                    property real x: 0.0417  // ~80/1920
                    property real y: 0.2593  // ~280/1080
                    property real width: 350
                    property real height: 600
                    property int tabIndex: 0
                }
                property JsonObject notes: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property bool draggableWhenPinned: false
                    property real x: 0.7292  // ~1400/1920
                    property real y: 0.0389  // ~42/1080
                    property real width: 460
                    property real height: 330
                }
                property JsonObject liveCaptions: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property bool draggableWhenPinned: false
                    property real x: 0.1042  // ~200/1920
                    property real y: 0.7407  // ~800/1080
                    property real width: 520
                    property real height: 100
                }
                property JsonObject liveCaptionsTranslation: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property bool draggableWhenPinned: false
                    property real x: 0.1042  // ~200/1920
                    property real y: 0.8519  // ~920/1080
                    property real width: 520
                    property real height: 80
                }
                property JsonObject liveScreenTranslation: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property bool draggableWhenPinned: false
                    property real x: 0.4688  // ~900/1920
                    property real y: 0.1667  // ~180/1080
                    property real width: 520
                    property real height: 260
                }
                property JsonObject liveScreenTranslationOutput: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: true
                    property bool draggableWhenPinned: false
                    property real x: 0.4688  // ~900/1920
                    property real y: 0.1667  // ~180/1080
                    property real width: 520
                    property real height: 120
                }
                property JsonObject liveCaptionsSettings: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property bool draggableWhenPinned: false
                    property real x: 0.2083  // ~400/1920
                    property real y: 0.1852  // ~200/1080
                    property real width: 480
                    property real height: 400
                }
                property JsonObject settingsMenu: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property bool draggableWhenPinned: false
                    property real x: 0.1146  // ~220/1920
                    property real y: 0.1019  // ~110/1080
                    property real width: 1100
                    property real height: 750
                    property int currentPage: 0
                }
                property JsonObject terminal: JsonObject {
                    property bool pinned: false
                    property bool clickthrough: false
                    property bool draggableWhenPinned: true
                    property real x: 0.2604  // ~500/1920
                    property real y: 0.2593  // ~280/1080
                    property real width: 600
                    property real height: 450
                }
            }

            property JsonObject timer: JsonObject {
                property JsonObject countdown: JsonObject {
                    property bool running: false
                    property int start: 0
                    property int duration: 300
                }
                property JsonObject pomodoro: JsonObject {
                    property bool running: false
                    property int start: 0
                    property bool isBreak: false
                    property int cycle: 0
                }
                property JsonObject stopwatch: JsonObject {
                    property bool running: false
                    property int start: 0
                    property list<var> laps: []
                }
            }
        }
    }
}
