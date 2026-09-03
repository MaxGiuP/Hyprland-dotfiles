use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::native_bus::NativeBus;
use crate::system;

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAX_REQUEST_BYTES: usize = 1024 * 1024;

#[derive(Debug, Deserialize, Serialize)]
pub struct Request {
    #[serde(default)]
    pub id: Value,
    pub method: String,
    #[serde(default = "empty_object")]
    pub params: Value,
}

fn empty_object() -> Value {
    json!({})
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Response {
    pub id: Value,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ApiError>,
}

impl Response {
    pub fn success(id: Value, result: Value) -> Self {
        Self {
            id,
            ok: true,
            result: Some(result),
            error: None,
        }
    }

    pub fn failure(id: Value, error: ApiError) -> Self {
        Self {
            id,
            ok: false,
            result: None,
            error: Some(error),
        }
    }
}

#[derive(Debug, Deserialize, Serialize)]
pub struct ApiError {
    pub code: String,
    pub message: String,
}

impl ApiError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }

    pub fn invalid_params(message: impl Into<String>) -> Self {
        Self::new("invalid_params", message)
    }
}

impl From<crate::native_bus::NativeError> for ApiError {
    fn from(error: crate::native_bus::NativeError) -> Self {
        Self::new(error.code, error.message)
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AdapterPowerParams {
    #[serde(default = "default_adapter")]
    adapter: String,
    powered: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AdapterVisibilityParams {
    #[serde(default = "default_adapter")]
    adapter: String,
    enabled: bool,
    #[serde(default)]
    timeout_seconds: Option<u32>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct WirelessParams {
    enabled: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EnabledParams {
    enabled: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct TimezoneParams {
    timezone: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct HostnameParams {
    #[serde(default)]
    hostname: Option<String>,
    #[serde(default)]
    pretty_hostname: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PowerProfileParams {
    profile: String,
}

fn default_adapter() -> String {
    "hci0".to_string()
}

pub struct State {
    started: Instant,
    bus: NativeBus,
    snapshot_cache: Mutex<Option<(Instant, Value)>>,
    capabilities_cache: Mutex<Option<(Instant, Value)>>,
}

impl State {
    pub fn new() -> Self {
        Self {
            started: Instant::now(),
            bus: NativeBus::connect(),
            snapshot_cache: Mutex::new(None),
            capabilities_cache: Mutex::new(None),
        }
    }

    pub fn dispatch(&self, request: Request) -> Response {
        let id = request.id;
        let result = self.handle(&request.method, request.params);
        match result {
            Ok(value) => Response::success(id, value),
            Err(error) => Response::failure(id, error),
        }
    }

    fn handle(&self, method: &str, params: Value) -> Result<Value, ApiError> {
        match method {
            "ping" => Ok(json!({
                "service": "ii-settingsd",
                "version": env!("CARGO_PKG_VERSION"),
                "protocol_version": PROTOCOL_VERSION,
                "uptime_ms": self.started.elapsed().as_millis(),
            })),
            "protocol.describe" => Ok(protocol_description()),
            "snapshot" => self.snapshot(),
            "capabilities" => self.capabilities(),
            "bluetooth.snapshot" => self.bus.bluetooth_snapshot().map_err(Into::into),
            "bluetooth.set_powered" => {
                let params: AdapterPowerParams = parse_params(params)?;
                self.bus
                    .set_bluetooth_powered(&params.adapter, params.powered)?;
                self.invalidate_snapshot();
                Ok(json!({ "adapter": params.adapter, "powered": params.powered }))
            }
            "bluetooth.set_discoverable" => {
                let params: AdapterVisibilityParams = parse_params(params)?;
                validate_timeout(params.timeout_seconds)?;
                self.bus.set_bluetooth_discoverable(
                    &params.adapter,
                    params.enabled,
                    params.timeout_seconds,
                )?;
                self.invalidate_snapshot();
                Ok(json!({
                    "adapter": params.adapter,
                    "discoverable": params.enabled,
                    "timeout_seconds": params.timeout_seconds,
                }))
            }
            "bluetooth.set_pairable" => {
                let params: AdapterVisibilityParams = parse_params(params)?;
                validate_timeout(params.timeout_seconds)?;
                self.bus.set_bluetooth_pairable(
                    &params.adapter,
                    params.enabled,
                    params.timeout_seconds,
                )?;
                self.invalidate_snapshot();
                Ok(json!({
                    "adapter": params.adapter,
                    "pairable": params.enabled,
                    "timeout_seconds": params.timeout_seconds,
                }))
            }
            "network.set_wireless_enabled" => {
                let params: WirelessParams = parse_params(params)?;
                self.bus.set_wireless_enabled(params.enabled)?;
                self.invalidate_snapshot();
                Ok(json!({ "wireless_enabled": params.enabled }))
            }
            "time.set_ntp" => {
                let params: EnabledParams = parse_params(params)?;
                self.bus.set_ntp(params.enabled)?;
                self.invalidate_snapshot();
                Ok(json!({ "ntp": params.enabled }))
            }
            "time.set_timezone" => {
                let params: TimezoneParams = parse_params(params)?;
                self.bus.set_timezone(&params.timezone)?;
                self.invalidate_snapshot();
                Ok(json!({ "timezone": params.timezone }))
            }
            "hostname.set" => {
                let params: HostnameParams = parse_params(params)?;
                self.bus.set_hostname(
                    params.hostname.as_deref(),
                    params.pretty_hostname.as_deref(),
                )?;
                self.invalidate_snapshot();
                Ok(json!({
                    "hostname": params.hostname,
                    "pretty_hostname": params.pretty_hostname,
                }))
            }
            "session.lock" => {
                ensure_empty_params(&params)?;
                self.bus.lock_session()?;
                Ok(json!({ "locked": true }))
            }
            "power.profile" => self.bus.power_profile().map_err(Into::into),
            "power.set_profile" => {
                let params: PowerProfileParams = parse_params(params)?;
                if !matches!(
                    params.profile.as_str(),
                    "power-saver" | "balanced" | "performance"
                ) {
                    return Err(ApiError::invalid_params(
                        "profile must be power-saver, balanced, or performance",
                    ));
                }
                self.bus.set_power_profile(&params.profile)?;
                self.invalidate_snapshot();
                Ok(json!({ "active_profile": params.profile }))
            }
            _ => Err(ApiError::new(
                "method_not_found",
                format!("unknown method: {method}"),
            )),
        }
    }

    fn snapshot(&self) -> Result<Value, ApiError> {
        const MAX_AGE: Duration = Duration::from_millis(750);
        if let Some(cached) = read_cache(&self.snapshot_cache, MAX_AGE) {
            return Ok(cached);
        }
        let value = system::snapshot(&self.bus)
            .map_err(|error| ApiError::new("snapshot_failed", error.to_string()))?;
        write_cache(&self.snapshot_cache, value.clone());
        Ok(value)
    }

    fn capabilities(&self) -> Result<Value, ApiError> {
        const MAX_AGE: Duration = Duration::from_secs(15);
        if let Some(cached) = read_cache(&self.capabilities_cache, MAX_AGE) {
            return Ok(cached);
        }
        let value = system::capabilities(&self.bus);
        write_cache(&self.capabilities_cache, value.clone());
        Ok(value)
    }

    fn invalidate_snapshot(&self) {
        if let Ok(mut cache) = self.snapshot_cache.lock() {
            *cache = None;
        }
    }
}

fn parse_params<T: for<'de> Deserialize<'de>>(value: Value) -> Result<T, ApiError> {
    serde_json::from_value(value).map_err(|error| ApiError::invalid_params(error.to_string()))
}

fn validate_timeout(timeout: Option<u32>) -> Result<(), ApiError> {
    if timeout.is_some_and(|seconds| seconds > 3600) {
        return Err(ApiError::invalid_params(
            "timeout_seconds must be no greater than 3600",
        ));
    }
    Ok(())
}

fn ensure_empty_params(params: &Value) -> Result<(), ApiError> {
    if params.as_object().is_some_and(serde_json::Map::is_empty) {
        Ok(())
    } else {
        Err(ApiError::invalid_params("this method takes no parameters"))
    }
}

fn read_cache(cache: &Mutex<Option<(Instant, Value)>>, max_age: Duration) -> Option<Value> {
    cache
        .lock()
        .ok()
        .and_then(|guard| guard.as_ref().cloned())
        .filter(|(created, _)| created.elapsed() <= max_age)
        .map(|(_, value)| value)
}

fn write_cache(cache: &Mutex<Option<(Instant, Value)>>, value: Value) {
    if let Ok(mut cache) = cache.lock() {
        *cache = Some((Instant::now(), value));
    }
}

fn protocol_description() -> Value {
    json!({
        "protocol_version": PROTOCOL_VERSION,
        "transport": "unix-socket-json-lines",
        "maximum_request_bytes": MAX_REQUEST_BYTES,
        "methods": {
            "ping": {},
            "protocol.describe": {},
            "snapshot": {},
            "capabilities": {},
            "bluetooth.snapshot": {},
            "bluetooth.set_powered": {
                "params": { "adapter": "hci0", "powered": true }
            },
            "bluetooth.set_discoverable": {
                "params": { "adapter": "hci0", "enabled": true, "timeout_seconds": 180 }
            },
            "bluetooth.set_pairable": {
                "params": { "adapter": "hci0", "enabled": true, "timeout_seconds": 180 }
            },
            "network.set_wireless_enabled": {
                "params": { "enabled": true }
            },
            "time.set_ntp": {
                "params": { "enabled": true }
            },
            "time.set_timezone": {
                "params": { "timezone": "Europe/London" }
            },
            "hostname.set": {
                "params": { "hostname": "workstation", "pretty_hostname": "My Workstation" }
            },
            "session.lock": {},
            "power.profile": {},
            "power.set_profile": {
                "params": { "profile": "balanced" }
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn response_preserves_string_id() {
        let response = Response::success(json!("settings-42"), json!({ "ready": true }));
        let encoded = serde_json::to_value(response).unwrap();
        assert_eq!(encoded["id"], "settings-42");
        assert_eq!(encoded["ok"], true);
    }

    #[test]
    fn visibility_timeout_is_bounded() {
        assert!(validate_timeout(Some(3600)).is_ok());
        assert!(validate_timeout(Some(3601)).is_err());
    }

    #[test]
    fn unknown_request_fields_are_tolerated_for_forward_compatibility() {
        let request: Request = serde_json::from_value(json!({
            "id": 7,
            "method": "ping",
            "params": {},
            "future": true
        }))
        .unwrap();
        assert_eq!(request.method, "ping");
    }
}
