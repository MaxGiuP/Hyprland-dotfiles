use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde_json::{Value, json};
use zbus::blocking::{Connection, Proxy};
use zbus::names::OwnedInterfaceName;
use zbus::zvariant::{Array, Dict, OwnedObjectPath, OwnedValue, Value as ZValue};

const BLUEZ_SERVICE: &str = "org.bluez";
const BLUEZ_ROOT: &str = "/";
const BLUEZ_ADAPTER_INTERFACE: &str = "org.bluez.Adapter1";
const BLUEZ_DEVICE_INTERFACE: &str = "org.bluez.Device1";
const BLUEZ_BATTERY_INTERFACE: &str = "org.bluez.Battery1";
const NETWORK_MANAGER_SERVICE: &str = "org.freedesktop.NetworkManager";
const NETWORK_MANAGER_PATH: &str = "/org/freedesktop/NetworkManager";
const NETWORK_MANAGER_INTERFACE: &str = "org.freedesktop.NetworkManager";
const POWER_PROFILES_SERVICE: &str = "org.freedesktop.UPower.PowerProfiles";
const POWER_PROFILES_PATH: &str = "/org/freedesktop/UPower/PowerProfiles";
const POWER_PROFILES_INTERFACE: &str = "org.freedesktop.UPower.PowerProfiles";
const LEGACY_POWER_PROFILES_SERVICE: &str = "net.hadess.PowerProfiles";
const LEGACY_POWER_PROFILES_PATH: &str = "/net/hadess/PowerProfiles";
const LEGACY_POWER_PROFILES_INTERFACE: &str = "net.hadess.PowerProfiles";
const HOSTNAME_SERVICE: &str = "org.freedesktop.hostname1";
const HOSTNAME_PATH: &str = "/org/freedesktop/hostname1";
const HOSTNAME_INTERFACE: &str = "org.freedesktop.hostname1";
const TIMEDATE_SERVICE: &str = "org.freedesktop.timedate1";
const TIMEDATE_PATH: &str = "/org/freedesktop/timedate1";
const TIMEDATE_INTERFACE: &str = "org.freedesktop.timedate1";
const LOGIN_SERVICE: &str = "org.freedesktop.login1";
const LOGIN_PATH: &str = "/org/freedesktop/login1";
const LOGIN_MANAGER_INTERFACE: &str = "org.freedesktop.login1.Manager";
const LOGIN_SESSION_INTERFACE: &str = "org.freedesktop.login1.Session";
const ZONEINFO_ROOT: &str = "/usr/share/zoneinfo";

type Properties = HashMap<String, OwnedValue>;
type Interfaces = HashMap<OwnedInterfaceName, Properties>;
type ManagedObjects = HashMap<OwnedObjectPath, Interfaces>;

#[derive(Debug)]
pub struct NativeError {
    pub code: String,
    pub message: String,
}

impl NativeError {
    fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }

    fn unavailable(service: &str) -> Self {
        Self::new(
            "service_unavailable",
            format!("the native service {service} is not available"),
        )
    }

    fn action(service: &str, error: impl std::fmt::Display) -> Self {
        Self::new(
            "native_action_failed",
            format!("{service} rejected the action: {error}"),
        )
    }
}

pub struct NativeBus {
    system: Option<Connection>,
    connection_error: Option<String>,
    known_names_cache: Mutex<Option<(Instant, HashSet<String>)>>,
}

impl NativeBus {
    pub fn connect() -> Self {
        match Connection::system() {
            Ok(connection) => Self {
                system: Some(connection),
                connection_error: None,
                known_names_cache: Mutex::new(None),
            },
            Err(error) => Self {
                system: None,
                connection_error: Some(error.to_string()),
                known_names_cache: Mutex::new(None),
            },
        }
    }

    fn connection(&self) -> Result<&Connection, NativeError> {
        self.system.as_ref().ok_or_else(|| {
            NativeError::new(
                "system_bus_unavailable",
                self.connection_error
                    .as_deref()
                    .unwrap_or("the system D-Bus is unavailable"),
            )
        })
    }

    pub fn service_available(&self, name: &str) -> bool {
        self.known_names()
            .map(|names| names.contains(name))
            .unwrap_or(false)
    }

