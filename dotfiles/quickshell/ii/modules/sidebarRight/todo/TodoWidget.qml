import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    property int currentTab: 0
    // Tabs renamed: Events, Tasks
    property var tabButtonList: [
        {"icon": "event",      "name": Translation.tr("Events")},
        {"icon": "checklist",  "name": Translation.tr("Tasks")}
    ]
    property bool showAddDialog: false
    property int dialogMargins: 20
    property int fabSize: 48
    property int fabMargins: 14

    // -------- Betterbird scan wiring --------
    property string pythonCmd: "/usr/bin/python3"
    property string scanScript: "/home/linmax/.config/quickshell/ii/modules/sidebarRight/todo/bb_scan.py"

    property var bbEventsList: []   // mapped for TaskList (uses `name` as title)
    property var bbTasksList:  []   // mapped for TaskList (uses `name` as title)

    // map payload items to what TaskList expects; make sure `name` exists
    function mapForTaskListItem(title, subtitle, done, index) {
        const t = (title || "").trim();
        const s = (subtitle || "").trim();

        // Splits date into first and second element
        var first, second;
        var i = s.indexOf(" ");
        if (i === -1) {
            first  = s;     // no space
            second = "";
        } else {
            first  = s.slice(0, i);
            second = s.slice(i + 1); // the rest of the string
        }

        return {
            content: t,
            date: first,
            time: second,
            index: index,

            done: !!done,
        };
    }

    // run scanner
    property string _buf: ""
    Process {
        id: scanProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: { root._buf += (data || "") + "\n"; }
        }
        onExited: (code) => {
            const txt = root._buf || "";
            const s = txt.indexOf("{"), e = txt.lastIndexOf("}");
            let payload = {};
            if (s >= 0 && e >= s) {
                try { payload = JSON.parse(txt.slice(s, e+1)); } catch(_) { payload = {}; }
            }

            // events
            const ev = (payload.events || []).slice();
            ev.sort(function(a,b){
                const ad = a.whenMs == null ? Infinity : a.whenMs;
                const bd = b.whenMs == null ? Infinity : b.whenMs;
                if (ad !== bd) return ad - bd;
                return String(a.title||"").localeCompare(String(b.title||""));
            });
            bbEventsList = ev.map(function(e,i){
                return mapForTaskListItem(e.title || Translation.tr("(No title)"),
                                          e.whenStr || "",
                                          false, i);
            });

            // tasks (show all; if you only want open, filter `!t.done`)
            const ts = (payload.tasks || []).slice();
            ts.sort(function(a,b){
                const ad = a.dueMs == null ? Infinity : a.dueMs;
                const bd = b.dueMs == null ? Infinity : b.dueMs;
                if (ad !== bd) return ad - bd;
                return String(a.title||"").localeCompare(String(b.title||""));
            });
            bbTasksList = ts.map(function(t,i){
                return mapForTaskListItem(t.title || Translation.tr("(No title)"),
                                          t.dueStr || "",
                                          !!t.done, i);
            });
        }
    }

    function refreshFromBetterbird() {
        _buf = "";
        scanProc.command = [pythonCmd, scanScript, "--json"];
        scanProc.running = false;
        scanProc.running = true;
    }

    // -------- Keys --------
    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                currentTab = Math.min(currentTab + 1, root.tabButtonList.length - 1)
            } else if (event.key === Qt.Key_PageUp) {
                currentTab = Math.max(currentTab - 1, 0)
            }
            event.accepted = true;
        }
        // Open add dialog on "N" (any modifiers)
        else if (event.key === Qt.Key_N) {
            root.showAddDialog = true
            event.accepted = true;
        }
        // Close dialog on Esc if open
        else if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false
            event.accepted = true;
        }
    }

    function setDateTimeToNow() {
        var now = new Date();
        todoDate.text    = Qt.formatDate(now, "dd-MM-yyyy");
        todoHours.text   = Qt.formatTime(now, "HH");
        todoMinutes.text = Qt.formatTime(now, "mm");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            currentIndex: currentTab
            onCurrentIndexChanged: currentTab = currentIndex

            background: Item {
                WheelHandler {
                    onWheel: (event) => {
                        if (event.angleDelta.y < 0)
                            tabBar.currentIndex = Math.min(tabBar.currentIndex + 1, root.tabButtonList.length - 1)
                        else if (event.angleDelta.y > 0)
                            tabBar.currentIndex = Math.max(tabBar.currentIndex - 1, 0)
                    }
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                }
            }

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    selected: (index == currentTab)
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        Item { // Tab indicator
            id: tabIndicator
            Layout.fillWidth: true
            height: 3
            property bool enableIndicatorAnimation: false
            Connections {
                target: root
                function onCurrentTabChanged() { tabIndicator.enableIndicatorAnimation = true }
            }

            Rectangle {
                id: indicator
                property int tabCount: root.tabButtonList.length
                property real fullTabSize: root.width / tabCount
                property real targetWidth: tabBar.contentItem.children[0].children[tabBar.currentIndex].tabContentWidth

                implicitWidth: targetWidth
                anchors { top: parent.top; bottom: parent.bottom }
                x: tabBar.currentIndex * fullTabSize + (fullTabSize - targetWidth) / 2

                color: Appearance.colors.colPrimary
                radius: Appearance.rounding.full

                Behavior on x {
                    enabled: tabIndicator.enableIndicatorAnimation
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on implicitWidth {
                    enabled: tabIndicator.enableIndicatorAnimation
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }

        Rectangle { // Tabbar bottom border
            Layout.fillWidth: true
            height: 1
            color: Appearance.colors.colOutlineVariant
        }

        SwipeView {
            id: swipeView
            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            currentIndex: currentTab
            onCurrentIndexChanged: {
                tabIndicator.enableIndicatorAnimation = true
                currentTab = currentIndex
            }

            // Page 0: EVENTS (from Betterbird events)
            TaskList {
                tabIndex: 0
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "event"
                emptyPlaceholderText: Translation.tr("No events")
                taskList: bbEventsList   // each item has `name` as the title
            }

            // Page 1: TASKS (from Betterbird tasks)
            TaskList {
                tabIndex: 1
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("No tasks")
                taskList: bbTasksList    // each item has `name` as the title
            }
        }
    }

    // + FAB (kept as-is; opens your add dialog)
    StyledRectangularShadow {
        target: fabButton
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    FloatingActionButton {
        id: fabButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins

        onClicked: {
            
            root.showAddDialog = true
            setDateTimeToNow()
        }

        contentItem: MaterialSymbol {
            text: "add"
            horizontalAlignment: Text.AlignHCenter
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.m3colors.m3onPrimaryContainer
        }
    }

    // ===== ADD DIALOG (unchanged visuals) =====
    Item {
        anchors.fill: parent
        z: 9999
        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) {
                todoInput.text = ""
                fabButton.focus = true
            }
        }

        Rectangle { anchors.fill: parent; radius: Appearance.rounding.small; color: Appearance.colors.colScrim }

        Rectangle { // The dialog
            id: dialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: dialogColumnLayout.implicitHeight
            color: Appearance.colors.colSurfaceContainerHigh
            radius: Appearance.rounding.normal

            function addTask() {
                if (todoInput.text.length > 0) {
                    // This still writes to your local Todo model
                    Todo.addTask(todoInput.text, todoDate.text, todoHours.text + todoMinutes.text)
                    todoInput.text = ""
                    root.showAddDialog = false
                    root.currentTab = 1 // land on "Tasks"
                }
            }

            ColumnLayout {
                id: dialogColumnLayout
                anchors.fill: parent
                spacing: 16

                StyledText {
                    Layout.topMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignLeft
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Add task")
                }

                TextField {
                    id: todoInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    renderType: Text.NativeRendering
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Task description")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    focus: root.showAddDialog
                    onAccepted: dialog.addTask()

                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: todoInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }
                    cursorDelegate: Rectangle {
                        width: 1
                        color: todoInput.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }
                }

                RowLayout {
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    spacing: 8

                    // Date (DD-MM-YYYY)
                    TextField {
                        id: todoDate
                        Layout.preferredWidth: 125
                        padding: 10
                        placeholderText: "DD-MM-YYYY"
                        maximumLength: 10
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        renderType: Text.NativeRendering
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer

                        onTextChanged: {
                            var r = text.replace(/[^0-9-]/g, "");
                            r = r.replace(/-/g, "");
                            if (r.length > 2)  r = r.slice(0,2) + "-" + r.slice(2);
                            if (r.length > 5)  r = r.slice(0,5) + "-" + r.slice(5);
                            if (r.length > 10) r = r.slice(0,10);
                            if (r !== text) text = r;
                        }
                        onAccepted: todoHours.forceActiveFocus()

                        background: Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.verysmall
                            border.width: 2
                            border.color: todoDate.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                            color: "transparent"
                        }
                        cursorDelegate: Rectangle {
                            width: 1
                            color: todoDate.activeFocus ? Appearance.colors.colPrimary : "transparent"
                            radius: 1
                        }
                    }

                    // Hours (00–23)
                    TextField {
                        id: todoHours
                        Layout.preferredWidth: 50
                        padding: 10
                        placeholderText: "HH"
                        maximumLength: 2
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 0; top: 23 }
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        renderType: Text.NativeRendering
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer

                        onTextChanged: { text = text.replace(/[^0-9]/g, "") }
                        onAccepted: todoMinutes.forceActiveFocus()

                        background: Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.verysmall
                            border.width: 2
                            border.color: todoHours.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                            color: "transparent"
                        }
                        cursorDelegate: Rectangle {
                            width: 1
                            color: todoHours.activeFocus ? Appearance.colors.colPrimary : "transparent"
                            radius: 1
                        }
                    }

                    StyledText {
                        text: ":"
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }

                    // Minutes (00–59)
                    TextField {
                        id: todoMinutes
                        Layout.preferredWidth: 50
                        padding: 10
                        placeholderText: "MM"
                        maximumLength: 2
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 0; top: 59 }
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        renderType: Text.NativeRendering
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer

                        onTextChanged: { text = text.replace(/[^0-9]/g, "") }
                        onAccepted: dialog.addTask()

                        background: Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.verysmall
                            border.width: 2
                            border.color: todoMinutes.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                            color: "transparent"
                        }
                        cursorDelegate: Rectangle {
                            width: 1
                            color: todoMinutes.activeFocus ? Appearance.colors.colPrimary : "transparent"
                            radius: 1
                        }
                    }
                }

                RowLayout {
                    Layout.bottomMargin: 16
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.alignment: Qt.AlignRight
                    spacing: 5

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showAddDialog = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: todoInput.text.length > 0
                        onClicked: dialog.addTask()
                    }
                }
            }
        }
    }

    // initial load from Betterbird
    Component.onCompleted: refreshFromBetterbird()
}
