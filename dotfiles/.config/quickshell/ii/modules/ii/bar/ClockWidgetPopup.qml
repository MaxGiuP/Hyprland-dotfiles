import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    horizontalOffset: -20
    property real contentWidth: 340
    property string formattedDate: DateTime.formatDate("dddd, MMMM dd, yyyy")
    property string formattedTime: DateTime.time
    property string formattedUptime: DateTime.uptime
    property string todosSection: getUpcomingTodos()
    property string thunderbirdSection: getThunderbirdSummary()

    function getUpcomingTodos() {
        const startOfToday = new Date();
        startOfToday.setHours(0, 0, 0, 0);
        const startOfTodayTs = startOfToday.getTime();
        const endOfWindowTs = startOfTodayTs + 8 * 24 * 60 * 60 * 1000;

        const unfinishedTodos = Todo.list.filter(function (item) {
            if (item.done) return false;
            const dueAt = item.dueAt ?? 0;
            // Local todos have no due date (dueAt=0), always show them
            if (dueAt <= 0) return true;
            return dueAt >= startOfTodayTs && dueAt < endOfWindowTs;
        });
        if (unfinishedTodos.length === 0) {
            return Translation.tr("No pending tasks");
        }

        // Limit to first 5 todos to keep popup manageable
        const limitedTodos = unfinishedTodos.slice(0, 5);
        let todoText = limitedTodos.map(function (item, index) {
            return `  ${index + 1}. ${item.content}`;
        }).join('\n');

        if (unfinishedTodos.length > 5) {
            todoText += `\n  ${Translation.tr("... and %1 more").arg(unfinishedTodos.length - 5)}`;
        }

        return todoText;
    }

    function getThunderbirdSummary() {
        const maxTs = 9007199254740991;
        const startOfToday = new Date();
        startOfToday.setHours(0, 0, 0, 0);
        const startOfTodayTs = startOfToday.getTime();
        const endOfWindowTs = startOfTodayTs + 8 * 24 * 60 * 60 * 1000; // today + 7 days

        const eventItems = CalendarBridge.thunderbirdEvents
            .filter(item => {
                const startAt = item.startAt ?? 0;
                return startAt >= startOfTodayTs && startAt < endOfWindowTs;
            })
            .map(item => ({
                "kind": "event",
                "ts": item.startAt ?? 0,
                "title": item.title ?? "",
                "allDay": !!item.allDay,
            }));
        const taskItems = CalendarBridge.thunderbirdTasks
            .filter(item => {
                if (item.done) return false;
                const ts = (item.dueAt ?? item.entryAt ?? 0);
                if (ts <= 0) return false;
                return ts >= startOfTodayTs && ts < endOfWindowTs;
            })
            .map(item => {
                const ts = (item.dueAt ?? item.entryAt ?? 0);
                return {
                    "kind": "task",
                    "ts": ts,
                    "title": item.content ?? "",
                };
            });
        const merged = [...eventItems, ...taskItems]
            .sort((a, b) => (a.ts ?? 0) - (b.ts ?? 0))
            .slice(0, 6);

        if (merged.length === 0) {
            return Translation.tr("No upcoming Thunderbird events/tasks");
        }

        return merged.map((item, index) => {
            const isEvent = item.kind === "event";
            const ts = item.ts ?? 0;
            const datePart = ts > 0 && ts < maxTs ? new Date(ts).toLocaleString(Qt.locale(), "dd MMM") : "";
            const timePart = isEvent
                ? (item.allDay ? "--:--" : (ts > 0 ? new Date(ts).toLocaleString(Qt.locale(), "HH:mm") : "--:--"))
                : (ts > 0 && ts < maxTs ? new Date(ts).toLocaleString(Qt.locale(), "HH:mm") : Translation.tr("No due date"));
            const label = isEvent ? `E${index + 1}` : `T${index + 1}`;
            const when = datePart.length > 0 ? `${datePart} ${timePart}` : timePart;
            return `  ${label}. ${item.title} • ${when}`;
        }).join("\n");
    }

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 4

        StyledPopupHeaderRow {
            icon: "calendar_month"
            label: root.formattedDate
        }

        StyledPopupValueRow {
            icon: "timelapse"
            label: Translation.tr("System uptime:")
            value: root.formattedUptime
        }

        // Tasks
        Column {
            spacing: 0
            Layout.fillWidth: true

            StyledPopupValueRow {
                icon: "checklist"
                label: Translation.tr("To Do:")
                value: ""
            }

            StyledText {
                width: root.contentWidth
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                text: root.todosSection
            }
        }

        Column {
            spacing: 0
            Layout.fillWidth: true

            StyledPopupValueRow {
                icon: "event"
                label: Translation.tr("Thunderbird:")
                value: ""
            }

            StyledText {
                width: root.contentWidth
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                text: root.thunderbirdSection
            }
        }
    }
}
