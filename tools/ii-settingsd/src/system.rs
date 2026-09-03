use std::collections::BTreeMap;
use std::env;
use std::ffi::CString;
use std::fs;
use std::io;
use std::mem::MaybeUninit;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{Map, Value, json};

use crate::native_bus::NativeBus;

pub fn snapshot(bus: &NativeBus) -> io::Result<Value> {
    let generated_at_unix_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_millis();
    Ok(json!({
        "schema_version": 1,
        "generated_at_unix_ms": generated_at_unix_ms,
        "host": host_snapshot(),
        "time": time_snapshot(),
        "resources": resource_snapshot(),
        "storage": storage_snapshot(),
        "power": power_snapshot(),
        "thermal": thermal_snapshot(),
        "displays": display_snapshot(),
        "network_interfaces": network_interfaces(),
        "security": security_snapshot(),
        "session": session_snapshot(),
        "native": bus.native_snapshot(),
        "capabilities": capabilities(bus),
    }))
}

pub fn capabilities(bus: &NativeBus) -> Value {
    let commands = [
        "brightnessctl",
        "flatpak",
        "fwupdmgr",
        "hyprctl",
        "localectl",
        "loginctl",
        "pacman",
        "timedatectl",
        "wpctl",
    ];
    let mut command_map = Map::new();
    for command in commands {
        command_map.insert(command.to_string(), json!(command_exists(command)));
    }

    let services = bus.service_snapshot();
    let service = |name: &str| services.get(name).and_then(Value::as_bool).unwrap_or(false);
    json!({
        "schema_version": 1,
        "transport": {
            "unix_socket": true,
            "peer_uid_checked": true,
            "json_lines": true,
        },
        "services": services,
        "kernel_interfaces": {
            "backlight": path_has_entries(Path::new("/sys/class/backlight")),
            "bluetooth": path_has_entries(Path::new("/sys/class/bluetooth")),
            "drm": path_has_entries(Path::new("/sys/class/drm")),
            "network": path_has_entries(Path::new("/sys/class/net")),
            "power_supply": path_has_entries(Path::new("/sys/class/power_supply")),
            "thermal": path_has_entries(Path::new("/sys/class/thermal")),
        },
        "commands": command_map,
        "features": {
            "bluetooth_read": service("bluez"),
            "bluetooth_control": service("bluez"),
            "network_read": service("network_manager"),
            "wireless_control": service("network_manager"),
            "power_profiles": service("power_profiles"),
            "firmware_updates": service("fwupd"),
            "session_control": service("systemd_logind"),
            "host_inventory": service("hostname"),
            "hostname_control": service("hostname"),
            "time_read": service("timedate"),
            "network_time_control": service("timedate"),
            "timezone_control": service("timedate"),
            "resource_metrics": Path::new("/proc/meminfo").is_file(),
            "display_inventory": Path::new("/sys/class/drm").is_dir(),
        }
    })
}

fn host_snapshot() -> Value {
    let os_release = parse_key_value_file(Path::new("/etc/os-release"));
    let cpuinfo = fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
    let cpu_model = cpuinfo.lines().find_map(|line| {
        let (key, value) = line.split_once(':')?;
        matches!(key.trim(), "model name" | "Hardware" | "Processor")
            .then(|| value.trim().to_string())
    });
    let logical_cpus = cpuinfo
        .lines()
        .filter(|line| line.starts_with("processor") && line.contains(':'))
        .count();
    json!({
        "hostname": read_trimmed("/proc/sys/kernel/hostname"),
        "kernel_name": read_trimmed("/proc/sys/kernel/ostype"),
        "kernel_release": read_trimmed("/proc/sys/kernel/osrelease"),
        "architecture": env::consts::ARCH,
        "boot_id": read_trimmed("/proc/sys/kernel/random/boot_id"),
        "os": {
            "id": os_release.get("ID"),
            "name": os_release.get("NAME"),
            "pretty_name": os_release.get("PRETTY_NAME"),
            "version_id": os_release.get("VERSION_ID"),
        },
        "cpu": {
            "model": cpu_model,
            "logical_count": logical_cpus,
        },
        "hardware": {
            "vendor": read_trimmed("/sys/class/dmi/id/sys_vendor"),
            "model": read_trimmed("/sys/class/dmi/id/product_name"),
            "board_vendor": read_trimmed("/sys/class/dmi/id/board_vendor"),
            "board_name": read_trimmed("/sys/class/dmi/id/board_name"),
            "firmware_version": read_trimmed("/sys/class/dmi/id/bios_version"),
        }
    })
}

