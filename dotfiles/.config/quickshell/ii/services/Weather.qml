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
    }

    Process {
        id: fetcher
        command: ["bash", "-c", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) return;
                try {
                    const parsed = JSON.parse(text);
                    root.refineData(parsed);
                } catch(e) {
                    console.error("[WeatherService] Parse error: " + e.message);
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
