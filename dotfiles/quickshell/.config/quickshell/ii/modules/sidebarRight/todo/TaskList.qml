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
    property int tabIndex
    required property var taskList;
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 5
    property int todoListItemPadding: 8
    property int listBottomPadding: 80

    // --- helpers to render due date/time ---
function isoToDDMMYYYY(iso) {
    if (!iso) return "";
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso));
    return m ? (m[3] + "-" + m[2] + "-" + m[1]) : "";
}
function dueLabel(item) {
    const d = isoToDDMMYYYY(item.dueDate);
    const t = item.dueTime || "";
    return [d, t].filter(Boolean).join("  •  ");
}
function isOverdue(item) {
    if (!item || !item.dueDate) return false;
    const when = Date.parse(item.dueDate + "T" + (item.dueTime || "23:59") + ":00");
    return isFinite(when) && when < Date.now() && !item.done;
}


    StyledFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: columnLayout.height

        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: flickable.width
                height: flickable.height
                radius: Appearance.rounding.small
            }
        }

        ColumnLayout {
            id: columnLayout
            width: parent.width
            spacing: 0
            Repeater {
                model: ScriptModel {
                    values: taskList
                }
                delegate: Item {
                    id: todoItem
                    property bool pendingDoneToggle: false
                    property bool pendingDelete: false
                    property bool enableHeightAnimation: false

                    Layout.fillWidth: true
                    implicitHeight: todoItemRectangle.implicitHeight + todoListItemSpacing
                    height: implicitHeight
                    clip: true

                    Behavior on implicitHeight {
                        enabled: enableHeightAnimation
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    function startAction() {
                        enableHeightAnimation = true
                        todoItem.implicitHeight = 0
                        actionTimer.start()
                    }

                    Timer {
                        id: actionTimer
                        interval: Appearance.animation.elementMoveFast.duration
                        repeat: false
                        onTriggered: {
                            const idx = (modelData && modelData.index !== undefined) ? root.taskList.length - 1 - modelData.index : root.taskList.length - 1 - index;

                            if (todoItem.pendingDelete) {
                                Todo.deleteItem(idx, tabIndex)
                            } else if (todoItem.pendingDoneToggle) {
                                if (!modelData.done) Todo.markDone(idx)
                                else Todo.markUnfinished(idx)
                            }
                        }
                    }

                    Rectangle {
                        id: todoItemRectangle
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        implicitHeight: todoContentRowLayout.implicitHeight
                        color: Appearance.colors.colLayer2
                        radius: Appearance.rounding.small
                        ColumnLayout {
                            id: todoContentRowLayout
                            anchors.left: parent.left
                            anchors.right: parent.right

                            StyledText {
                                Layout.fillWidth: true // Needed for wrapping
                                Layout.leftMargin: 10
                                Layout.rightMargin: 10
                                Layout.topMargin: todoListItemPadding
                                id: todoContentText
                                text: modelData.content
                                wrapMode: Text.Wrap
                            }
                            RowLayout {
                                Layout.leftMargin: 10
                                Layout.rightMargin: 10
                                Layout.bottomMargin: todoListItemPadding

                                Item {
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    // put this where the button was
                                    Layout.fillWidth: false
                                    Layout.preferredWidth: 130   // reserve some space so it doesn't disappear
                                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: isOverdue(modelData) ? Appearance.colors.colError
                                                                : Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight

                                    // show DD-MM-YYYY • HH:MM if present
                                    text: {
                                        var d = modelData.dueDate || modelData.date || modelData.due_iso || "";
                                        var t = modelData.dueTime || modelData.time || modelData.due_time || "";
                                        if (d && /^\d{4}-\d{2}-\d{2}$/.test(d))
                                            d = d.slice(8,10) + "-" + d.slice(5,7) + "-" + d.slice(0,4);
                                        if (d && t) return d + " " + t;
                                        if (d) return d;
                                        if (t) return t;
                                        return ""; // nothing set
                                    }
                                }

                                TodoItemActionButton {
                                    Layout.fillWidth: false
                                    onClicked: {
                                        todoItem.pendingDoneToggle = true
                                        todoItem.startAction()
                                    }
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.done ? "remove_done" : "check"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                                TodoItemActionButton {
                                    Layout.fillWidth: false
                                    onClicked: {
                                        todoItem.pendingDelete = true
                                        todoItem.startAction()
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
            // Bottom padding
            Item {
                implicitHeight: listBottomPadding
            }
        }
    }
    
    Item { // Placeholder when list is empty
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