    fn known_names(&self) -> Result<HashSet<String>, NativeError> {
        const MAX_AGE: Duration = Duration::from_secs(5);
        if let Some(names) = self
            .known_names_cache
            .lock()
            .ok()
            .and_then(|cache| cache.as_ref().cloned())
            .filter(|(created, _)| created.elapsed() <= MAX_AGE)
            .map(|(_, names)| names)
        {
            return Ok(names);
        }
        let connection = self.connection()?;
        let proxy = Proxy::new(
            connection,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
        )
        .map_err(|error| NativeError::action("D-Bus", error))?;
        let mut names: Vec<String> = proxy
            .call("ListNames", &())
            .map_err(|error| NativeError::action("D-Bus", error))?;
        let mut activatable: Vec<String> = proxy
            .call("ListActivatableNames", &())
            .map_err(|error| NativeError::action("D-Bus", error))?;
        names.append(&mut activatable);
        let names = names.into_iter().collect::<HashSet<_>>();
        if let Ok(mut cache) = self.known_names_cache.lock() {
            *cache = Some((Instant::now(), names.clone()));
        }
        Ok(names)
    }

    pub fn service_snapshot(&self) -> Value {
        let services = [
            ("bluez", BLUEZ_SERVICE),
            ("network_manager", NETWORK_MANAGER_SERVICE),
            ("upower", "org.freedesktop.UPower"),
            ("power_profiles", POWER_PROFILES_SERVICE),
            ("fwupd", "org.freedesktop.fwupd"),
            ("systemd_logind", "org.freedesktop.login1"),
            ("systemd", "org.freedesktop.systemd1"),
            ("resolved", "org.freedesktop.resolve1"),
            ("timesync", "org.freedesktop.timesync1"),
            ("hostname", HOSTNAME_SERVICE),
            ("timedate", TIMEDATE_SERVICE),
        ];
        let known_names = self.known_names().unwrap_or_default();
        let mut result = serde_json::Map::new();
        for (key, name) in services {
            result.insert(key.to_string(), json!(known_names.contains(name)));
        }
        Value::Object(result)
    }

    pub fn native_snapshot(&self) -> Value {
        json!({
            "services": self.service_snapshot(),
            "bluetooth": self.bluetooth_snapshot().unwrap_or_else(error_value),
            "network": self.network_snapshot().unwrap_or_else(error_value),
            "power_profile": self.power_profile().unwrap_or_else(error_value),
            "hostname": self.hostname_snapshot().unwrap_or_else(error_value),
            "time": self.time_snapshot().unwrap_or_else(error_value),
            "session": self.session_snapshot().unwrap_or_else(error_value),
        })
    }

    pub fn hostname_snapshot(&self) -> Result<Value, NativeError> {
        if !self.service_available(HOSTNAME_SERVICE) {
            return Err(NativeError::unavailable(HOSTNAME_SERVICE));
        }
        let proxy = Proxy::new(
            self.connection()?,
            HOSTNAME_SERVICE,
            HOSTNAME_PATH,
            HOSTNAME_INTERFACE,
        )
        .map_err(|error| NativeError::action(HOSTNAME_SERVICE, error))?;
        Ok(json!({
            "available": true,
            "hostname": optional_property::<String>(&proxy, "Hostname"),
            "static_hostname": optional_property::<String>(&proxy, "StaticHostname"),
            "pretty_hostname": optional_property::<String>(&proxy, "PrettyHostname"),
            "chassis": optional_property::<String>(&proxy, "Chassis"),
            "deployment": optional_property::<String>(&proxy, "Deployment"),
            "location": optional_property::<String>(&proxy, "Location"),
            "hardware_vendor": optional_property::<String>(&proxy, "HardwareVendor"),
            "hardware_model": optional_property::<String>(&proxy, "HardwareModel"),
            "firmware_version": optional_property::<String>(&proxy, "FirmwareVersion"),
            "operating_system_pretty_name": optional_property::<String>(&proxy, "OperatingSystemPrettyName"),
        }))
    }