fn time_snapshot() -> Value {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0);
    let timezone = fs::read_link("/etc/localtime")
        .ok()
        .and_then(|path| {
            path.to_string_lossy()
                .split("/zoneinfo/")
                .nth(1)
                .map(str::to_string)
        })
        .or_else(|| read_trimmed("/etc/timezone"));
    json!({
        "unix_ms": now,
        "timezone": timezone,
    })
}

fn resource_snapshot() -> Value {
    let meminfo = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let memory = parse_meminfo(&meminfo);
    let load = fs::read_to_string("/proc/loadavg")
        .ok()
        .map(|text| {
            text.split_whitespace()
                .take(3)
                .filter_map(|value| value.parse::<f64>().ok())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let uptime_seconds = fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|text| text.split_whitespace().next()?.parse::<f64>().ok());
    json!({
        "memory": {
            "total_bytes": memory.get("MemTotal").copied(),
            "available_bytes": memory.get("MemAvailable").copied(),
            "free_bytes": memory.get("MemFree").copied(),
            "cached_bytes": memory.get("Cached").copied(),
            "swap_total_bytes": memory.get("SwapTotal").copied(),
            "swap_free_bytes": memory.get("SwapFree").copied(),
        },
        "load_average": load,
        "uptime_seconds": uptime_seconds,
    })
}

fn storage_snapshot() -> Value {
    match filesystem_usage(Path::new("/")) {
        Ok((total, available)) => json!({
            "root": {
                "total_bytes": total,
                "available_bytes": available,
                "used_bytes": total.saturating_sub(available),
            }
        }),
        Err(error) => json!({
            "root": null,
            "error": error.to_string(),
        }),
    }
}

fn power_snapshot() -> Value {
    let supplies = sorted_entries(Path::new("/sys/class/power_supply"));
    let mut batteries = Vec::new();
    let mut external_power = Vec::new();
    for path in supplies {
        let supply_type = read_trimmed(path.join("type")).unwrap_or_default();
        let item = json!({
            "name": file_name(&path),
            "type": supply_type,
            "manufacturer": read_trimmed(path.join("manufacturer")),
            "model": read_trimmed(path.join("model_name")),
            "status": read_trimmed(path.join("status")),
            "present": read_u64(path.join("present")).map(|value| value != 0),
            "online": read_u64(path.join("online")).map(|value| value != 0),
            "capacity_percent": read_u64(path.join("capacity")),
            "energy_now_uwh": read_u64(path.join("energy_now")),
            "energy_full_uwh": read_u64(path.join("energy_full")),
            "energy_full_design_uwh": read_u64(path.join("energy_full_design")),
            "power_now_uw": read_u64(path.join("power_now")),
            "charge_now_uah": read_u64(path.join("charge_now")),
            "charge_full_uah": read_u64(path.join("charge_full")),
            "current_now_ua": read_u64(path.join("current_now")),
            "voltage_now_uv": read_u64(path.join("voltage_now")),
            "cycle_count": read_u64(path.join("cycle_count")),
        });
        if supply_type.eq_ignore_ascii_case("battery") {
            batteries.push(item);
        } else {
            external_power.push(item);
        }
    }

    let backlights = sorted_entries(Path::new("/sys/class/backlight"))
        .into_iter()
        .map(|path| {
            let brightness = read_u64(path.join("brightness"));
            let maximum = read_u64(path.join("max_brightness"));
            let percent = brightness.zip(maximum).and_then(|(current, maximum)| {
                (maximum > 0).then_some(current.saturating_mul(100) / maximum)
            });
            json!({
                "name": file_name(&path),
                "brightness": brightness,
                "maximum": maximum,
                "percent": percent,
                "actual_brightness": read_u64(path.join("actual_brightness")),
            })
        })
        .collect::<Vec<_>>();
    json!({
        "batteries": batteries,
        "external_power": external_power,
        "backlights": backlights,
    })
}

fn thermal_snapshot() -> Value {
    let zones = sorted_entries(Path::new("/sys/class/thermal"))
        .into_iter()
        .filter(|path| file_name(path).starts_with("thermal_zone"))
        .map(|path| {
            let milli_celsius = read_i64(path.join("temp"));
            json!({
                "name": file_name(&path),
                "type": read_trimmed(path.join("type")),
                "milli_celsius": milli_celsius,
                "celsius": milli_celsius.map(|value| value as f64 / 1000.0),
            })
        })
        .collect::<Vec<_>>();
    json!({ "zones": zones })
}

fn display_snapshot() -> Value {
    let connectors = sorted_entries(Path::new("/sys/class/drm"))
        .into_iter()
        .filter(|path| path.join("status").is_file())
        .map(|path| {
            let modes = fs::read_to_string(path.join("modes"))
                .ok()
                .map(|text| {
                    text.lines()
                        .map(str::trim)
                        .filter(|line| !line.is_empty())
                        .take(64)
                        .map(str::to_string)
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
            json!({
                "name": file_name(&path),
                "status": read_trimmed(path.join("status")),
                "enabled": read_trimmed(path.join("enabled")),
                "dpms": read_trimmed(path.join("dpms")),
                "modes": modes,
            })
        })
        .collect::<Vec<_>>();
    json!({ "connectors": connectors })
}

fn network_interfaces() -> Value {
    let interfaces = sorted_entries(Path::new("/sys/class/net"))
        .into_iter()
        .map(|path| {
            json!({
                "name": file_name(&path),
                "address": read_trimmed(path.join("address")),
                "operstate": read_trimmed(path.join("operstate")),
                "carrier": read_u64(path.join("carrier")).map(|value| value != 0),
                "mtu": read_u64(path.join("mtu")),
                "wireless": path.join("wireless").is_dir(),
                "statistics": {
                    "rx_bytes": read_u64(path.join("statistics/rx_bytes")),
                    "tx_bytes": read_u64(path.join("statistics/tx_bytes")),
                    "rx_packets": read_u64(path.join("statistics/rx_packets")),
                    "tx_packets": read_u64(path.join("statistics/tx_packets")),
                }
            })
        })
        .collect::<Vec<_>>();
    json!(interfaces)
}

fn security_snapshot() -> Value {
    let lockdown = read_trimmed("/sys/kernel/security/lockdown");
    let lsm = read_trimmed("/sys/kernel/security/lsm");
    let secure_boot_variable = sorted_entries(Path::new("/sys/firmware/efi/efivars"))
        .into_iter()
        .any(|path| file_name(&path).starts_with("SecureBoot-"));
    json!({
        "efi_booted": Path::new("/sys/firmware/efi").is_dir(),
        "secure_boot_variable_present": secure_boot_variable,
        "kernel_lockdown": lockdown,
        "linux_security_modules": lsm,
        "apparmor_enabled": read_u64("/sys/module/apparmor/parameters/enabled")
            .map(|value| value != 0)
            .or_else(|| read_trimmed("/sys/module/apparmor/parameters/enabled")
                .map(|value| value.eq_ignore_ascii_case("Y"))),
        "selinux_present": Path::new("/sys/fs/selinux").is_dir(),
    })
}

fn session_snapshot() -> Value {
    json!({
        "id": env::var("XDG_SESSION_ID").ok(),
        "type": env::var("XDG_SESSION_TYPE").ok(),
        "class": env::var("XDG_SESSION_CLASS").ok(),
        "desktop": env::var("XDG_CURRENT_DESKTOP").ok(),
        "wayland_display": env::var("WAYLAND_DISPLAY").ok(),
        "display": env::var("DISPLAY").ok(),
        "language": env::var("LANG").ok(),
    })
}

fn parse_key_value_file(path: &Path) -> BTreeMap<String, String> {
    let Ok(text) = fs::read_to_string(path) else {
        return BTreeMap::new();
    };
    parse_key_value(&text)
}

fn parse_key_value(text: &str) -> BTreeMap<String, String> {
    text.lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                return None;
            }
            let (key, value) = line.split_once('=')?;
            let key = key.trim();
            if key.is_empty()
                || !key
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
            {
                return None;
            }
            Some((key.to_string(), unquote(value.trim())))
        })
        .collect()
}

