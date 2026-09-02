import QtQuick
import QtTest
import "../../modules/ii/sidebarRight/calendar/agenda_dates.js" as AgendaDates

TestCase {
    name: "SidebarAgendaDates"

    function localDate(year, month, day, hour) {
        return new Date(year, month, day, hour === undefined ? 12 : hour, 0, 0, 0);
    }

    function test_allDayUsesUtcCalendarDateAndExclusiveEnd() {
        const event = {
            startAt: Date.UTC(2026, 6, 10),
            endAt: Date.UTC(2026, 6, 11),
            allDay: true,
        };

        verify(AgendaDates.eventIntersectsDate(event, localDate(2026, 6, 10)));
        verify(!AgendaDates.eventIntersectsDate(event, localDate(2026, 6, 11)));
    }

    function test_allDayRemainsStableAcrossLondonDstBoundary() {
        const event = {
            startAt: Date.UTC(2026, 2, 29),
            endAt: Date.UTC(2026, 2, 30),
            allDay: true,
        };

        verify(AgendaDates.eventIntersectsDate(event, localDate(2026, 2, 29)));
        verify(!AgendaDates.eventIntersectsDate(event, localDate(2026, 2, 30)));
    }

    function test_timedEventEndingAtMidnightDoesNotLeakIntoNextDay() {
        const event = {
            startAt: localDate(2026, 6, 10, 22).getTime(),
            endAt: localDate(2026, 6, 11, 0).getTime(),
            allDay: false,
        };

        verify(AgendaDates.eventIntersectsDate(event, localDate(2026, 6, 10)));
        verify(!AgendaDates.eventIntersectsDate(event, localDate(2026, 6, 11)));
    }

    function test_overnightTimedEventAppearsOnBothIntersectedDays() {
        const event = {
            startAt: localDate(2026, 6, 10, 23).getTime(),
            endAt: localDate(2026, 6, 11, 2).getTime(),
            allDay: false,
        };

        verify(AgendaDates.eventIntersectsDate(event, localDate(2026, 6, 10)));
        verify(AgendaDates.eventIntersectsDate(event, localDate(2026, 6, 11)));
        verify(!AgendaDates.eventIntersectsDate(event, localDate(2026, 6, 12)));
    }

    function test_focusedRangeIncludesAnAlreadyRunningEvent() {
        const event = {
            startAt: localDate(2026, 6, 9, 20).getTime(),
            endAt: localDate(2026, 6, 11, 8).getTime(),
            allDay: false,
        };
        const rangeStart = localDate(2026, 6, 10, 0).getTime();
        const rangeEnd = localDate(2026, 6, 11, 0).getTime();

        verify(AgendaDates.eventIntersectsRange(event, rangeStart, rangeEnd));
    }
}
