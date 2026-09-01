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
    focus: true
    property var tabButtonList: [
        {"name": Translation.tr("Todo"), "icon": "checklist"},
        {"name": Translation.tr("Completed"), "icon": "done_all"}
    ]
    property bool showAddDialog: false
    property int dialogMargins: 8
    property int fabSize: 38
    property int fabMargins: 10
    property bool dueEnabled: false
    property int selectedDestinationIndex: 0
    readonly property var taskDestinations: [{
        id: "",
        displayName: Translation.tr("Local device"),
        provider: "local",
        icon: "devices",
        remote: false,
    }].concat(UnifiedAgenda.writableTaskDestinations)
    readonly property var selectedDestination: root.taskDestinations[Math.max(0, Math.min(root.selectedDestinationIndex, root.taskDestinations.length - 1))]
    readonly property bool remoteDestinationSelected: !!root.selectedDestination?.remote
    readonly property bool dateOnlyDueDestination: root.remoteDestinationSelected && !!root.selectedDestination?.dateOnlyDue
    readonly property bool dueInputValid: !root.dueEnabled || root.parseDueAt() > 0
    readonly property var localTodoList: {
        return Todo.list.map((item, i) => Object.assign({}, item, {
            originalIndex: i,
            readOnly: false,
            source: "local",
        })).filter(item => !item.done).sort((a, b) => {
            const aDue = parseInt(a?.dueAt ?? 0) || 0;
            const bDue = parseInt(b?.dueAt ?? 0) || 0;
            if (aDue > 0 && bDue <= 0) return -1;
            if (bDue > 0 && aDue <= 0) return 1;
            if (aDue > 0 && bDue > 0 && aDue !== bDue) return aDue - bDue;
            const aCreated = parseInt(a?.createdAt ?? 0) || 0;
            const bCreated = parseInt(b?.createdAt ?? 0) || 0;
            if (aCreated !== bCreated) return bCreated - aCreated;
            return `${a.title ?? a.content}`.localeCompare(`${b.title ?? b.content}`);
        });
    }
    readonly property var localCompletedList: {
        return Todo.list.map((item, i) => Object.assign({}, item, {
            originalIndex: i,
            readOnly: false,
            source: "local",
        })).sort((a, b) => {
            if (!!a.done !== !!b.done) return a.done ? -1 : 1;
            const aCreated = parseInt(a?.createdAt ?? 0) || 0;
            const bCreated = parseInt(b?.createdAt ?? 0) || 0;
            if (aCreated !== bCreated) return bCreated - aCreated;
            return `${a.title ?? a.content}`.localeCompare(`${b.title ?? b.content}`);
        }).filter(item => !!item.done);
    }

    function openAddDialog() {
        root.resetComposer();
        root.showAddDialog = true;
        GlobalStates.newTaskRequested = false;
        Qt.callLater(() => titleInput.forceActiveFocus());
    }

    Component.onCompleted: {
        if (GlobalStates.newTaskRequested)
            root.openAddDialog();
    }

    Connections {
        target: GlobalStates
        function onNewTaskRequestedChanged() {
            if (GlobalStates.newTaskRequested)
                root.openAddDialog();
        }
    }

    onTaskDestinationsChanged: {
        if (root.selectedDestinationIndex >= root.taskDestinations.length)
            root.selectedDestinationIndex = 0;
    }

    function resetComposer() {
        titleInput.text = "";
        descriptionInput.text = "";
        root.dueEnabled = false;
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        dueDateInput.text = Qt.formatDate(tomorrow, "yyyy-MM-dd");
        dueTimeInput.text = "09:00";
    }

    function setDuePreset(daysFromToday) {
        const dueDate = new Date();
        dueDate.setDate(dueDate.getDate() + daysFromToday);
        root.dueEnabled = true;
        dueDateInput.text = Qt.formatDate(dueDate, "yyyy-MM-dd");
        if (dueTimeInput.text.trim().length === 0)
            dueTimeInput.text = "09:00";
    }

    function parseDateOnlyDueAt(year, month, day) {
        const timestamp = Date.UTC(year, month - 1, day, 0, 0, 0, 0);
        const parsedUtc = new Date(timestamp);
        if (parsedUtc.getUTCFullYear() !== year
            || parsedUtc.getUTCMonth() !== month - 1
            || parsedUtc.getUTCDate() !== day)
            return -1;
        return timestamp;
    }

    function parseDueAt() {
        if (!root.dueEnabled)
            return 0;
        const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dueDateInput.text.trim());
        const timeMatch = /^(\d{1,2}):(\d{2})$/.exec(dueTimeInput.text.trim());
        if (!dateMatch || (!root.dateOnlyDueDestination && !timeMatch))
            return -1;
        const year = parseInt(dateMatch[1]);
        const month = parseInt(dateMatch[2]);
        const day = parseInt(dateMatch[3]);
        if (month < 1 || month > 12 || day < 1 || day > 31)
            return -1;

        // Google Tasks persists due.date_naive() in UTC. Keep the selected
        // calendar date canonical at UTC midnight so UTC+ offsets cannot move
        // it to the previous day before QuickMail sends it to the provider.
        if (root.dateOnlyDueDestination)
            return root.parseDateOnlyDueAt(year, month, day);

        const hour = parseInt(timeMatch[1]);
        const minute = parseInt(timeMatch[2]);
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59)
            return -1;
        const parsed = new Date(year, month - 1, day, hour, minute, 0, 0);
        if (parsed.getFullYear() !== year || parsed.getMonth() !== month - 1 || parsed.getDate() !== day)
            return -1;
        return parsed.getTime();
    }

    onShowAddDialogChanged: {
        if (root.showAddDialog)
            Qt.callLater(() => titleInput.forceActiveFocus());
        else {
            root.resetComposer();
            Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false;
            event.accepted = true;
            return;
        }
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                tabBar.incrementCurrentIndex();
            } else if (event.key === Qt.Key_PageUp) {
                tabBar.decrementCurrentIndex();
            }
            event.accepted = true;
        }
        // N and Ctrl+N both open the quick task composer.
        else if (!root.showAddDialog && event.key === Qt.Key_N
                 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ControlModifier)) {
            root.openAddDialog();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SecondaryTabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 8
            visible: UnifiedAgenda.mutationBusy || UnifiedAgenda.mutationError.length > 0

            MaterialLoadingIndicator {
                visible: UnifiedAgenda.mutationBusy
                implicitSize: 18
                loading: UnifiedAgenda.mutationBusy
            }

            StyledText {
                Layout.fillWidth: true
                text: UnifiedAgenda.mutationError.length > 0
                    ? UnifiedAgenda.mutationError
                    : Translation.tr("Syncing QuickMail task…")
                color: UnifiedAgenda.mutationError.length > 0
                    ? Appearance.colors.colError
                    : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }
        }

        SwipeView {
            id: swipeView
            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true
            currentIndex: tabBar.currentIndex

            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("No todos")
                taskList: root.localTodoList
            }

            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "done_all"
                emptyPlaceholderText: Translation.tr("No completed tasks")
                taskList: root.localCompletedList
            }
        }
    }

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
        anchors.bottomMargin: root.fabMargins + 10
        implicitWidth: root.fabSize
        implicitHeight: root.fabSize
        buttonRadius: root.fabSize / 2

        onClicked: root.openAddDialog()
        iconText: "add"
    }

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

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
                onClicked: root.showAddDialog = false
            }
        }

        Rectangle {
            id: dialogCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: dialogColumnLayout.implicitHeight

            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            function addTask() {
                if (titleInput.text.trim().length > 0 && root.dueInputValid) {
                    const title = titleInput.text.trim();
                    const description = descriptionInput.text.trim();
                    const dueAt = root.parseDueAt();
                    let accepted = true;
                    if (root.remoteDestinationSelected) {
                        accepted = UnifiedAgenda.createRemoteTask(
                            root.selectedDestination.id,
                            title,
                            description,
                            dueAt
                        );
                    } else {
                        Todo.addTask(title, description, dueAt);
                    }
                    if (accepted) {
                        root.showAddDialog = false;
                        tabBar.setCurrentIndex(0);
                    }
                }
            }

            ColumnLayout {
                id: dialogColumnLayout
                anchors.fill: parent
                spacing: 6

                StyledText {
                    Layout.topMargin: 10
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.alignment: Qt.AlignLeft
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("New task")
                }

                TextField {
                    id: titleInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    padding: 8
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    renderType: Text.NativeRendering
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Task title")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    focus: root.showAddDialog
                    onAccepted: dialogCard.addTask()
                    KeyNavigation.tab: descriptionInput

                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: titleInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }

                    cursorDelegate: Rectangle {
                        width: 1
                        color: titleInput.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }
                }

                TextArea {
                    id: descriptionInput
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    padding: 8
                    implicitHeight: 48
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    renderType: Text.NativeRendering
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Task description")
                    placeholderTextColor: Appearance.m3colors.m3outline
                    wrapMode: TextEdit.Wrap
                    KeyNavigation.tab: destinationInput
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && (event.modifiers & Qt.ControlModifier)) {
                            dialogCard.addTask();
                            event.accepted = true;
                        }
                    }
                    background: Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.verysmall
                        border.width: 2
                        border.color: descriptionInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
                        color: "transparent"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    spacing: 8

                    StyledText {
                        text: Translation.tr("Task destination")
                        color: Appearance.m3colors.m3onSurface
                        font.weight: Font.DemiBold
                    }

                    StyledComboBox {
                        id: destinationInput
                        Layout.fillWidth: true
                        implicitHeight: 36
                        model: root.taskDestinations
                        textRole: "displayName"
                        currentIndex: root.selectedDestinationIndex
                        enabled: !UnifiedAgenda.mutationBusy
                        onActivated: index => root.selectedDestinationIndex = index
                        KeyNavigation.tab: dueDateInput
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    spacing: 6

                    StyledText {
                        text: root.dateOnlyDueDestination
                            ? Translation.tr("Due date")
                            : Translation.tr("Due")
                        color: Appearance.m3colors.m3onSurface
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Repeater {
                        model: [
                            {"label": Translation.tr("Today"), "days": 0},
                            {"label": Translation.tr("Tomorrow"), "days": 1},
                            {"label": Translation.tr("Next week"), "days": 7}
                        ]
                        delegate: GroupButton {
                            required property var modelData
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.small
                            onClicked: root.setDuePreset(modelData.days)
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }

                    GroupButton {
                        implicitWidth: 32
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.small
                        onClicked: root.dueEnabled = false
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "event_busy"
                            iconSize: 17
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    spacing: 8
                    visible: root.dueEnabled

                    TextField {
                        id: dueDateInput
                        Layout.fillWidth: true
                        enabled: root.dueEnabled
                        placeholderText: "YYYY-MM-DD"
                        inputMethodHints: Qt.ImhDate
                        selectByMouse: true
                        color: Appearance.m3colors.m3onSurface
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        KeyNavigation.tab: root.dateOnlyDueDestination ? titleInput : dueTimeInput
                        onAccepted: {
                            if (root.dateOnlyDueDestination)
                                dialogCard.addTask();
                            else
                                dueTimeInput.forceActiveFocus();
                        }
                        background: Rectangle {
                            radius: Appearance.rounding.verysmall
                            color: "transparent"
                            border.width: 2
                            border.color: !root.dueInputValid
                                ? Appearance.colors.colError
                                : dueDateInput.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.m3colors.m3outline
                        }
                    }

                    TextField {
                        id: dueTimeInput
                        Layout.preferredWidth: 90
                        visible: !root.dateOnlyDueDestination
                        enabled: root.dueEnabled && visible
                        placeholderText: "HH:MM"
                        inputMethodHints: Qt.ImhTime
                        horizontalAlignment: TextInput.AlignHCenter
                        selectByMouse: true
                        color: Appearance.m3colors.m3onSurface
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        KeyNavigation.tab: titleInput
                        onAccepted: dialogCard.addTask()
                        background: Rectangle {
                            radius: Appearance.rounding.verysmall
                            color: "transparent"
                            border.width: 2
                            border.color: !root.dueInputValid
                                ? Appearance.colors.colError
                                : dueTimeInput.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.m3colors.m3outline
                        }
                    }
                }

                StyledText {
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.fillWidth: true
                    visible: root.dueEnabled && root.dateOnlyDueDestination
                    text: Translation.tr("Google Tasks stores due dates without a time.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.fillWidth: true
                    visible: root.dueEnabled && !root.dueInputValid
                    text: root.dateOnlyDueDestination
                        ? Translation.tr("Use a valid date")
                        : Translation.tr("Use a valid date and 24-hour time")
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                RowLayout {
                    Layout.bottomMargin: 10
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.alignment: Qt.AlignRight
                    spacing: 5

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.showAddDialog = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: titleInput.text.trim().length > 0
                            && root.dueInputValid
                            && (!root.remoteDestinationSelected || !UnifiedAgenda.mutationBusy)
                        onClicked: dialogCard.addTask()
                    }
                }
            }
        }
    }
}
