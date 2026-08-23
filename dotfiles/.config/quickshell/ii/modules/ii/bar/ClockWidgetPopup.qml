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
    property string upcomingSection: getUpcomingSummary()

    function getUpcomingSummary() {
        const maxTs = 9007199254740991;
        const nowTs = Date.now();
        const endOfWindowTs = nowTs + 7 * 24 * 60 * 60 * 1000;

        const localItems = Todo.list
            .filter(item => {
                if (item.done) return false;
                const dueAt = item.dueAt ?? 0;
                return dueAt <= 0 || (dueAt >= nowTs && dueAt < endOfWindowTs);
            })
            .map(item => ({
                "ts": (item.dueAt ?? 0) > 0 ? item.dueAt : maxTs,
                "title": item.content ?? item.title ?? "",
                "allDay": false,
            }));

        const eventItems = CalendarBridge.thunderbirdEvents
            .filter(item => {
                const startAt = item.startAt ?? 0;
                const endAt = item.endAt ?? startAt;
                return startAt < endOfWindowTs && endAt >= nowTs;
            })
            .map(item => ({
                "ts": item.startAt ?? 0,
                "title": item.title ?? "",
                "allDay": !!item.allDay,
            }));
        const taskItems = CalendarBridge.thunderbirdTasks
            .filter(item => {
                if (item.done) return false;
                const ts = (item.dueAt ?? item.entryAt ?? 0);
                if (ts <= 0) return false;
                return ts >= nowTs && ts < endOfWindowTs;
            })
            .map(item => {
                const ts = (item.dueAt ?? item.entryAt ?? 0);
                return {
                    "ts": ts,
                    "title": item.content ?? "",
                    "allDay": false,
                };
            });

        const upcomingItems = [...localItems, ...eventItems, ...taskItems]
            .sort((a, b) => (a.ts ?? 0) - (b.ts ?? 0))
            .filter(item => item.title.length > 0);

        if (upcomingItems.length === 0) {
            return Translation.tr("No upcoming events");
        }

        const visibleItems = upcomingItems.slice(0, 8);
        let summary = visibleItems.map((item, index) => {
            const ts = item.ts ?? 0;
            const datePart = ts > 0 && ts < maxTs ? new Date(ts).toLocaleString(Qt.locale(), "dd MMM") : "";
            const timePart = item.allDay
                ? Translation.tr("All day")
                : (ts > 0 && ts < maxTs ? new Date(ts).toLocaleString(Qt.locale(), "HH:mm") : "");
            const when = [datePart, timePart].filter(part => part.length > 0).join(" ");
            return `  ${index + 1}. ${item.title}${when.length > 0 ? ` • ${when}` : ""}`;
        }).join("\n");

        if (upcomingItems.length > visibleItems.length) {
            summary += `\n  ${Translation.tr("... and %1 more").arg(upcomingItems.length - visibleItems.length)}`;
        }
        return summary;
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

        Column {
            spacing: 0
            Layout.fillWidth: true

            StyledPopupValueRow {
                icon: "event"
                label: Translation.tr("Upcoming events:")
                value: ""
            }

            StyledText {
                width: root.contentWidth
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnSurfaceVariant
                text: root.upcomingSection
            }
        }
    }
}
