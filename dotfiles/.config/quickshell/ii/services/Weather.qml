pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning

import qs.modules.common

Singleton {
    id: root
    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property string city: Config.options.bar.weather.city
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    property bool gpsActive: Config.options.bar.weather.enableGPS

    onUseUSCSChanged: { root.getData(); }
    onCityChanged:    { root.getData(); }

    property var location: ({ valid: false, lat: 0, long: 0 })

    property var data: ({
        uv: "--",
        humidity: "--",
        sunrise: "--",
        sunset: "--",
        windDir: "--",
        wCode: null,
        city: "",
        wind: "--",
        precip: "--",
        visib: "--",
        press: "--",
        temp: "--",
        tempFeelsLike: "",
        lastRefresh: "--",
        hourly: [],
    })

    function refineData(raw) {
        if (!raw || !raw.current) return;
        const c = raw.current;
        let d = {};

        d.wCode    = c.weather_code ?? null;
        d.uv       = c.uv_index               != null ? c.uv_index : "--";
        d.humidity = c.relative_humidity_2m   != null ? (c.relative_humidity_2m + "%") : "--";

        // Degrees → 16-point compass
        if (c.wind_direction_10m != null) {
            const dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"];
            d.windDir = dirs[Math.round(c.wind_direction_10m / 22.5) % 16];
        } else {
            d.windDir = "--";
        }

        // Sunrise/sunset: "2024-01-15T07:23" → "07:23"
        d.sunrise = raw.daily?.sunrise?.[0]?.slice(11) ?? "--";
        d.sunset  = raw.daily?.sunset?.[0]?.slice(11)  ?? "--";
        d.city    = raw.city || "";

        const vis   = c.visibility       ?? null;
        const press = c.surface_pressure  ?? null;

        if (root.useUSCS) {
            d.wind   = c.wind_speed_10m    != null ? (Math.round(c.wind_speed_10m)              + " mph")  : "--";
            d.precip = c.precipitation     != null ? (c.precipitation                           + " in")   : "--";
            d.visib  = vis   != null ? ((Math.round(vis / 160.934) / 10)                        + " mi")   : "--";
            d.press  = press != null ? ((Math.round(press * 0.02953 * 100) / 100)               + " inHg") : "--";
            d.temp          = c.temperature_2m      != null ? (Math.round(c.temperature_2m)      + "°F") : "--";
            d.tempFeelsLike = c.apparent_temperature != null ? (Math.round(c.apparent_temperature) + "°F") : "";
        } else {
            d.wind   = c.wind_speed_10m    != null ? (Math.round(c.wind_speed_10m)              + " km/h") : "--";
            d.precip = c.precipitation     != null ? (c.precipitation                           + " mm")   : "--";
            d.visib  = vis   != null ? ((Math.round(vis / 100) / 10)                            + " km")   : "--";
            d.press  = press != null ? (Math.round(press)                                       + " hPa")  : "--";
            d.temp          = c.temperature_2m      != null ? (Math.round(c.temperature_2m)      + "°C") : "--";
            d.tempFeelsLike = c.apparent_temperature != null ? (Math.round(c.apparent_temperature) + "°C") : "";
        }

        d.lastRefresh = DateTime.time + " • " + DateTime.date;

        // Next 10 hourly slots from now
        d.hourly = [];
        try {
            const times = raw.hourly?.time           ?? [];
            const temps = raw.hourly?.temperature_2m ?? [];
            const codes = raw.hourly?.weather_code   ?? [];
            const nowStr = new Date().toISOString().slice(0, 13); // "2024-01-15T15"
            for (let i = 0; i < times.length && d.hourly.length < 10; i++) {
                if (times[i].slice(0, 13) >= nowStr) {
                    d.hourly.push({
                        time:  times[i].slice(11, 16),
                        wCode: codes[i],
                        temp:  root.useUSCS ? (Math.round(temps[i]) + "°F") : (Math.round(temps[i]) + "°C")
                    });
                }
            }
        } catch(e) {
            console.error("[WeatherService] Hourly forecast error: " + e.message);
        }

        root.data = d;
    }

    // wttr.in uses "06:30 AM" format — convert to 24h "06:30"
    function to24h(t) {
        if (!t) return "--";
        const parts = t.trim().split(' ');
        if (parts.length < 2) return t.trim().slice(0, 5);
        let [hh, mm] = parts[0].split(':');
        hh = parseInt(hh);
        if (parts[1] === 'AM' && hh === 12) hh = 0;
        if (parts[1] === 'PM' && hh !== 12) hh += 12;
        return `${String(hh).padStart(2, '0')}:${mm}`;
    }

    function refineDataWttr(raw) {
        if (!raw || !raw.current_condition?.[0]) return;
        const c = raw.current_condition[0];
        const w = raw.weather?.[0];
        let d = {};

        // wttr.in returns all values as strings
        d.wCode    = parseInt(c.weatherCode) || null;
        d.uv       = c.uvIndex ?? w?.uvIndex ?? "--";
        d.humidity = c.humidity != null ? (c.humidity + "%") : "--";
        d.windDir  = c.winddir16Point ?? "--";

        d.sunrise  = root.to24h(w?.astronomy?.[0]?.sunrise);
        d.sunset   = root.to24h(w?.astronomy?.[0]?.sunset);
        d.city     = raw.nearest_area?.[0]?.areaName?.[0]?.value ?? root.city;

        if (root.useUSCS) {
            d.wind          = c.windspeedMiles  != null ? (c.windspeedMiles   + " mph")  : "--";
            d.precip        = c.precipInches    != null ? (c.precipInches     + " in")   : "--";
            d.visib         = c.visibilityMiles != null ? (c.visibilityMiles  + " mi")   : "--";
            d.press         = c.pressureInches  != null ? (c.pressureInches   + " inHg") : "--";
            d.temp          = c.temp_F          != null ? (c.temp_F           + "°F")    : "--";
            d.tempFeelsLike = c.FeelsLikeF      != null ? (c.FeelsLikeF       + "°F")    : "";
        } else {
            d.wind          = c.windspeedKmph   != null ? (c.windspeedKmph    + " km/h") : "--";
            d.precip        = c.precipMM        != null ? (c.precipMM         + " mm")   : "--";
            d.visib         = c.visibility      != null ? (c.visibility       + " km")   : "--";
            d.press         = c.pressure        != null ? (c.pressure         + " hPa")  : "--";
            d.temp          = c.temp_C          != null ? (c.temp_C           + "°C")    : "--";
            d.tempFeelsLike = c.FeelsLikeC      != null ? (c.FeelsLikeC       + "°C")    : "";
        }

        d.lastRefresh = DateTime.time + " • " + DateTime.date + " (wttr.in)";

        // Hourly: wttr.in gives 8 slots/day at "0","300","600",...,"2100" (hour*100)
        d.hourly = [];
        try {
            const todayStr = new Date().toISOString().slice(0, 10);
            const nowMins  = new Date().getHours() * 60 + new Date().getMinutes();
            for (const day of (raw.weather ?? [])) {
                const isToday = day.date === todayStr;
                for (const slot of (day.hourly ?? [])) {
                    const slotH = Math.floor(parseInt(slot.time) / 100);
                    const slotM = parseInt(slot.time) % 100;
                    if (isToday && (slotH * 60 + slotM) < nowMins) continue;
                    d.hourly.push({
                        time:  `${String(slotH).padStart(2,'0')}:${String(slotM).padStart(2,'0')}`,
                        wCode: parseInt(slot.weatherCode),
                        temp:  root.useUSCS ? (slot.tempF + "°F") : (slot.tempC + "°C")
                    });
                    if (d.hourly.length >= 10) break;
                }
                if (d.hourly.length >= 10) break;
            }
        } catch(e) {
            console.error("[WeatherService] wttr.in hourly error: " + e.message);
        }

        root.data = d;
    }

    function tryFallback() {
        console.info("[WeatherService] open-meteo unavailable — falling back to wttr.in");
        const loc = (root.gpsActive && root.location.valid)
            ? (root.location.lat + "," + root.location.long)
            : formatCityName(root.city);
        fallbackFetcher.command = ["curl", "-s", "--max-time", "15", `https://wttr.in/${loc}?format=j1`];
        fallbackFetcher.running = true;
    }

    function getData() {
        const units = root.useUSCS
            ? "&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch"
            : "";
        const params = "current=temperature_2m,apparent_temperature,weather_code,"
            + "wind_speed_10m,wind_direction_10m,precipitation,relative_humidity_2m,"
            + "surface_pressure,uv_index,visibility"
            + "&daily=sunrise,sunset"
            + "&hourly=temperature_2m,weather_code"
            + "&timezone=auto&forecast_days=2"
            + units;

        let command;
        if (root.gpsActive && root.location.valid) {
            const url = "https://api.open-meteo.com/v1/forecast?latitude="
                + root.location.lat + "&longitude=" + root.location.long + "&" + params;
            command = "curl -s --max-time 15 '" + url + "'"
                + " | jq '. + {city:\"GPS Location\"}' || echo '{}'";
        } else {
            const city = formatCityName(root.city);
            const geoUrl = "https://geocoding-api.open-meteo.com/v1/search?name="
                + city + "&count=1&language=en&format=json";
            const weatherBase = "https://api.open-meteo.com/v1/forecast?" + params;
            command = "GEO=$(curl -s --max-time 10 '" + geoUrl + "'); "
                + "LAT=$(echo \"$GEO\" | jq -r '.results[0].latitude // empty'); "
                + "LON=$(echo \"$GEO\" | jq -r '.results[0].longitude // empty'); "
                + "CITY=$(echo \"$GEO\" | jq -r '.results[0].name // \"Unknown\"'); "
                + "[ -z \"$LAT\" ] && echo '{}' && exit 0; "
                + "curl -s --max-time 15 '" + weatherBase + "&latitude='\"$LAT\"'&longitude='\"$LON\"''"
                + " | jq --arg c \"$CITY\" '. + {city: $c}' || echo '{}'";
        }

        fetcher.command = ["bash", "-c", command];
        fetcher.running = true;
    }

    function formatCityName(cityName) {
        return cityName.trim().split(/\s+/).join('+');
    }

    Component.onCompleted: {
        if (!root.gpsActive) return;
        console.info("[WeatherService] Starting the GPS service.");
        positionSource.start();
        gpsTimeoutTimer.restart();
    }

    // If GPS is enabled but never delivers coordinates (e.g. geoclue is installed
    // but inactive/unconfigured), fall back to city mode after one fetch interval.
    Timer {
        id: gpsTimeoutTimer
        interval: root.fetchInterval
        repeat: false
        onTriggered: {
            if (!root.gpsActive || root.location.valid) return;
            console.warn("[WeatherService] GPS timed out — no position received. Falling back to city mode.");
            positionSource.stop();
            root.location.valid = false;
            root.gpsActive = false;
            Quickshell.execDetached(["notify-send", Translation.tr("Weather Service"),
                Translation.tr("GPS timed out. Using city fallback instead."), "-a", "Shell"]);
        }
    }

    // Primary: open-meteo. On any failure (bad JSON, empty response, no .current)
    // automatically retries via wttr.in.
    Process {
        id: fetcher
        command: ["bash", "-c", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) {
                    root.tryFallback();
                    return;
                }
                try {
                    const parsed = JSON.parse(text);
                    if (parsed?.current) {
                        root.refineData(parsed);
                    } else {
                        root.tryFallback();
                    }
                } catch(e) {
                    console.error("[WeatherService] open-meteo parse error: " + e.message);
                    root.tryFallback();
                }
            }
        }
    }

    // Fallback: wttr.in
    Process {
        id: fallbackFetcher
        command: ["curl", "-s", "--max-time", "15", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) {
                    console.error("[WeatherService] wttr.in returned empty response");
                    return;
                }
                try {
                    const parsed = JSON.parse(text);
                    root.refineDataWttr(parsed);
                } catch(e) {
                    console.error("[WeatherService] wttr.in parse error: " + e.message);
                }
            }
        }
    }

    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval

        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                root.location.lat   = position.coordinate.latitude;
                root.location.long  = position.coordinate.longitude;
                root.location.valid = true;
                root.getData();
            } else {
                root.gpsActive = root.location.valid ? true : false;
                console.error("[WeatherService] Failed to get the GPS location.");
            }
        }

        onValidityChanged: {
            if (!positionSource.valid) {
                positionSource.stop();
                root.location.valid = false;
                root.gpsActive = false;
                Quickshell.execDetached(["notify-send", Translation.tr("Weather Service"),
                    Translation.tr("Cannot find a GPS service. Using the fallback method instead."), "-a", "Shell"]);
                console.error("[WeatherService] Could not acquire a valid backend plugin.");
            }
        }
    }

    Timer {
        running: !root.gpsActive
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: !root.gpsActive
        onTriggered: root.getData()
    }
}