    pub fn set_hostname(
        &self,
        hostname: Option<&str>,
        pretty_hostname: Option<&str>,
    ) -> Result<(), NativeError> {
        if hostname.is_none() && pretty_hostname.is_none() {
            return Err(NativeError::new(
                "invalid_params",
                "hostname or pretty_hostname must be provided",
            ));
        }
        if let Some(hostname) = hostname {
            validate_hostname(hostname)?;
        }
        if let Some(pretty_hostname) = pretty_hostname {
            validate_pretty_hostname(pretty_hostname)?;
        }
        if !self.service_available(HOSTNAME_SERVICE) {
            return Err(NativeError::unavailable(HOSTNAME_SERVICE));
        }
        let proxy = Proxy::new(
            self.connection()?,
            HOSTNAME_SERVICE,
            HOSTNAME_PATH,
            HOSTNAME_INTERFACE,
        )
        .map_err(|error| NativeError::action(HOSTNAME_SERVICE, error))?;
        if let Some(hostname) = hostname {
            let _: () = proxy
                .call("SetStaticHostname", &(hostname, true))
                .map_err(|error| NativeError::action(HOSTNAME_SERVICE, error))?;
        }
        if let Some(pretty_hostname) = pretty_hostname {
            let _: () = proxy
                .call("SetPrettyHostname", &(pretty_hostname, true))
                .map_err(|error| NativeError::action(HOSTNAME_SERVICE, error))?;
        }
        Ok(())
    }

    pub fn time_snapshot(&self) -> Result<Value, NativeError> {
        if !self.service_available(TIMEDATE_SERVICE) {
            return Err(NativeError::unavailable(TIMEDATE_SERVICE));
        }
        let proxy = Proxy::new(
            self.connection()?,
            TIMEDATE_SERVICE,
            TIMEDATE_PATH,
            TIMEDATE_INTERFACE,
        )
        .map_err(|error| NativeError::action(TIMEDATE_SERVICE, error))?;
        Ok(json!({
            "available": true,
            "timezone": optional_property::<String>(&proxy, "Timezone"),
            "local_rtc": optional_property::<bool>(&proxy, "LocalRTC"),
            "can_ntp": optional_property::<bool>(&proxy, "CanNTP"),
            "ntp": optional_property::<bool>(&proxy, "NTP"),
            "ntp_synchronized": optional_property::<bool>(&proxy, "NTPSynchronized"),
            "time_usec": optional_property::<u64>(&proxy, "TimeUSec"),
            "rtc_time_usec": optional_property::<u64>(&proxy, "RTCTimeUSec"),
        }))
    }

    pub fn set_ntp(&self, enabled: bool) -> Result<(), NativeError> {
        if !self.service_available(TIMEDATE_SERVICE) {
            return Err(NativeError::unavailable(TIMEDATE_SERVICE));
        }
        let proxy = Proxy::new(
            self.connection()?,
            TIMEDATE_SERVICE,
            TIMEDATE_PATH,
            TIMEDATE_INTERFACE,
        )
        .map_err(|error| NativeError::action(TIMEDATE_SERVICE, error))?;
        let _: () = proxy
            .call("SetNTP", &(enabled, true))
            .map_err(|error| NativeError::action(TIMEDATE_SERVICE, error))?;
        Ok(())
    }

    pub fn set_timezone(&self, timezone: &str) -> Result<(), NativeError> {
        validate_timezone(timezone)?;
        if !self.service_available(TIMEDATE_SERVICE) {
            return Err(NativeError::unavailable(TIMEDATE_SERVICE));
        }
        let proxy = Proxy::new(
            self.connection()?,
            TIMEDATE_SERVICE,
            TIMEDATE_PATH,
            TIMEDATE_INTERFACE,
        )
        .map_err(|error| NativeError::action(TIMEDATE_SERVICE, error))?;
        let _: () = proxy
            .call("SetTimezone", &(timezone, true))
            .map_err(|error| NativeError::action(TIMEDATE_SERVICE, error))?;
        Ok(())
    }

    pub fn session_snapshot(&self) -> Result<Value, NativeError> {
        if !self.service_available(LOGIN_SERVICE) {
            return Err(NativeError::unavailable(LOGIN_SERVICE));
        }
        let Some(session_id) = env::var("XDG_SESSION_ID")
            .ok()
            .filter(|value| !value.is_empty())
        else {
            return Ok(json!({
                "available": true,
                "current_session": null,
            }));
        };
        let path = self.session_path(&session_id)?;
        let proxy = Proxy::new(
            self.connection()?,
            LOGIN_SERVICE,
            path.as_str(),
            LOGIN_SESSION_INTERFACE,
        )
        .map_err(|error| NativeError::action(LOGIN_SERVICE, error))?;
        Ok(json!({
            "available": true,
            "current_session": {
                "id": session_id,
                "path": path.as_str(),
                "active": optional_property::<bool>(&proxy, "Active"),
                "state": optional_property::<String>(&proxy, "State"),
                "class": optional_property::<String>(&proxy, "Class"),
                "type": optional_property::<String>(&proxy, "Type"),
                "remote": optional_property::<bool>(&proxy, "Remote"),
                "idle_hint": optional_property::<bool>(&proxy, "IdleHint"),
                "locked_hint": optional_property::<bool>(&proxy, "LockedHint"),
                "vt_number": optional_property::<u32>(&proxy, "VTNr"),
            }
        }))
    }

