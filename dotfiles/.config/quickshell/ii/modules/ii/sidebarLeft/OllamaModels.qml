import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: root

    property real padding: 8
    property string selectedUseCaseFilter: "all"
    property string customModelId: ""
    readonly property var useCaseFilters: [
        {"id": "all", "label": Translation.tr("All")},
        {"id": "chat", "label": Translation.tr("Chat")},
        {"id": "coding", "label": Translation.tr("Coding")},
        {"id": "reasoning", "label": Translation.tr("Reasoning")},
        {"id": "agents", "label": Translation.tr("Agents")},
        {"id": "lightweight", "label": Translation.tr("Lightweight")},
    ]
    readonly property var suggestedRecommendations: Ai.storeOllamaRecommendations.filter(entry =>
        root.matchesUseCase(entry) && Ai.successorContextForRecommendation(entry).length === 0
    )
    readonly property var successorRecommendations: Ai.successorStoreOllamaRecommendations.filter(entry =>
        root.matchesUseCase(entry)
    )

    function focusActiveItem() {
        customInstallField.forceActiveFocus()
    }

    function recommendationUseCases(entry) {
        return entry?.use_cases ?? []
    }

    function matchesUseCase(entry) {
        if (root.selectedUseCaseFilter === "all")
            return true
        return root.recommendationUseCases(entry).indexOf(root.selectedUseCaseFilter) !== -1
    }

    function formatUseCaseLabel(tag) {
        if (tag === "chat")
            return Translation.tr("Chat")
        if (tag === "coding")
            return Translation.tr("Coding")
        if (tag === "reasoning")
            return Translation.tr("Reasoning")
        if (tag === "agents")
            return Translation.tr("Agents")
        if (tag === "lightweight")
            return Translation.tr("Lightweight")
        return tag
    }

    function installCustomModel() {
        const modelId = root.customModelId.trim()
        if (modelId.length === 0)
            return

        Ai.queueOllamaInstall([modelId])
        root.customModelId = ""
    }

    component InfoChip: Rectangle {
        required property string text
        implicitHeight: chipLabel.implicitHeight + 8
        implicitWidth: chipLabel.implicitWidth + 14
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer2

        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            text: parent.text
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    component RecommendationCard: Rectangle {
        required property var entry
        readonly property string installId: entry.install_id ?? ""
        readonly property string installState: Ai.ollamaInstallStateFor(installId)
        readonly property string successorContext: Ai.successorContextForRecommendation(entry)
        readonly property string storageSize: entry.storage_size?.length > 0 ? entry.storage_size : ""
        readonly property var useCases: entry.use_cases ?? []
        readonly property string hardwareHint: entry.hardware_hint ?? ""

        width: parent ? parent.width : 0
        implicitHeight: content.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer3
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: entry.display_name ?? installId
                        color: Appearance.colors.colOnLayer1
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colSubtext
                        text: installId
                        elide: Text.ElideRight
                    }
                }

                DialogButton {
                    enabled: !Ai.ollamaRemoveBusy && installState === "available"
                    buttonText: installState === "installed"
                        ? Translation.tr("Installed")
                        : (installState === "paused"
                            ? Translation.tr("Paused")
                            : (installState === "installing"
                                ? Translation.tr("Installing")
                                : (installState === "queued"
                                    ? Translation.tr("Queued")
                                    : Translation.tr("Install"))))
                    colBackground: installState === "installed"
                        ? Appearance.colors.colLayer2
                        : Appearance.colors.colLayer3
                    colBackgroundHover: installState === "installed"
                        ? Appearance.colors.colLayer2
                        : Appearance.colors.colLayer3Hover
                    colText: installState === "installed"
                        ? Appearance.colors.colSubtext
                        : Appearance.colors.colPrimary
                    downAction: () => Ai.queueOllamaInstall([installId])
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colOnLayer1
                text: entry.reason?.length > 0 ? entry.reason : (entry.description ?? "")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        ...(storageSize.length > 0 ? [Translation.tr("Storage: %1").arg(storageSize)] : []),
                        ...(hardwareHint.length > 0 ? [hardwareHint] : []),
                        ...useCases.map(tag => root.formatUseCaseLabel(tag)),
                    ]

                    delegate: InfoChip {
                        required property string modelData
                        text: modelData
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: successorContext.length > 0
                color: Appearance.colors.colPrimary
                wrapMode: Text.WordWrap
                text: Translation.tr("Successor to your %1").arg(successorContext)
            }

            StyledText {
                Layout.fillWidth: true
                visible: entry.updated_label?.length > 0
                color: Appearance.colors.colSubtext
                text: Translation.tr("Updated %1").arg(entry.updated_label ?? "")
            }
        }
    }

    Process {
        id: ollamaServeProc
        command: ["ollama", "serve"]

        onRunningChanged: {
            if (!running)
                Qt.callLater(() => Ai.refreshOllamaStatus())
        }
    }

    Process {
        id: ollamaKillProc
        command: ["pkill", "ollama"]

        onExited: Qt.callLater(() => Ai.refreshOllamaStatus())
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.padding

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: summaryLayout.implicitHeight + 18
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ColumnLayout {
                id: summaryLayout
                anchors.fill: parent
                anchors.margins: 9
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "memory"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Ollama models")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colSubtext
                            text: !Ai.ollamaInstalled
                                ? Translation.tr("Ollama is not installed or not currently detectable on this machine.")
                                : (Ai.ollamaRunning
                                    ? Translation.tr("Manage installed and recommended local models while the Ollama runtime is online.")
                                    : Translation.tr("Manage installed and recommended local models. Start the Ollama runtime when you need it."))
                        }
                    }

                    DialogButton {
                        buttonText: Translation.tr("Refresh")
                        downAction: () => {
                            Ai.refreshOnlineModels()
                            Ai.refreshOllamaStatus()
                        }
                    }

                    DialogButton {
                        enabled: Ai.ollamaInstalled
                        buttonText: Ai.ollamaRunning ? Translation.tr("Stop") : Translation.tr("Start")
                        downAction: () => {
                            if (Ai.ollamaRunning) {
                                ollamaServeProc.running = false
                                ollamaKillProc.running = true
                            } else {
                                ollamaServeProc.running = true
                            }
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    InfoChip {
                        text: Ai.ollamaRunning ? Translation.tr("Runtime online") : Translation.tr("Runtime offline")
                    }

                    InfoChip {
                        text: Translation.tr("%1 installed").arg(Ai.localOllamaModels.length)
                    }

                    InfoChip {
                        text: Translation.tr("%1 suggested").arg(Ai.storeOllamaRecommendations.length)
                    }

                    InfoChip {
                        text: Translation.tr("%1 successors").arg(Ai.successorStoreOllamaRecommendations.length)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: Ai.ollamaMutationBusy
            implicitHeight: installStatusLayout.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ColumnLayout {
                id: installStatusLayout
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnLayer1
                    font.bold: true
                    text: Ai.ollamaInstallingModelId.length > 0
                        ? (Ai.ollamaInstallPaused
                            ? Translation.tr("Paused %1").arg(Ai.ollamaInstallingModelId)
                            : Translation.tr("Installing %1").arg(Ai.ollamaInstallingModelId))
                        : Translation.tr("Removing %1").arg(Ai.ollamaRemovingModelId)
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: Ai.ollamaInstallingModelId.length > 0
                        ? Ai.ollamaInstallStatusText
                        : Ai.ollamaRemoveStatusText
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    visible: Ai.ollamaInstallingModelId.length > 0 && Ai.ollamaInstallProgress >= 0
                    value: Ai.ollamaInstallProgress
                }

                StyledIndeterminateProgressBar {
                    Layout.fillWidth: true
                    visible: (Ai.ollamaInstallingModelId.length > 0 && Ai.ollamaInstallProgress < 0)
                        || Ai.ollamaRemovingModelId.length > 0
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: Ai.ollamaInstallingModelId.length > 0
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    DialogButton {
                        enabled: !Ai.ollamaInstallCancelRequested
                        buttonText: Ai.ollamaInstallPaused ? Translation.tr("Resume") : Translation.tr("Pause")
                        downAction: () => {
                            if (Ai.ollamaInstallPaused)
                                Ai.resumeOllamaInstall()
                            else
                                Ai.pauseOllamaInstall()
                        }
                    }

                    DialogButton {
                        enabled: !Ai.ollamaInstallCancelRequested
                        buttonText: Translation.tr("Cancel")
                        colEnabled: Appearance.colors.colError
                        downAction: () => Ai.cancelOllamaInstall()
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: root.useCaseFilters

                delegate: DialogButton {
                    required property var modelData
                    buttonText: modelData.label
                    toggled: root.selectedUseCaseFilter === modelData.id
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundToggled: Appearance.colors.colPrimary
                    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                    colText: toggled ? colForegroundToggled : Appearance.colors.colOnLayer1
                    downAction: () => root.selectedUseCaseFilter = modelData.id
                }
            }
        }

        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Column {
                width: scrollView.availableWidth
                spacing: 14

                Rectangle {
                    width: parent.width
                    implicitHeight: manualInstallLayout.implicitHeight + 16
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    ColumnLayout {
                        id: manualInstallLayout
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Manual install")
                            color: Appearance.colors.colOnLayer1
                            font.bold: true
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Know the exact Ollama model id already? Install it directly here.")
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialTextField {
                                id: customInstallField
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Custom model id, e.g. qwen3:4b")
                                text: root.customModelId
                                onTextChanged: root.customModelId = text
                                onAccepted: root.installCustomModel()
                            }

                            DialogButton {
                                buttonText: Translation.tr("Install")
                                downAction: root.installCustomModel
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Installed")
                            color: Appearance.colors.colOnLayer1
                            font.bold: true
                        }

                        DialogButton {
                            buttonText: Translation.tr("Refresh")
                            downAction: () => Ai.refreshOllamaStatus()
                        }
                    }

                    StyledText {
                        width: parent.width
                        visible: Ai.localOllamaModels.length === 0
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("No local Ollama models are installed yet.")
                    }

                    Repeater {
                        model: Ai.localOllamaModels

                        delegate: Rectangle {
                            required property string modelData
                            readonly property string removeState: Ai.ollamaRemoveStateFor(modelData)
                            width: parent.width
                            implicitHeight: installedRow.implicitHeight + 12
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer3

                            RowLayout {
                                id: installedRow
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Ai.guessModelName(modelData)
                                        color: Appearance.colors.colOnLayer1
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        color: Appearance.colors.colSubtext
                                        text: modelData
                                        elide: Text.ElideRight
                                    }
                                }

                                ApiCommandButton {
                                    enabled: !Ai.ollamaInstallBusy && removeState === "installed"
                                    buttonText: removeState === "removing"
                                        ? Translation.tr("Removing")
                                        : (removeState === "queued" ? Translation.tr("Queued") : Translation.tr("Remove"))
                                    downAction: () => Ai.queueOllamaRemoval([modelData])
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Recommended models")
                            color: Appearance.colors.colOnLayer1
                            font.bold: true
                        }

                        DialogButton {
                            enabled: Ai.availableOllamaRecommendations.length > 0
                            buttonText: Translation.tr("Install all")
                            downAction: () => Ai.installAllSuggestedOllamaModels()
                        }
                    }

                    StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Browse curated local models by use case, compare storage size, then install directly from here.")
                    }

                    StyledText {
                        width: parent.width
                        visible: root.suggestedRecommendations.length === 0
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("No suggested models match this filter right now.")
                    }

                    Repeater {
                        model: root.suggestedRecommendations

                        delegate: RecommendationCard {
                            required property var modelData
                            entry: modelData
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8

                    StyledText {
                        width: parent.width
                        text: Translation.tr("Potential successors")
                        color: Appearance.colors.colOnLayer1
                        font.bold: true
                    }

                    StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("These suggestions are newer models that fit families you already have installed.")
                    }

                    StyledText {
                        width: parent.width
                        visible: root.successorRecommendations.length === 0
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("No successor suggestions match this filter right now.")
                    }

                    Repeater {
                        model: root.successorRecommendations

                        delegate: RecommendationCard {
                            required property var modelData
                            entry: modelData
                        }
                    }
                }
            }
        }
    }
}
