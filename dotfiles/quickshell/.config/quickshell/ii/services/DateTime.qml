import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services 1.0
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    function capitalizeFirst(text) {
        if (!text || text.length === 0) return text
        return text.charAt(0).toUpperCase() + text.slice(1)
    }

    property var clock: SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    property string time: Qt.locale().toString(
        clock.date,
        Config.options?.time.format ?? "hh:mm"
    )

    property string date: capitalizeFirst(
        Qt.locale().toString(clock.date, Config.options?.time.dateFormat ?? "dddd, dd/MM")
    )

    property string collapsedCalendarFormat: capitalizeFirst(
        Qt.locale().toString(clock.date, "dd MMMM yyyy")
    )

    property string uptime: "0h, 0m"

    Timer {
        interval: 10
        running: true
        repeat: true
        onTriggered: {
            fileUptime.reload()
            const textUptime = fileUptime.text()
            const uptimeSeconds = Number(textUptime.split(" ")[0] ?? 0)

            const days = Math.floor(uptimeSeconds / 86400)
            const hours = Math.floor((uptimeSeconds % 86400) / 3600)
            const minutes = Math.floor((uptimeSeconds % 3600) / 60)

            let formatted = ""
            if (days > 0) formatted += `${days}d`
            if (hours > 0) formatted += `${formatted ? ", " : ""}${hours}h`
            if (minutes > 0 || !formatted) formatted += `${formatted ? ", " : ""}${minutes}m`
            uptime = formatted

            interval = Config.options?.resources?.updateInterval ?? 3000
        }
    }

    FileView {
        id: fileUptime
        path: "/proc/uptime"
    }
}
