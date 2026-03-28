//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env II_STANDALONE_APP=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ApplicationWindow {
    id: root

    property real contentPadding: 8
    property bool navExpanded: width > 900
    property var pages: [
        { name: Translation.tr("Home"), icon: "home" },
        { name: Translation.tr("Audio"), icon: "volume_up" }
    ]
    property int currentPage: 0
    readonly property var navEntries: pages.map((page, index) => ({ isHeader: false, pageIndex: index, page: page }))
    readonly property var pageYOffsets: [0, 48]

    visible: true
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background
    title: "smoke-settings-shell"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.contentPadding

        Item {
            id: titlebar
            readonly property bool showTitlebar: Config.options?.windows?.showTitlebar ?? true
            readonly property bool centerTitle: Config.options?.windows?.centerTitle ?? false

            visible: showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)

            StyledText {
                id: titleText
                useDefaultVariableAxes: false
                anchors {
                    left: titlebar.centerTitle ? undefined : parent.left
                    horizontalCenter: titlebar.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.title
            }

            RowLayout {
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right

                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: root.navExpanded ? 170 : 68
                clip: true
                radius: Appearance.rounding.windowRounding - root.contentPadding
                color: Appearance.m3colors.m3surfaceContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    RippleButton {
                        Layout.alignment: Qt.AlignLeft
                        implicitWidth: 40
                        implicitHeight: 40
                        Layout.leftMargin: 4
                        buttonRadius: Appearance.rounding.full
                        downAction: () => root.navExpanded = !root.navExpanded

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: 24
                            color: Appearance.colors.colOnLayer1
                            text: root.navExpanded ? "menu_open" : "menu"
                        }
                    }

                    StyledFlickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: navItems.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Item {
                            id: navItems
                            width: parent.width
                            implicitHeight: navColumn.implicitHeight

                            Rectangle {
                                y: root.pageYOffsets[root.currentPage] ?? 0
                                width: parent.width
                                height: 48
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colSecondaryContainer
                            }

                            Column {
                                id: navColumn
                                width: parent.width
                                spacing: 0

                                Repeater {
                                    model: root.navEntries

                                    delegate: RippleButton {
                                        required property var modelData
                                        width: parent.width
                                        height: 48
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: "transparent"
                                        downAction: () => root.currentPage = modelData.pageIndex

                                        contentItem: Item {
                                            anchors.fill: parent

                                            MaterialSymbol {
                                                id: navIcon
                                                anchors.left: parent.left
                                                anchors.leftMargin: 16
                                                anchors.verticalCenter: parent.verticalCenter
                                                iconSize: 22
                                                fill: root.currentPage === modelData.pageIndex ? 1 : 0
                                                text: modelData.page.icon
                                                color: root.currentPage === modelData.pageIndex
                                                    ? Appearance.m3colors.m3onSecondaryContainer
                                                    : Appearance.colors.colOnLayer1
                                            }

                                            StyledText {
                                                anchors.left: navIcon.right
                                                anchors.leftMargin: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: root.navExpanded
                                                text: modelData.page.name
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                color: root.currentPage === modelData.pageIndex
                                                    ? Appearance.m3colors.m3onSecondaryContainer
                                                    : Appearance.colors.colOnLayer1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding
            }
        }
    }
}