    pub fn lock_session(&self) -> Result<(), NativeError> {
        if !self.service_available(LOGIN_SERVICE) {
            return Err(NativeError::unavailable(LOGIN_SERVICE));
        }
        let session_id = env::var("XDG_SESSION_ID")
            .ok()
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                NativeError::new(
                    "session_unavailable",
                    "XDG_SESSION_ID is not available to the service",
                )
            })?;
        let manager = Proxy::new(
            self.connection()?,
            LOGIN_SERVICE,
            LOGIN_PATH,
            LOGIN_MANAGER_INTERFACE,
        )
        .map_err(|error| NativeError::action(LOGIN_SERVICE, error))?;
        let _: () = manager
            .call("LockSession", &(session_id,))
            .map_err(|error| NativeError::action(LOGIN_SERVICE, error))?;
        Ok(())
    }

    fn session_path(&self, session_id: &str) -> Result<OwnedObjectPath, NativeError> {
        let manager = Proxy::new(
            self.connection()?,
            LOGIN_SERVICE,
            LOGIN_PATH,
            LOGIN_MANAGER_INTERFACE,
        )
        .map_err(|error| NativeError::action(LOGIN_SERVICE, error))?;
        manager
            .call("GetSession", &(session_id,))
            .map_err(|error| NativeError::action(LOGIN_SERVICE, error))
    }

    pub fn bluetooth_snapshot(&self) -> Result<Value, NativeError> {
        if !self.service_available(BLUEZ_SERVICE) {
            return Err(NativeError::unavailable(BLUEZ_SERVICE));
        }
        let connection = self.connection()?;
        let manager = Proxy::new(
            connection,
            BLUEZ_SERVICE,
            BLUEZ_ROOT,
            "org.freedesktop.DBus.ObjectManager",
        )
        .map_err(|error| NativeError::action(BLUEZ_SERVICE, error))?;
        let objects: ManagedObjects = manager
            .call("GetManagedObjects", &())
            .map_err(|error| NativeError::action(BLUEZ_SERVICE, error))?;

        let mut adapters = Vec::new();
        let mut devices = Vec::new();
        for (path, interfaces) in &objects {
            if let Some(properties) = interface_properties(interfaces, BLUEZ_ADAPTER_INTERFACE) {
                adapters.push(json!({
                    "path": path.as_str(),
                    "id": path.as_str().rsplit('/').next().unwrap_or(""),
                    "address": property_string(properties, "Address"),
                    "address_type": property_string(properties, "AddressType"),
                    "name": property_string(properties, "Name"),
                    "alias": property_string(properties, "Alias"),
                    "modalias": property_string(properties, "Modalias"),
                    "class": property_u32(properties, "Class"),
                    "powered": property_bool(properties, "Powered"),
                    "discoverable": property_bool(properties, "Discoverable"),
                    "discoverable_timeout": property_u32(properties, "DiscoverableTimeout"),
                    "pairable": property_bool(properties, "Pairable"),
                    "pairable_timeout": property_u32(properties, "PairableTimeout"),
                    "discovering": property_bool(properties, "Discovering"),
                    "uuids": property_strings(properties, "UUIDs"),
                }));
            }
            if let Some(properties) = interface_properties(interfaces, BLUEZ_DEVICE_INTERFACE) {
                let battery = interface_properties(interfaces, BLUEZ_BATTERY_INTERFACE);
                devices.push(json!({
                    "path": path.as_str(),
                    "adapter": property_object_path(properties, "Adapter"),
                    "address": property_string(properties, "Address"),
                    "address_type": property_string(properties, "AddressType"),
                    "name": property_string(properties, "Name"),
                    "alias": property_string(properties, "Alias"),
                    "icon": property_string(properties, "Icon"),
                    "modalias": property_string(properties, "Modalias"),
                    "class": property_u32(properties, "Class"),
                    "appearance": property_u16(properties, "Appearance"),
                    "paired": property_bool(properties, "Paired"),
                    "bonded": property_bool(properties, "Bonded"),
                    "trusted": property_bool(properties, "Trusted"),
                    "blocked": property_bool(properties, "Blocked"),
                    "connected": property_bool(properties, "Connected"),
                    "services_resolved": property_bool(properties, "ServicesResolved"),
                    "rssi": property_i16(properties, "RSSI"),
                    "tx_power": property_i16(properties, "TxPower"),
                    "wake_allowed": property_bool(properties, "WakeAllowed"),
                    "battery_percent": battery.and_then(|value| property_u8(value, "Percentage")),
                    "uuids": property_strings(properties, "UUIDs"),
                }));
            }
        }
        adapters.sort_by(|left, right| json_string(left, "path").cmp(json_string(right, "path")));
        devices.sort_by(|left, right| {
            json_string(left, "alias")
                .cmp(json_string(right, "alias"))
                .then_with(|| json_string(left, "address").cmp(json_string(right, "address")))
        });

        Ok(json!({
            "available": true,
            "adapters": adapters,
            "devices": devices,
        }))
    }

    pub fn set_bluetooth_powered(&self, adapter: &str, powered: bool) -> Result<(), NativeError> {
        self.set_adapter_property(adapter, "Powered", powered)
    }

    pub fn set_bluetooth_discoverable(
        &self,
        adapter: &str,
        enabled: bool,
        timeout_seconds: Option<u32>,
    ) -> Result<(), NativeError> {
        if let Some(timeout) = timeout_seconds {
            self.set_adapter_property(adapter, "DiscoverableTimeout", timeout)?;
        }
        self.set_adapter_property(adapter, "Discoverable", enabled)
    }

    pub fn set_bluetooth_pairable(
        &self,
        adapter: &str,
        enabled: bool,
        timeout_seconds: Option<u32>,
    ) -> Result<(), NativeError> {
        if let Some(timeout) = timeout_seconds {
            self.set_adapter_property(adapter, "PairableTimeout", timeout)?;
        }
        self.set_adapter_property(adapter, "Pairable", enabled)
    }

    fn set_adapter_property<T>(
        &self,
        adapter: &str,
        property: &str,
        value: T,
    ) -> Result<(), NativeError>
    where
        T: Into<zbus::zvariant::Value<'static>> + 'static,
    {
        if !self.service_available(BLUEZ_SERVICE) {
            return Err(NativeError::unavailable(BLUEZ_SERVICE));
        }
        let path = adapter_object_path(adapter)?;
        let proxy = Proxy::new(
            self.connection()?,
            BLUEZ_SERVICE,
            path.as_str(),
            BLUEZ_ADAPTER_INTERFACE,
        )
        .map_err(|error| NativeError::action(BLUEZ_SERVICE, error))?;
        proxy
            .set_property(property, value)
            .map_err(|error| NativeError::action(BLUEZ_SERVICE, error))
    }

    pub fn network_snapshot(&self) -> Result<Value, NativeError> {
        if !self.service_available(NETWORK_MANAGER_SERVICE) {
            return Err(NativeError::unavailable(NETWORK_MANAGER_SERVICE));
        }
        let proxy = Proxy::new(
            self.connection()?,
            NETWORK_MANAGER_SERVICE,
            NETWORK_MANAGER_PATH,
            NETWORK_MANAGER_INTERFACE,
        )
        .map_err(|error| NativeError::action(NETWORK_MANAGER_SERVICE, error))?;
        let state: u32 = get_property(&proxy, "State", NETWORK_MANAGER_SERVICE)?;
        let connectivity: u32 = get_property(&proxy, "Connectivity", NETWORK_MANAGER_SERVICE)?;
        let networking_enabled: bool =
            get_property(&proxy, "NetworkingEnabled", NETWORK_MANAGER_SERVICE)?;
        let wireless_enabled: bool =
            get_property(&proxy, "WirelessEnabled", NETWORK_MANAGER_SERVICE)?;
        let wireless_hardware_enabled: bool =
            get_property(&proxy, "WirelessHardwareEnabled", NETWORK_MANAGER_SERVICE)?;
        Ok(json!({
            "available": true,
            "state": state,
            "state_name": network_state_name(state),
            "connectivity": connectivity,
            "connectivity_name": connectivity_name(connectivity),
            "networking_enabled": networking_enabled,
            "wireless_enabled": wireless_enabled,
            "wireless_hardware_enabled": wireless_hardware_enabled,
        }))
    }

    pub fn set_wireless_enabled(&self, enabled: bool) -> Result<(), NativeError> {
        if !self.service_available(NETWORK_MANAGER_SERVICE) {
            return Err(NativeError::unavailable(NETWORK_MANAGER_SERVICE));
        }
        let proxy = Proxy::new(
            self.connection()?,
            NETWORK_MANAGER_SERVICE,
            NETWORK_MANAGER_PATH,
            NETWORK_MANAGER_INTERFACE,
        )
        .map_err(|error| NativeError::action(NETWORK_MANAGER_SERVICE, error))?;
        proxy
            .set_property("WirelessEnabled", enabled)
            .map_err(|error| NativeError::action(NETWORK_MANAGER_SERVICE, error))
    }

    pub fn power_profile(&self) -> Result<Value, NativeError> {
        let (service, path, interface) = self.power_profile_endpoint()?;
        let proxy = Proxy::new(self.connection()?, service, path, interface)
            .map_err(|error| NativeError::action(service, error))?;
        let active_profile: String = get_property(&proxy, "ActiveProfile", service)?;
        let performance_degraded: String = proxy
            .get_property("PerformanceDegraded")
            .unwrap_or_default();
        let mut profiles = proxy
            .get_property::<OwnedValue>("Profiles")
            .ok()
            .map(profile_names)
            .unwrap_or_default();
        if !profiles.iter().any(|profile| profile == &active_profile) {
            profiles.push(active_profile.clone());
            profiles.sort();
            profiles.dedup();
        }
        Ok(json!({
            "available": true,
            "active_profile": active_profile,
            "profiles": profiles,
            "performance_degraded": performance_degraded,
        }))
    }

    pub fn set_power_profile(&self, profile: &str) -> Result<(), NativeError> {
        let (service, path, interface) = self.power_profile_endpoint()?;
        let proxy = Proxy::new(self.connection()?, service, path, interface)
            .map_err(|error| NativeError::action(service, error))?;
        proxy
            .set_property("ActiveProfile", profile)
            .map_err(|error| NativeError::action(service, error))
    }

    fn power_profile_endpoint(
        &self,
    ) -> Result<(&'static str, &'static str, &'static str), NativeError> {
        if self.service_available(POWER_PROFILES_SERVICE) {
            Ok((
                POWER_PROFILES_SERVICE,
                POWER_PROFILES_PATH,
                POWER_PROFILES_INTERFACE,
            ))
        } else if self.service_available(LEGACY_POWER_PROFILES_SERVICE) {
            Ok((
                LEGACY_POWER_PROFILES_SERVICE,
                LEGACY_POWER_PROFILES_PATH,
                LEGACY_POWER_PROFILES_INTERFACE,
            ))
        } else {
            Err(NativeError::unavailable(POWER_PROFILES_SERVICE))
        }
    }
}