fn unquote(value: &str) -> String {
    let bytes = value.as_bytes();
    if bytes.len() < 2
        || !matches!(
            (bytes.first(), bytes.last()),
            (Some(b'\"'), Some(b'\"')) | (Some(b'\''), Some(b'\''))
        )
    {
        return value.to_string();
    }
    let quote = bytes[0];
    let inner = &value[1..value.len() - 1];
    if quote == b'\'' {
        return inner.to_string();
    }
    let mut result = String::with_capacity(inner.len());
    let mut escaped = false;
    for character in inner.chars() {
        if escaped {
            if matches!(character, '\\' | '"' | '$' | '`') {
                result.push(character);
            } else {
                result.push('\\');
                result.push(character);
            }
            escaped = false;
        } else if character == '\\' {
            escaped = true;
        } else {
            result.push(character);
        }
    }
    if escaped {
        result.push('\\');
    }
    result
}

fn parse_meminfo(text: &str) -> BTreeMap<String, u64> {
    text.lines()
        .filter_map(|line| {
            let (key, value) = line.split_once(':')?;
            let mut fields = value.split_whitespace();
            let amount = fields.next()?.parse::<u64>().ok()?;
            let multiplier = match fields.next() {
                Some(unit) if unit.eq_ignore_ascii_case("kb") => 1024,
                _ => 1,
            };
            Some((key.to_string(), amount.saturating_mul(multiplier)))
        })
        .collect()
}

