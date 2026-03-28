import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    anchors.topMargin: 10
    property int monthShift: 0
    property int currentDay: new Date().getDate()
    property var viewingDate: (currentDay, CalendarLayout.getDateInXMonthsTime(monthShift))
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    property date selectedDate: new Date()
    property var thunderbirdTasks: RemoteCalendarBridge.thunderbirdTasks
    property var thunderbirdEvents: RemoteCalendarBridge.thunderbirdEvents
    property string lastError: RemoteCalendarBridge.lastError
    readonly property bool loading: RemoteCalendarBridge.loading
    readonly property bool hasAnyData: root.thunderbirdEvents.length > 0 || root.thunderbirdTasks.length > 0

    Timer {
        id: midnightTimer
        repeat: false
        running: true
        interval: {
            const now = new Date();
            const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
            return midnight.getTime() - now.getTime();
        }
        onTriggered: {
            root.currentDay = new Date().getDate();
            if (root.monthShift === 0) root.selectedDate = new Date();
            midnightTimer.interval = 86400000;
            midnightTimer.restart();
        }
    }

    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 20

    function startOfDay(dateObj) {
        const d = new Date(dateObj);
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function endOfDay(dateObj) {
        const d = startOfDay(dateObj);
        d.setDate(d.getDate() + 1);
        return d;
    }

    function dayToDate(dayValue) {
        if (!dayValue || `${dayValue}`.trim().length === 0) return null;
        const d = new Date(viewingDate);
        d.setDate(parseInt(dayValue));
        d.setHours(0, 0, 0, 0);
        return d;
    }

    function dateMatches(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function localTasksForDay(dayDate) {
        const start = startOfDay(dayDate).getTime();
        const end = endOfDay(dayDate).getTime();
        return Todo.list.filter(task => {
            if (task.done) return false;
            const dueAt = parseInt(task?.dueAt ?? 0) || 0;
            return dueAt >= start && dueAt < end;
        });
    }

    function allTasksForDay(dayDate) {
        const range = CalendarBridge.dateRangeForDay(dayDate);
        const imported = root.thunderbirdTasks.filter(task => {
            if (task.done) return false;
            const due = task.dueAt ?? 0;
            const entry = task.entryAt ?? 0;
            const ts = due > 0 ? due : entry;
            return ts > 0 && ts >= range.startMs && ts < range.endMs;
        });
        return [...localTasksForDay(dayDate), ...imported];
    }

    function eventsForDay(dayDate) {
        const range = CalendarBridge.dateRangeForDay(dayDate);
        return root.thunderbirdEvents
            .filter(event => {
                const start = event.startAt ?? 0;
                const end = event.endAt ?? start;
                if (start <= 0)
                    return false;
                return start < range.endMs && (end <= 0 ? start : end) >= range.startMs;
            })
            .sort((a, b) => (a.startAt ?? 0) - (b.startAt ?? 0));
    }

    function allUpcomingItems() {
        const minTs = root.startOfDay(root.selectedDate).getTime();
        const eventItems = root.thunderbirdEvents
            .filter(item => {
                const start = parseInt(item?.startAt ?? 0) || 0;
                const end = parseInt(item?.endAt ?? start) || start;
                return start > 0 && (end >= minTs || start >= minTs);
            })
            .map(item => ({
            "kind": "event",
            "title": item.title ?? "",
            "at": item.startAt ?? 0,
            "endAt": item.endAt ?? 0,
            "allDay": !!item.allDay,
            "readOnly": true,
        }));
        const localTaskItems = Todo.list.filter(task => {
            if (task.done) return false;
            const dueAt = parseInt(task?.dueAt ?? 0) || 0;
            return dueAt >= minTs;
        }).map(task => ({
            "kind": "task",
            "title": task.content,
            "at": task.dueAt,
            "source": "local",
            "readOnly": false,
            "allDay": false,
        }));
        const importedTaskItems = root.thunderbirdTasks
            .filter(task => {
                if (task.done) return false;
                const ts = parseInt(task?.dueAt ?? task?.entryAt ?? 0) || 0;
                return ts >= minTs;
            })
            .map(task => ({
            "kind": "task",
            "title": task.content ?? "",
            "at": task.dueAt || task.entryAt,
            "dueAt": task.dueAt || 0,
            "entryAt": task.entryAt || 0,
            "allDay": task.allDay === true,
            "source": "thunderbird",
            "readOnly": true,
        }));

        return [...eventItems, ...localTaskItems, ...importedTaskItems]
            .filter(item => (item.at ?? 0) > 0)
            .sort((a, b) => (a.at ?? 0) - (b.at ?? 0))
            .filter(item => `${item.title ?? ""}`.trim().length > 0);
    }

    function capitalizeFirst(text) {
        if (!text || text.length === 0) return text;
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    function formatDateWithCapitalMonth(dateObj, format) {
        const dateValue = new Date(dateObj);
        const raw = dateValue.toLocaleDateString(Qt.locale(), format);
        const monthLong = dateValue.toLocaleDateString(Qt.locale(), "MMMM");
        const monthShort = dateValue.toLocaleDateString(Qt.locale(), "MMM");
        const monthLongCap = root.capitalizeFirst(monthLong);
        const monthShortCap = root.capitalizeFirst(monthShort);
        let out = raw.replace(monthLong, monthLongCap);
        out = out.replace(monthShort, monthShortCap);
        return out;
    }

    function formatDateTimeWithCapitalMonth(dateObj, format) {
        const dateValue = new Date(dateObj);
        const raw = dateValue.toLocaleString(Qt.locale(), format);
        const monthLong = dateValue.toLocaleDateString(Qt.locale(), "MMMM");
        const monthShort = dateValue.toLocaleDateString(Qt.locale(), "MMM");
        const monthLongCap = root.capitalizeFirst(monthLong);
        const monthShortCap = root.capitalizeFirst(monthShort);
        let out = raw.replace(monthLong, monthLongCap);
        out = out.replace(monthShort, monthShortCap);
        return out;
    }

    function isAllDayTask(taskLike) {
        if (taskLike?.allDay === true)
            return true;
        if (!(taskLike?.readOnly || taskLike?.source === "thunderbird"))
            return false;
        const ts = parseInt(taskLike?.dueAt ?? taskLike?.entryAt ?? taskLike?.at ?? 0) || 0;
        if (ts <= 0)
            return false;
        const d = new Date(ts);
        return d.getHours() === 0
            && d.getMinutes() === 0
            && d.getSeconds() === 0
            && d.getMilliseconds() === 0;
    }

    function formatTaskDateTime(taskLike) {
        const ts = parseInt(taskLike?.dueAt ?? taskLike?.entryAt ?? taskLike?.at ?? 0) || 0;
        if (ts <= 0)
            return "";
        const d = new Date(ts);
        const datePart = root.formatDateWithCapitalMonth(d, "dd MMM");
        const timePart = root.isAllDayTask(taskLike)
            ? "--:--"
            : d.toLocaleTimeString(Qt.locale(), "HH:mm");
        return `${datePart}, ${timePart}`;
    }

    function formatUpcomingDateTime(item) {
        if ((item?.kind ?? "") === "event") {
            const ts = parseInt(item?.at ?? 0) || 0;
            if (ts <= 0)
                return "";
            const d = new Date(ts);
            const datePart = root.formatDateWithCapitalMonth(d, "dd MMM");
            const timePart = item?.allDay === true
                ? "--:--"
                : d.toLocaleTimeString(Qt.locale(), "HH:mm");
            return `${datePart}, ${timePart}`;
        }
        return root.formatTaskDateTime(item);
    }

    function openThunderbirdForDay(dateObj) {
        if (!dateObj)
            return;
        const isoDate = Qt.formatDate(new Date(dateObj), "yyyy-MM-dd");
        const launcher = `${Directories.scriptPath}/calendar/open_thunderbird_day.sh`.replace(/file:\/\//, "");
        Quickshell.execDetached(["bash", launcher, isoDate]);
    }

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                monthShift++;
            } else if (event.key === Qt.Key_PageUp) {
                monthShift--;
            }
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (event.angleDelta.y > 0) {
                monthShift--;
            } else if (event.angleDelta.y < 0) {
                monthShift++;
            }
        }
    }

    ColumnLayout {
        id: calendarColumn
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 5
            CalendarHeaderButton {
                clip: true
                buttonText: `${monthShift != 0 ? "• " : ""}${root.formatDateWithCapitalMonth(viewingDate, "MMMM yyyy")}`
                tooltipText: (monthShift === 0) ? "" : Translation.tr("Jump to current month")
                downAction: () => {
                    monthShift = 0;
                    selectedDate = new Date();
                }
            }
            Item { Layout.fillWidth: true }
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => monthShift--
                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => monthShift++
                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                tooltipText: Translation.tr("Open Thunderbird calendar")
                downAction: () => Quickshell.execDetached(["thunderbird", "-calendar"])
                contentItem: MaterialSymbol {
                    text: "open_in_new"
                    iconSize: Appearance.font.pixelSize.large
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                tooltipText: Translation.tr("Refresh Thunderbird calendar/tasks")
                downAction: () => RemoteCalendarBridge.refresh()
                contentItem: MaterialSymbol {
                    text: root.loading ? "hourglass_top" : "refresh"
                    iconSize: Appearance.font.pixelSize.large
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            visible: root.loading

            MaterialLoadingIndicator {
                implicitSize: 22
                loading: root.loading
            }

            StyledText {
                text: root.hasAnyData ? Translation.tr("Refreshing calendar data") : Translation.tr("Loading calendar data")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        RowLayout {
            id: weekDaysRow
            Layout.alignment: Qt.AlignHCenter
            spacing: 5
            Repeater {
                model: CalendarLayout.weekDays
                delegate: CalendarDayButton {
                    day: Translation.tr(modelData.day)
                    isToday: modelData.today
                    bold: true
                    enabled: false
                }
            }
        }

        Repeater {
            id: calendarRows
            model: 6
            delegate: RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 5
                Repeater {
                    model: Array(7).fill(modelData)
                    delegate: CalendarDayButton {
                        property var dayData: calendarLayout[modelData][index]
                        property var parsedDate: root.dayToDate(dayData.day)
                        day: dayData.day
                        isToday: dayData.today
                        enabled: dayData.today >= 0
                        selected: parsedDate ? root.dateMatches(parsedDate, root.selectedDate) : false
                        eventCount: parsedDate ? root.eventsForDay(parsedDate).length : 0
                        taskCount: parsedDate ? root.allTasksForDay(parsedDate).length : 0
                        onDayClicked: {
                            if (parsedDate) {
                                root.selectedDate = parsedDate;
                                RemoteCalendarBridge.focusDay(parsedDate);
                                Persistent.states.sidebar.bottomGroup.tab = 1;
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            height: 1
            color: Appearance.colors.colOutlineVariant
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2

            StyledText {
                text: Translation.tr("All upcoming from %1").arg(root.formatDateWithCapitalMonth(root.selectedDate, "dd MMM yyyy"))
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: `${root.allUpcomingItems().length}`
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: 120

            StyledListView {
                id: upcomingList
                anchors.fill: parent
                spacing: 6
                animateAppearance: false
                clip: true
                model: ScriptModel {
                    values: root.allUpcomingItems()
                }

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    color: Appearance.colors.colLayer2
                    radius: Appearance.rounding.small
                    implicitHeight: upcomingItemColumn.implicitHeight + 16

                    ColumnLayout {
                        id: upcomingItemColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true

                            MaterialSymbol {
                                text: modelData.kind === "event" ? "event" : "checklist"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.title ?? ""
                                wrapMode: Text.Wrap
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.formatUpcomingDateTime(modelData)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !!modelData.readOnly
                            text: Translation.tr("Source: Thunderbird")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: root.allUpcomingItems().length === 0
                spacing: 5

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 42
                    color: Appearance.m3colors.m3outline
                    text: "event_busy"
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No upcoming events or tasks")
                    color: Appearance.m3colors.m3outline
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.lastError.length > 0
            text: root.lastError
            wrapMode: Text.Wrap
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

    }
}