fn get_property<T>(proxy: &Proxy<'_>, name: &str, service: &str) -> Result<T, NativeError>
where
    T: TryFrom<OwnedValue>,
    T::Error: Into<zbus::Error>,
{
    proxy
        .get_property(name)
        .map_err(|error| NativeError::action(service, error))
}

fn optional_property<T>(proxy: &Proxy<'_>, name: &str) -> Option<T>
where
    T: TryFrom<OwnedValue>,
    T::Error: Into<zbus::Error>,
{
    proxy.get_property(name).ok()
}

fn interface_properties<'a>(interfaces: &'a Interfaces, name: &str) -> Option<&'a Properties> {
    interfaces
        .iter()
        .find(|(interface, _)| interface.as_str() == name)
        .map(|(_, properties)| properties)
}

fn property_string(properties: &Properties, key: &str) -> Option<String> {
    properties
        .get(key)
        .and_then(|value| <&str>::try_from(value).ok())
        .map(str::to_string)
}

fn property_object_path(properties: &Properties, key: &str) -> Option<String> {
    properties
        .get(key)
        .and_then(|value| <&zbus::zvariant::ObjectPath<'_>>::try_from(value).ok())
        .map(ToString::to_string)
}

macro_rules! numeric_property {
    ($name:ident, $type:ty) => {
        fn $name(properties: &Properties, key: &str) -> Option<$type> {
            properties
                .get(key)
                .and_then(|value| <$type>::try_from(value).ok())
        }
    };
}

numeric_property!(property_u8, u8);
numeric_property!(property_u16, u16);
numeric_property!(property_i16, i16);
numeric_property!(property_u32, u32);
numeric_property!(property_bool, bool);

fn property_strings(properties: &Properties, key: &str) -> Vec<String> {
    let Some(value) = properties.get(key) else {
        return Vec::new();
    };
    let Ok(array) = <&Array<'_>>::try_from(value) else {
        return Vec::new();
    };
    array
        .inner()
        .iter()
        .filter_map(|value| <&str>::try_from(value).ok().map(str::to_string))
        .collect()
}

