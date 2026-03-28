import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 5
    property int todoListItemPadding: 8
    property int listBottomPadding: 80
    property bool hideActionsForReadOnly: true
    property real highlightDayStartMs: -1
    property real highlightDayEndMs: -1
    property bool autoScrollToHighlight: false
    property bool accentHighlightMatches: false
    property bool selectionEnabled: false
    property string selectedExternalId: ""
    property string selectedCalId: ""
    signal itemActivated(var item)

    function itemMatchesHighlight(task) {
        if (root.highlightDayStartMs < 0 || root.highlightDayEndMs <= root.highlightDayStartMs)
            return false;
        const dueAt = parseInt(task?.dueAt ?? 0) || 0;
        return dueAt >= root.highlightDayStartMs && dueAt < root.highlightDayEndMs;
    }

    function itemMatchesSelection(task) {
        if (!root.selectionEnabled)
            return false;
        return `${task?.externalId ?? ""}` === root.selectedExternalId
            && `${task?.calId ?? ""}` === root.selectedCalId;
    }

    function scrollToHighlight() {
        if (!root.autoScrollToHighlight || !root.taskList || root.taskList.length === 0)
            return;
        for (let i = 0; i < root.taskList.length; ++i) {
            if (root.itemMatchesHighlight(root.taskList[i])) {
                listView.positionViewAtIndex(i, ListView.Beginning);
                return;
            }
        }
    }

    onTaskListChanged: Qt.callLater(root.scrollToHighlight)
    onHighlightDayStartMsChanged: Qt.callLater(root.scrollToHighlight)

    function isAllDayTask(task, dueDate) {
        if (task?.allDay === true)
            return true;
        if (!(task?.readOnly || task?.source === "thunderbird"))
            return false;
        return dueDate.getHours() === 0
            && dueDate.getMinutes() === 0
            && dueDate.getSeconds() === 0
            && dueDate.getMilliseconds() === 0;
    }

    function formatDueLabel(task) {
        if (task?.source === "local")
            return "";
        const dueAt = parseInt(task?.dueAt ?? 0);
        if (!dueAt || dueAt <= 0) return "";
        const dueDate = new Date(dueAt);
        const datePart = dueDate.toLocaleDateString(Qt.locale(), "dd MMM");
        const timePart = root.isAllDayTask(task, dueDate)
            ? "--:--"
            : dueDate.toLocaleTimeString(Qt.locale(), "HH:mm");
        return Translation.tr("Due: %1").arg(`${datePart}, ${timePart}`);
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: root.todoListItemSpacing
        animateAppearance: false
        model: ScriptModel {
            values: root.taskList
        }
        delegate: Item {
            id: todoItem
            required property var modelData
            property bool pendingDoneToggle: false
            property bool pendingDelete: false
            property bool enableHeightAnimation: false
            readonly property bool highlighted: root.itemMatchesHighlight(todoItem.modelData)
            readonly property bool selected: root.itemMatchesSelection(todoItem.modelData)

            implicitHeight: todoItemRectangle.implicitHeight
            width: ListView.view.width
            clip: true

            Behavior on implicitHeight {
                enabled: enableHeightAnimation
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                id: todoItemRectangle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: todoContentRowLayout.implicitHeight
                color: todoItem.selected || (root.accentHighlightMatches && todoItem.highlighted)
                    ? Appearance.colors.colPrimary
                    : todoItem.highlighted
                        ? Appearance.colors.colSecondaryContainer
                        : Appearance.colors.colLayer2
                radius: Appearance.rounding.small

                MouseArea {
                    anchors.fill: parent
                    enabled: root.selectionEnabled
                    onClicked: root.itemActivated(todoItem.modelData)
                }

                ColumnLayout {
                    id: todoContentRowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right

                    StyledText {
                        id: todoContentText
                        Layout.fillWidth: true // Needed for wrapping
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.topMargin: todoListItemPadding
                        text: `${todoItem.modelData.title ?? todoItem.modelData.content ?? ""}`
                        wrapMode: Text.Wrap
                        color: (todoItem.selected || (root.accentHighlightMatches && todoItem.highlighted))
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer1
                        font.weight: todoItem.modelData.description ? Font.DemiBold : Font.Normal
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        visible: `${todoItem.modelData.description ?? ""}`.trim().length > 0
                        text: `${todoItem.modelData.description ?? ""}`
                        wrapMode: Text.Wrap
                        color: (todoItem.selected || (root.accentHighlightMatches && todoItem.highlighted))
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        visible: text.length > 0
                        text: root.formatDueLabel(todoItem.modelData)
                        color: (todoItem.selected || (root.accentHighlightMatches && todoItem.highlighted))
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        visible: !!todoItem.modelData.readOnly
                        text: {
                            const sourceName = `${todoItem.modelData.calendarName ?? ""}`.trim();
                            return sourceName.length > 0
                                ? Translation.tr("Source: %1 (read-only)").arg(sourceName)
                                : Translation.tr("Source: Thunderbird (read-only)");
                        }
                        color: (todoItem.selected || (root.accentHighlightMatches && todoItem.highlighted))
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    RowLayout {
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.bottomMargin: todoListItemPadding
                        Item {
                            Layout.fillWidth: true
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            visible: !(root.hideActionsForReadOnly && todoItem.modelData.readOnly)
                            onClicked: {
                                if (!todoItem.modelData.done)
                                    Todo.markDone(todoItem.modelData.originalIndex);
                                else
                                    Todo.markUnfinished(todoItem.modelData.originalIndex);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: todoItem.modelData.done ? "remove_done" : "check"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            visible: !(root.hideActionsForReadOnly && todoItem.modelData.readOnly)
                            onClicked: {
                                Todo.deleteItem(todoItem.modelData.originalIndex);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "delete_forever"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: emptyPlaceholderText
            }
        }
    }
}