fn filesystem_usage(path: &Path) -> io::Result<(u64, u64)> {
    let path = CString::new(path.as_os_str().as_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "path contains a NUL byte"))?;
    let mut stats = MaybeUninit::<libc::statvfs>::uninit();
    // SAFETY: `path` is a valid NUL-terminated C string and `stats` points to
    // writable memory large enough for one statvfs structure.
    let result = unsafe { libc::statvfs(path.as_ptr(), stats.as_mut_ptr()) };
    if result != 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: statvfs returned success and initialized the structure.
    let stats = unsafe { stats.assume_init() };
    let fragment_size = if stats.f_frsize > 0 {
        stats.f_frsize
    } else {
        stats.f_bsize
    };
    Ok((
        stats.f_blocks.saturating_mul(fragment_size),
        stats.f_bavail.saturating_mul(fragment_size),
    ))
}

fn command_exists(command: &str) -> bool {
    env::var_os("PATH").is_some_and(|path| {
        env::split_paths(&path).any(|directory| {
            let candidate = directory.join(command);
            candidate.is_file() && is_executable(&candidate)
        })
    })
}

fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path)
        .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

fn sorted_entries(path: &Path) -> Vec<PathBuf> {
    let mut entries = fs::read_dir(path)
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path())
        .collect::<Vec<_>>();
    entries.sort();
    entries
}

fn path_has_entries(path: &Path) -> bool {
    fs::read_dir(path)
        .ok()
        .and_then(|mut entries| entries.next())
        .is_some()
}

fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn read_trimmed(path: impl AsRef<Path>) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn read_u64(path: impl AsRef<Path>) -> Option<u64> {
    read_trimmed(path)?.parse().ok()
}

fn read_i64(path: impl AsRef<Path>) -> Option<i64> {
    read_trimmed(path)?.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn meminfo_values_are_converted_to_bytes() {
        let parsed = parse_meminfo(
            "MemTotal:       16384 kB\nMemAvailable:    4096 kB\nHugePages_Total: 2\n",
        );
        assert_eq!(parsed["MemTotal"], 16_777_216);
        assert_eq!(parsed["MemAvailable"], 4_194_304);
        assert_eq!(parsed["HugePages_Total"], 2);
    }

    #[test]
    fn os_release_parser_handles_quotes_and_escapes() {
        let parsed = parse_key_value(
            "NAME=Linux\nPRETTY_NAME=\"Example \\\"Linux\\\"\"\nSINGLE='literal value'\n# ignored\n",
        );
        assert_eq!(parsed["NAME"], "Linux");
        assert_eq!(parsed["PRETTY_NAME"], "Example \"Linux\"");
        assert_eq!(parsed["SINGLE"], "literal value");
    }

    #[test]
    fn malformed_keys_are_ignored() {
        let parsed = parse_key_value("GOOD=value\nbad-key=nope\n=value\n");
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed["GOOD"], "value");
    }

    #[test]
    fn root_filesystem_usage_is_sensible() {
        let (total, available) = filesystem_usage(Path::new("/")).unwrap();
        assert!(total > 0);
        assert!(available <= total);
    }
}