fn profile_names(value: OwnedValue) -> Vec<String> {
    let Ok(array) = Array::try_from(value) else {
        return Vec::new();
    };
    let mut profiles = Vec::new();
    for value in array.inner() {
        let Ok(dictionary) = <&Dict<'_, '_>>::try_from(value) else {
            continue;
        };
        for (key, value) in dictionary.iter() {
            if variant_string(key) == Some("Profile") {
                if let Some(profile) = variant_string(value) {
                    profiles.push(profile.to_string());
                }
            }
        }
    }
    profiles.sort();
    profiles.dedup();
    profiles
}

fn variant_string<'a>(value: &'a ZValue<'_>) -> Option<&'a str> {
    match value {
        ZValue::Value(inner) => variant_string(inner),
        _ => <&str>::try_from(value).ok(),
    }
}

fn adapter_object_path(adapter: &str) -> Result<String, NativeError> {
    let id = adapter.strip_prefix("/org/bluez/").unwrap_or(adapter);
    let Some(number) = id.strip_prefix("hci") else {
        return Err(NativeError::new(
            "invalid_params",
            "adapter must be hci followed by digits, for example hci0",
        ));
    };
    if number.is_empty() || !number.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(NativeError::new(
            "invalid_params",
            "adapter must be hci followed by digits, for example hci0",
        ));
    }
    Ok(format!("/org/bluez/{id}"))
}

