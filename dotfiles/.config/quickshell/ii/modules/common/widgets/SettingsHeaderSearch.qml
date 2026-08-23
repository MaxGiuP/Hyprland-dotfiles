import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

FocusScope {
    id: root

    property string query: ""
    property var pages: []
    property int maxResults: 8
    signal queryEdited(string value)
    signal resultSelected(var result)

    readonly property var recommendations: {
        const searchText = root.query.trim().toLowerCase()
        if (!searchText)
            return []

        function compact(value) {
            return String(value ?? "").toLowerCase().replace(/[\s\-_./&]+/g, "")
        }

        const compactSearchText = compact(searchText)
        const results = []
        const seen = new Set()

        function addResult(result, score) {
            const key = `${result.pageIndex}:${result.label}:${result.subTab}:${result.sectionId}`
            if (seen.has(key))
                return

            seen.add(key)
            result.score = score
            results.push(result)
        }

        for (let pageIndex = 0; pageIndex < root.pages.length; pageIndex++) {
            const page = root.pages[pageIndex]
            const pageName = page?.displayName ?? ""
            const description = page?.description ?? ""
            const pageText = `${pageName} ${description}`
            if (!pageText.toLowerCase().includes(searchText) && !compact(pageText).includes(compactSearchText))
                continue

            addResult({
                icon: page.icon,
                label: pageName,
                pageName: description,
                pageIndex: pageIndex,
                subTab: -1,
                sectionId: ""
            }, pageName.toLowerCase().startsWith(searchText) ? 0 : 2)
        }

        for (const entry of SettingsSearchIndex.entries) {
            const localizedLabel = Translation.tr(entry.label)
            const pageName = root.pages[entry.page]?.displayName ?? ""
            const resultText = `${localizedLabel} ${entry.label} ${pageName}`
            if (!resultText.toLowerCase().includes(searchText) && !compact(resultText).includes(compactSearchText))
                continue

            const localizedLower = localizedLabel.toLowerCase()
            const sourceLower = entry.label.toLowerCase()
            addResult({
                icon: entry.icon,
                label: localizedLabel,
                pageName: pageName,
                pageIndex: entry.page,
                subTab: entry.subTab ?? -1,
                sectionId: entry.sectionId ?? ""
            }, localizedLower.startsWith(searchText) || compact(localizedLower).startsWith(compactSearchText)
                ? 1
                : sourceLower.startsWith(searchText) || compact(sourceLower).startsWith(compactSearchText) ? 2 : 3)
        }

        results.sort((left, right) => left.score - right.score || left.label.localeCompare(right.label))
        return results.slice(0, root.maxResults)
    }
    readonly property bool dropdownVisible: root.activeFocus && root.query.trim().length > 0

    Layout.preferredWidth: Math.max(180, Math.min(280, (parent?.width ?? 700) * 0.32))
    Layout.minimumWidth: 180
    Layout.maximumWidth: 280
    Layout.preferredHeight: 36
    implicitHeight: 36
    z: 100

    function clearQuery(keepFocus = true) {
        searchField.clear()
        root.queryEdited("")
        if (keepFocus)
            searchField.forceActiveFocus()
    }

    function selectResult(result) {
        if (!result)
            return

        const selectedResult = {
            icon: result.icon,
            label: result.label,
            pageName: result.pageName,
            pageIndex: result.pageIndex,
            subTab: result.subTab,
            sectionId: result.sectionId
        }
        root.clearQuery(false)
        root.resultSelected(selectedResult)
        root.focus = false
    }

    onRecommendationsChanged: recommendationList.currentIndex = recommendations.length > 0 ? 0 : -1

    ToolbarTextField {
        id: searchField
        anchors.fill: parent
        leftPadding: 38
        rightPadding: clearButton.visible ? 38 : 12
        placeholderText: Translation.tr("Search settings")
        selectByMouse: true

        onTextEdited: root.queryEdited(text)
        Keys.onDownPressed: event => {
            if (root.recommendations.length > 0)
                recommendationList.currentIndex = Math.min(recommendationList.currentIndex + 1, root.recommendations.length - 1)
            event.accepted = true
        }
        Keys.onUpPressed: event => {
            if (root.recommendations.length > 0)
                recommendationList.currentIndex = Math.max(recommendationList.currentIndex - 1, 0)
            event.accepted = true
        }
        Keys.onReturnPressed: event => {
            root.selectResult(root.recommendations[recommendationList.currentIndex])
            event.accepted = true
        }
        Keys.onEnterPressed: event => {
            root.selectResult(root.recommendations[recommendationList.currentIndex])
            event.accepted = true
        }
        Keys.onEscapePressed: event => {
            if (text.length > 0)
                root.clearQuery()
            else
                searchField.focus = false
            event.accepted = true
        }

        Binding {
            target: searchField
            property: "text"
            value: root.query
            when: !searchField.activeFocus
            restoreMode: Binding.RestoreNone
        }
    }

    MaterialSymbol {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "search"
        iconSize: 18
        color: searchField.activeFocus ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
    }

    IconToolbarButton {
        id: clearButton
        visible: searchField.text.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        text: "close"
        onClicked: root.clearQuery()

        StyledToolTip {
            text: Translation.tr("Clear search")
        }
    }

    Rectangle {
        id: dropdown
        visible: root.dropdownVisible
        anchors.top: parent.bottom
        anchors.topMargin: 8
        anchors.right: parent.right
        width: Math.max(root.width, 390)
        height: root.recommendations.length > 0
            ? Math.min(404, recommendationList.contentHeight + 8)
            : 56
        radius: Appearance.rounding.small
        color: Appearance.colors.colSurfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        ListView {
            id: recommendationList
            visible: root.recommendations.length > 0
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            spacing: 2
            model: root.recommendations
            currentIndex: root.recommendations.length > 0 ? 0 : -1

            delegate: RippleButton {
                required property var modelData
                required property int index

                width: recommendationList.width
                height: 48
                buttonRadius: Appearance.rounding.small
                colBackground: index === recommendationList.currentIndex
                    ? Appearance.colors.colLayer2
                    : "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onHoveredChanged: {
                    if (hovered)
                        recommendationList.currentIndex = index
                }
                onClicked: root.selectResult(modelData)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSecondaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: modelData.icon
                            iconSize: 17
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.pageName
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                        }
                    }

                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: 17
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        StyledText {
            visible: root.recommendations.length === 0
            anchors.centerIn: parent
            text: Translation.tr("No matching settings")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
