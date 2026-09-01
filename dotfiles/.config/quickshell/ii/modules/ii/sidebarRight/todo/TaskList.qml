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
    property string readOnlyActionIcon: ""
    signal itemActivated(var item)
    signal readOnlyAction(var item)

    function isQuickMailTask(task) {
        return `${task?.source ?? ""}` === "quickmail-task"
            && `${task?.kind ?? "task"}` === "task"
            && `${task?.id ?? ""}`.length > 0;
    }

    function isDateOnlyTask(task) {
        if (task?.dateOnly === true)
            return true;
        if (`${task?.source ?? ""}` !== "quickmail-task")
            return false;
        return /gmail|google/.test(`${task?.provider ?? ""}`.toLowerCase());
    }

    function dateOnlyDisplayDate(timestamp) {
        const utcDate = new Date(timestamp);
        // Reconstruct a local calendar date from UTC fields before formatting.
        // Noon avoids DST transitions at midnight without changing the date.
        return new Date(utcDate.getUTCFullYear(), utcDate.getUTCMonth(), utcDate.getUTCDate(), 12, 0, 0, 0);
    }

    function itemMatchesHighlight(task) {
        if (root.highlightDayStartMs < 0 || root.highlightDayEndMs <= root.highlightDayStartMs)
            return false;
        const dueAt = parseInt(task?.dueAt ?? 0) || 0;
        if (root.isDateOnlyTask(task) && dueAt > 0) {
            const dueDate = new Date(dueAt);
            const highlightDate = new Date(root.highlightDayStartMs);
            return dueDate.getUTCFullYear() === highlightDate.getFullYear()
                && dueDate.getUTCMonth() === highlightDate.getMonth()
                && dueDate.getUTCDate() === highlightDate.getDate();
        }
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
        if (root.isDateOnlyTask(task))
            return true;
        // QuickMail's Microsoft tasks retain a real time, including 00:00.
        // Only legacy provider-less read-only rows use the midnight heuristic.
        if (`${task?.source ?? ""}` === "quickmail-task")
            return false;
        if (!task?.readOnly)
            return false;
        return dueDate.getHours() === 0
            && dueDate.getMinutes() === 0
            && dueDate.getSeconds() === 0
            && dueDate.getMilliseconds() === 0;
    }

    function formatDueLabel(task) {
        const dueAt = parseInt(task?.dueAt ?? 0);
        if (!dueAt || dueAt <= 0) return "";
        const dueDate = new Date(dueAt);
        const dateOnly = root.isDateOnlyTask(task);
        const displayDate = dateOnly ? root.dateOnlyDisplayDate(dueAt) : dueDate;
        const datePart = displayDate.toLocaleDateString(Translation.locale, "dd MMM");
        if (dateOnly) {
            const today = new Date();
            const todayDateOnly = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate(), 0, 0, 0, 0);
            return dueAt < todayDateOnly
                ? Translation.tr("Overdue: %1").arg(datePart)
                : Translation.tr("Due date: %1").arg(datePart);
        }
        const timePart = root.isAllDayTask(task, dueDate)
            ? "--:--"
            : dueDate.toLocaleTimeString(Translation.locale, "HH:mm");
        if (task?.source === "local") {
            const now = new Date();
            const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
            const tomorrowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime();
            const dayAfterStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 2).getTime();
            const relativeDate = dueAt >= todayStart && dueAt < tomorrowStart
                ? Translation.tr("Today")
                : dueAt >= tomorrowStart && dueAt < dayAfterStart
                    ? Translation.tr("Tomorrow")
                    : datePart;
            return dueAt < Date.now()
                ? Translation.tr("Overdue: %1").arg(`${relativeDate}, ${timePart}`)
                : Translation.tr("Due: %1").arg(`${relativeDate}, ${timePart}`);
        }
        return task?.source === "mail"
            ? Translation.tr("Received: %1").arg(`${datePart}, ${timePart}`)
            : task?.kind === "event"
            ? Translation.tr("Starts: %1").arg(`${datePart}, ${timePart}`)
            : Translation.tr("Due: %1").arg(`${datePart}, ${timePart}`);
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
            readonly property bool accentHighlighted: root.accentHighlightMatches && todoItem.highlighted && !todoItem.selected
            readonly property color foregroundColor: todoItem.selected
                ? Appearance.colors.colOnPrimary
                : todoItem.accentHighlighted
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colOnLayer1
            readonly property color mutedForegroundColor: todoItem.selected
                ? Appearance.colors.colOnPrimary
                : todoItem.accentHighlighted
                    ? Appearance.colors.colOnPrimaryContainer
                    : Appearance.colors.colSubtext

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
                color: todoItem.selected
                    ? Appearance.colors.colPrimary
                    : todoItem.accentHighlighted
                        ? Appearance.colors.colPrimaryContainer
                        : todoItem.highlighted
                            ? Appearance.colors.colSecondaryContainer
                        : Appearance.colors.colLayer2
                radius: Appearance.rounding.small
                border.width: todoItem.accentHighlighted ? 1 : 0
                border.color: Appearance.colors.colPrimary

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
                        color: todoItem.foregroundColor
                        font.weight: todoItem.modelData.description ? Font.DemiBold : Font.Normal
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        visible: `${todoItem.modelData.description ?? ""}`.trim().length > 0
                        text: `${todoItem.modelData.description ?? ""}`
                        wrapMode: Text.Wrap
                        color: todoItem.foregroundColor
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        visible: text.length > 0
                        text: root.formatDueLabel(todoItem.modelData)
                        color: todoItem.selected || todoItem.accentHighlighted
                            ? todoItem.mutedForegroundColor
                            : todoItem.modelData.source === "local"
                                && (parseInt(todoItem.modelData.dueAt ?? 0) || 0) > 0
                                && (parseInt(todoItem.modelData.dueAt ?? 0) || 0) < Date.now()
                                ? Appearance.colors.colError
                            : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        visible: !!todoItem.modelData.readOnly || root.isQuickMailTask(todoItem.modelData)
                        text: {
                            const sourceName = `${todoItem.modelData.calendarName ?? ""}`.trim();
                            if (todoItem.modelData.source === "mail")
                                return Translation.tr("Mail: %1").arg(todoItem.modelData.account ?? "QuickMail");
                            if (root.isQuickMailTask(todoItem.modelData))
                                return Translation.tr("QuickMail: %1").arg(
                                    todoItem.modelData.account || todoItem.modelData.provider || "QuickMail"
                                );
                            return sourceName.length > 0
                                ? Translation.tr("Source: %1 (read-only)").arg(sourceName)
                                : Translation.tr("Source: QuickMail (read-only)");
                        }
                        color: todoItem.mutedForegroundColor
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
                            visible: !!todoItem.modelData.readOnly && root.readOnlyActionIcon.length > 0
                            onClicked: root.readOnlyAction(todoItem.modelData)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: root.readOnlyActionIcon
                                iconSize: Appearance.font.pixelSize.larger
                                color: todoItem.foregroundColor
                            }
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            visible: !(root.hideActionsForReadOnly && todoItem.modelData.readOnly)
                            enabled: !root.isQuickMailTask(todoItem.modelData) || !UnifiedAgenda.mutationBusy
                            onClicked: {
                                if (root.isQuickMailTask(todoItem.modelData)) {
                                    UnifiedAgenda.completeRemoteTask(
                                        todoItem.modelData.id,
                                        !todoItem.modelData.done
                                    );
                                } else if (!todoItem.modelData.done) {
                                    Todo.markDone(todoItem.modelData.originalIndex);
                                } else {
                                    Todo.markUnfinished(todoItem.modelData.originalIndex);
                                }
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: todoItem.modelData.done ? "remove_done" : "check"
                                iconSize: Appearance.font.pixelSize.larger
                                color: todoItem.foregroundColor
                            }
                        }
                        TodoItemActionButton {
                            Layout.fillWidth: false
                            visible: !(root.hideActionsForReadOnly && todoItem.modelData.readOnly)
                            enabled: !root.isQuickMailTask(todoItem.modelData) || !UnifiedAgenda.mutationBusy
                            onClicked: {
                                if (root.isQuickMailTask(todoItem.modelData))
                                    UnifiedAgenda.deleteRemoteTask(todoItem.modelData.id);
                                else
                                    Todo.deleteItem(todoItem.modelData.originalIndex);
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "delete_forever"
                                iconSize: Appearance.font.pixelSize.larger
                                color: todoItem.foregroundColor
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