fn network_state_name(state: u32) -> &'static str {
    match state {
        10 => "asleep",
        20 => "disconnected",
        30 => "disconnecting",
        40 => "connecting",
        50 => "connected-local",
        60 => "connected-site",
        70 => "connected-global",
        _ => "unknown",
    }
}

fn connectivity_name(connectivity: u32) -> &'static str {
    match connectivity {
        1 => "none",
        2 => "portal",
        3 => "limited",
        4 => "full",
        _ => "unknown",
    }
}

fn validate_timezone(timezone: &str) -> Result<(), NativeError> {
    if timezone.is_empty()
        || timezone.len() > 255
        || timezone.starts_with('/')
        || timezone
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
        || !timezone
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'_' | b'-' | b'+'))
    {
        return Err(NativeError::new(
            "invalid_params",
            "timezone must be a valid relative IANA time-zone name",
        ));
    }

    let root = fs::canonicalize(Path::new(ZONEINFO_ROOT)).map_err(|error| {
        NativeError::new(
            "zoneinfo_unavailable",
            format!("cannot access {ZONEINFO_ROOT}: {error}"),
        )
    })?;
    let candidate = fs::canonicalize(root.join(timezone)).map_err(|_| {
        NativeError::new("invalid_params", format!("unknown time zone: {timezone}"))
    })?;
    if !candidate.starts_with(&root)
        || !fs::metadata(&candidate)
            .map(|metadata| metadata.is_file())
            .unwrap_or(false)
    {
        return Err(NativeError::new(
            "invalid_params",
            "timezone must resolve to a regular file inside /usr/share/zoneinfo",
        ));
    }
    let mut file = File::open(&candidate).map_err(|_| {
        NativeError::new(
            "invalid_params",
            format!("time-zone data is not readable: {timezone}"),
        )
    })?;
    let mut magic = [0_u8; 4];
    file.read_exact(&mut magic).map_err(|_| {
        NativeError::new(
            "invalid_params",
            format!("invalid time-zone data: {timezone}"),
        )
    })?;
    if &magic != b"TZif" {
        return Err(NativeError::new(
            "invalid_params",
            format!("not a binary IANA time zone: {timezone}"),
        ));
    }
    Ok(())
}

