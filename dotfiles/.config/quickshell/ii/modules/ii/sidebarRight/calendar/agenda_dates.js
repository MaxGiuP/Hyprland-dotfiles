function value(item, camelName, snakeName) {
    if (!item) return undefined;
    return item[camelName] !== undefined ? item[camelName] : item[snakeName];
}

function timestamp(input) {
    if (input === undefined || input === null || input === "") return NaN;
    const instant = input instanceof Date ? input : new Date(input);
    return instant.getTime();
}

function startOfDay(value) {
    const instant = value instanceof Date ? value : new Date(value);
    if (isNaN(instant.getTime())) return NaN;
    return new Date(instant.getFullYear(), instant.getMonth(), instant.getDate()).getTime();
}

function utcCalendarDay(value) {
    const instant = value instanceof Date ? value : new Date(value);
    if (isNaN(instant.getTime())) return NaN;
    return Math.floor(Date.UTC(
        instant.getUTCFullYear(),
        instant.getUTCMonth(),
        instant.getUTCDate()
    ) / 86400000);
}

function localCalendarDay(value) {
    const instant = value instanceof Date ? value : new Date(value);
    if (isNaN(instant.getTime())) return NaN;
    return Math.floor(Date.UTC(
        instant.getFullYear(),
        instant.getMonth(),
        instant.getDate()
    ) / 86400000);
}

function isAllDayEvent(event) {
    return !!event && (event.allDay === true || event.all_day === true);
}

function eventStart(event) {
    const direct = value(event, "startAt", "start_at");
    return timestamp(direct !== undefined ? direct : event && event.dueAt);
}

function eventEnd(event) {
    return timestamp(value(event, "endAt", "end_at"));
}

function normalizedEventEnd(event, start) {
    let end = eventEnd(event);
    if (isNaN(end) || end <= start) end = start + 1;
    return end;
}

// Calendar providers encode all-day dates as UTC-midnight boundaries and the
// end date is exclusive. Comparing those values as local instants shifts days
// during DST and makes a one-day event appear on tomorrow as well.
function eventIntersectsDate(event, dateValue) {
    const start = eventStart(event);
    if (isNaN(start)) return false;

    if (isAllDayEvent(event)) {
        const day = localCalendarDay(dateValue);
        const startDay = utcCalendarDay(start);
        let endDay = utcCalendarDay(eventEnd(event));
        if (isNaN(day) || isNaN(startDay)) return false;
        if (isNaN(endDay) || endDay <= startDay) endDay = startDay + 1;
        return day >= startDay && day < endDay;
    }

    const dayStart = startOfDay(dateValue);
    if (isNaN(dayStart)) return false;
    const dayDate = new Date(dayStart);
    const nextDay = new Date(
        dayDate.getFullYear(),
        dayDate.getMonth(),
        dayDate.getDate() + 1
    ).getTime();
    return start < nextDay && normalizedEventEnd(event, start) > dayStart;
}

function eventIntersectsRange(event, rangeStart, rangeEnd) {
    const start = eventStart(event);
    const from = timestamp(rangeStart);
    const to = timestamp(rangeEnd);
    if (isNaN(start) || isNaN(from) || isNaN(to) || to <= from) return false;

    if (isAllDayEvent(event)) {
        const firstDay = localCalendarDay(from);
        const finalDay = localCalendarDay(new Date(to - 1)) + 1;
        const startDay = utcCalendarDay(start);
        let endDay = utcCalendarDay(eventEnd(event));
        if (isNaN(firstDay) || isNaN(finalDay) || isNaN(startDay)) return false;
        if (isNaN(endDay) || endDay <= startDay) endDay = startDay + 1;
        return startDay < finalDay && endDay > firstDay;
    }

    return start < to && normalizedEventEnd(event, start) > from;
}

function eventEndsAfterDate(event, dateValue) {
    const start = eventStart(event);
    if (isNaN(start)) return false;

    if (isAllDayEvent(event)) {
        const day = localCalendarDay(dateValue);
        const startDay = utcCalendarDay(start);
        let endDay = utcCalendarDay(eventEnd(event));
        if (isNaN(day) || isNaN(startDay)) return false;
        if (isNaN(endDay) || endDay <= startDay) endDay = startDay + 1;
        return endDay > day;
    }

    const dayStart = startOfDay(dateValue);
    return !isNaN(dayStart) && normalizedEventEnd(event, start) > dayStart;
}
