pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    readonly property var italianWeekdayMap: ({
        "lunedì": "Lunedì",
        "martedì": "Martedì",
        "mercoledì": "Mercoledì",
        "giovedì": "Giovedì",
        "venerdì": "Venerdì",
        "sabato": "Sabato",
        "domenica": "Domenica",
        "lun": "Lun",
        "mar": "Mar",
        "mer": "Mer",
        "gio": "Gio",
        "ven": "Ven",
        "sab": "Sab",
        "dom": "Dom"
    })
    readonly property var italianWeekdayPattern: /lunedì|martedì|mercoledì|giovedì|venerdì|sabato|domenica|lun|mar|mer|gio|ven|sab|dom/g

    function capitalizeItalianWeekdays(text) {
        if (typeof text !== "string" || text.length === 0)
            return text;
        if (!Qt.locale().name.toLowerCase().startsWith("it"))
            return text;
        return text.replace(italianWeekdayPattern, function(match) {
            return italianWeekdayMap[match] ?? match;
        });
    }

    function formatDate(format) {
        return capitalizeItalianWeekdays(Qt.locale().toString(clock.date, format));
    }

    property var clock: SystemClock {
        id: clock
        precision: {
            if (Config.options.time.secondPrecision || GlobalStates.screenLocked)
                return SystemClock.Seconds;
            return SystemClock.Minutes;
        }
    }
    property string time: Qt.locale().toString(clock.date, Config.options?.time.format ?? "hh:mm")
    property string shortDate: capitalizeItalianWeekdays(Qt.locale().toString(clock.date, Config.options?.time.shortDateFormat ?? "dd/MM"))
    property string date: capitalizeItalianWeekdays(Qt.locale().toString(clock.date, Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy"))
    property string longDate: formatDate(Config.options?.time.dateFormat ?? "dddd, dd/MM")
    property string collapsedCalendarFormat: formatDate("dddd, MMMM dd")
    property string uptime: "0h, 0m"
    property string day: formatDate("dddd")

    Timer {
        interval: Math.max(100, Config.options?.resources?.updateInterval ?? 3000)
        running: true
        repeat: true
        onTriggered: {
            fileUptime.reload();
            const textUptime = fileUptime.text();
            const uptimeSeconds = Number(textUptime.split(" ")[0] ?? 0);

            // Convert seconds to days, hours, and minutes
            const days = Math.floor(uptimeSeconds / 86400);
            const hours = Math.floor((uptimeSeconds % 86400) / 3600);
            const minutes = Math.floor((uptimeSeconds % 3600) / 60);

            // Build the formatted uptime string
            let formatted = "";
            if (days > 0)
                formatted += `${days}d`;
            if (hours > 0)
                formatted += `${formatted ? ", " : ""}${hours}h`;
            if (minutes > 0 || !formatted)
                formatted += `${formatted ? ", " : ""}${minutes}m`;
            uptime = formatted;
        }
    }

    FileView {
        id: fileUptime

        path: "/proc/uptime"
    }
}