fn validate_hostname(hostname: &str) -> Result<(), NativeError> {
    let valid = !hostname.is_empty()
        && hostname.len() <= 64
        && hostname.is_ascii()
        && hostname.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && label
                    .as_bytes()
                    .first()
                    .is_some_and(u8::is_ascii_alphanumeric)
                && label
                    .as_bytes()
                    .last()
                    .is_some_and(u8::is_ascii_alphanumeric)
                && label
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        });
    if !valid {
        return Err(NativeError::new(
            "invalid_params",
            "hostname must be 1-64 ASCII characters in DNS-label form",
        ));
    }
    Ok(())
}

fn validate_pretty_hostname(pretty_hostname: &str) -> Result<(), NativeError> {
    let unsafe_format = |character| {
        matches!(
            character,
            '\u{2028}'
                | '\u{2029}'
                | '\u{202a}'..='\u{202e}'
                | '\u{2066}'..='\u{2069}'
        )
    };
    if pretty_hostname.is_empty()
        || pretty_hostname.len() > 256
        || pretty_hostname.chars().count() > 64
        || pretty_hostname.trim() != pretty_hostname
        || pretty_hostname
            .chars()
            .any(|character| character.is_control() || unsafe_format(character))
    {
        return Err(NativeError::new(
            "invalid_params",
            "pretty_hostname must be 1-64 readable characters without controls or surrounding whitespace",
        ));
    }
    Ok(())
}

fn json_string<'a>(value: &'a Value, key: &str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or("")
}

fn error_value(error: NativeError) -> Value {
    json!({
        "available": false,
        "error": {
            "code": error.code,
            "message": error.message,
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adapter_id_and_object_path_are_accepted() {
        assert_eq!(adapter_object_path("hci0").unwrap(), "/org/bluez/hci0");
        assert_eq!(
            adapter_object_path("/org/bluez/hci12").unwrap(),
            "/org/bluez/hci12"
        );
    }

    #[test]
    fn unsafe_adapter_paths_are_rejected() {
        for value in ["hci", "hci-1", "../hci0", "/org/bluez/hci0/dev_01"] {
            assert!(adapter_object_path(value).is_err(), "accepted {value}");
        }
    }

    #[test]
    fn network_states_have_stable_names() {
        assert_eq!(network_state_name(70), "connected-global");
        assert_eq!(connectivity_name(2), "portal");
        assert_eq!(connectivity_name(99), "unknown");
    }

    #[test]
    fn known_binary_timezone_is_accepted() {
        assert!(validate_timezone("Etc/UTC").is_ok());
    }

    #[test]
    fn timezone_traversal_and_metadata_files_are_rejected() {
        for value in [
            "../etc/passwd",
            "/etc/localtime",
            "Europe//London",
            "Europe/./London",
            "zone.tab",
            "Europe/London\0ignored",
        ] {
            assert!(validate_timezone(value).is_err(), "accepted {value:?}");
        }
    }

    #[test]
    fn dns_style_hostnames_are_validated() {
        for value in ["workstation", "studio-pc", "desk.example"] {
            assert!(validate_hostname(value).is_ok(), "rejected {value:?}");
        }
        for value in [
            "",
            "-desk",
            "desk-",
            ".desk",
            "desk..example",
            "desk_name",
            "café",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        ] {
            assert!(validate_hostname(value).is_err(), "accepted {value:?}");
        }
    }

    #[test]
    fn readable_unicode_pretty_hostnames_are_supported() {
        assert!(validate_pretty_hostname("Linmax Studio ✨").is_ok());
        for value in ["", " padded", "line\nbreak", "spoof\u{202e}name"] {
            assert!(
                validate_pretty_hostname(value).is_err(),
                "accepted {value:?}"
            );
        }
    }

    #[test]
    fn power_profile_names_unwrap_dictionary_variants() {
        let mut profile = Dict::new(
            &zbus::zvariant::Signature::Str,
            &zbus::zvariant::Signature::Variant,
        );
        profile
            .append(
                ZValue::from("Profile"),
                ZValue::Value(Box::new(ZValue::from("balanced"))),
            )
            .unwrap();
        let mut profiles = Array::new(profile.signature());
        profiles.append(ZValue::Dict(profile)).unwrap();
        let value = OwnedValue::try_from(ZValue::Array(profiles)).unwrap();

        assert_eq!(profile_names(value), ["balanced"]);
    }
}
