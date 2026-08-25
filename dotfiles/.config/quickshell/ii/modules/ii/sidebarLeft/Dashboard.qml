import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property var headlines: []
    property var quotes: []
    property bool newsLoading: false
    property bool marketsLoading: false

    function cleanTitle(value) {
        return String(value || "").replace(/<!\[CDATA\[|\]\]>/g, "").replace(/<[^>]*>/g, "").replace(/&amp;/g, "&").replace(/&quot;/g, "\"").trim()
    }

    function fetchNews() {
        const feed = Config.options.sidebar.dashboard.newsFeed.trim()
        if (!feed.length || newsLoading) return
        newsLoading = true
        newsFetcher.command = ["curl", "-L", "-s", "--max-time", "15", feed]
        newsFetcher.running = true
    }

    function fetchMarkets() {
        const symbols = Config.options.sidebar.dashboard.stockSymbols.split(",")
            .map(symbol => symbol.trim().toLowerCase())
            .filter(symbol => /^[a-z0-9.^-]+$/.test(symbol))
        if (!symbols.length || marketsLoading) return
        marketsLoading = true
        marketFetcher.command = ["curl", "-s", "--max-time", "15", "https://stooq.com/q/l/?s=" + encodeURIComponent(symbols.join(",")) + "&i=d"]
        marketFetcher.running = true
    }

    function refresh() {
        if (Config.options.sidebar.dashboard.showWeather)
            Weather.getData()
        if (Config.options.sidebar.dashboard.showNews)
            fetchNews()
        if (Config.options.sidebar.dashboard.showMarkets)
            fetchMarkets()
    }

    Component.onCompleted: refresh()

    Process {
        id: newsFetcher
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const result = []
                const itemPattern = /<item>([\s\S]*?)<\/item>/g
                let match
                while ((match = itemPattern.exec(text)) !== null && result.length < 6) {
                    const titleMatch = /<title>([\s\S]*?)<\/title>/.exec(match[1])
                    const linkMatch = /<link>([\s\S]*?)<\/link>/.exec(match[1])
                    const title = root.cleanTitle(titleMatch?.[1])
                    const link = root.cleanTitle(linkMatch?.[1])
                    if (title.length && /^https?:\/\//.test(link))
                        result.push({ title: title, link: link })
                }
                root.headlines = result
                root.newsLoading = false
            }
        }
        onExited: {
            if (!running) root.newsLoading = false
        }
    }

    Process {
        id: marketFetcher
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = text.trim().split(/\r?\n/)
                const result = []
                for (let i = 1; i < rows.length; i++) {
                    const cells = rows[i].split(",")
                    if (cells.length < 7) continue
                    const open = Number(cells[4])
                    const close = Number(cells[6])
                    if (!Number.isFinite(close)) continue
                    const change = Number.isFinite(open) && open !== 0 ? ((close - open) / open * 100) : NaN
                    result.push({ symbol: cells[0].toUpperCase(), close: close, change: change })
                }
                root.quotes = result
                root.marketsLoading = false
            }
        }
        onExited: {
            if (!running) root.marketsLoading = false
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: content
            width: parent.width
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 12
                StyledText {
                    text: Translation.tr("Overview")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    onClicked: root.refresh()
                    contentItem: MaterialSymbol { text: "refresh"; anchors.centerIn: parent; iconSize: Appearance.font.pixelSize.large }
                    StyledToolTip { text: Translation.tr("Refresh") }
                }
            }

            Rectangle {
                visible: Config.options.sidebar.dashboard.showWeather
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                implicitHeight: weatherRow.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSurfaceContainerHigh
                RowLayout {
                    id: weatherRow
                    anchors { fill: parent; margins: 12 }
                    MaterialSymbol { text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"; iconSize: 38; color: Appearance.colors.colPrimary }
                    ColumnLayout {
                        Layout.fillWidth: true
                        StyledText { text: Weather.data.city || Translation.tr("Weather"); font.weight: Font.Medium }
                        StyledText { text: Weather.data.temp + " • " + Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
                    }
                    StyledText { text: Weather.data.humidity; color: Appearance.colors.colSubtext }
                }
            }

            DashboardHeading { visible: Config.options.sidebar.dashboard.showNews; icon: "newspaper"; text: Translation.tr("Top news"); loading: root.newsLoading }
            Repeater {
                model: Config.options.sidebar.dashboard.showNews ? root.headlines : []
                delegate: RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    implicitHeight: headlineText.implicitHeight + 18
                    onClicked: Qt.openUrlExternally(modelData.link)
                    contentItem: StyledText {
                        id: headlineText
                        anchors { fill: parent; margins: 9 }
                        text: modelData.title
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
            StyledText { visible: Config.options.sidebar.dashboard.showNews && !root.newsLoading && root.headlines.length === 0; Layout.leftMargin: 12; text: Translation.tr("No headlines available."); color: Appearance.colors.colSubtext }

            DashboardHeading { visible: Config.options.sidebar.dashboard.showMarkets; icon: "show_chart"; text: Translation.tr("Markets"); loading: root.marketsLoading }
            Repeater {
                model: Config.options.sidebar.dashboard.showMarkets ? root.quotes : []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    implicitHeight: 44
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainerHigh
                    RowLayout {
                        anchors { fill: parent; margins: 10 }
                        StyledText { text: modelData.symbol; font.weight: Font.Medium; Layout.fillWidth: true }
                        StyledText { text: modelData.close.toFixed(2) }
                        StyledText { text: Number.isFinite(modelData.change) ? (modelData.change >= 0 ? "+" : "") + modelData.change.toFixed(2) + "%" : "--"; color: Number.isFinite(modelData.change) && modelData.change < 0 ? Appearance.colors.colError : Appearance.colors.colPrimary }
                    }
                }
            }
            StyledText { visible: Config.options.sidebar.dashboard.showMarkets && !root.marketsLoading && root.quotes.length === 0; Layout.leftMargin: 12; text: Translation.tr("No market quotes available."); color: Appearance.colors.colSubtext }
        }
    }

    component DashboardHeading: RowLayout {
        property string icon
        property string text
        property bool loading: false
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        MaterialSymbol { text: parent.icon; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colPrimary }
        StyledText { text: parent.text; font.weight: Font.DemiBold; Layout.fillWidth: true }
        BusyIndicator { visible: parent.loading; implicitWidth: 20; implicitHeight: 20 }
    }
}
