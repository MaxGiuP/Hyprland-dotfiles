import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: (Config.options?.policies?.ai ?? 1) !== 0
    property bool translatorEnabled: Config.options?.sidebar?.translator?.enable ?? false
    property var tabButtonList: [
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": "", "title": Translation.tr("Intelligence")}] : []),
        ...(root.translatorEnabled ? [{"icon": "translate", "name": "", "title": Translation.tr("Translator")}] : []),
        {"icon": "calculate", "name": "", "title": Translation.tr("Calculator")},
        {"icon": "smartphone", "name": "", "title": Translation.tr("KDE Connect")},
        {"icon": "terminal", "name": "", "title": Translation.tr("Console")},
    ]
    property int tabCount: swipeView.count

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        Toolbar {
            visible: tabButtonList.length > 0
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                currentIndex: swipeView.currentIndex
                delegate: ToolbarTabButton {
                    required property int index
                    required property var modelData
                    current: index == tabBar.currentIndex
                    text: modelData.name
                    materialSymbol: modelData.icon
                    horizontalPadding: 7
                    onClicked: {
                        tabBar.setCurrentIndex(index);
                        root.focusActiveItem();
                    }
                    StyledToolTip {
                        text: modelData.title
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: tabBar.currentIndex

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                contentChildren: [
                    ...(root.aiChatEnabled ? [aiChat.createObject()] : []),
                    ...(root.translatorEnabled ? [translator.createObject()] : []),
                    calculatorTab.createObject(),
                    kdeConnectTab.createObject(),
                    consoleTab.createObject(),
                    ...(root.tabButtonList.length === 0 ? [placeholder.createObject()] : []),
                ]
            }
        }

        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: consoleTab
            ShellConsole {}
        }
        Component {
            id: kdeConnectTab
            KdeConnect {}
        }
        Component {
            id: calculatorTab
            Calculator {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
