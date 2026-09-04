use anyhow::{Context, Result};
use linmax_desktop_bridge::hyprland::atomic_write;
use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};
use zbus::blocking::{connection::Builder as ConnectionBuilder, Connection, Proxy};
use zbus::zvariant::{OwnedValue, Structure};

const SERVICE: &str = "org.kde.kdeconnect";
const ROOT_PATH: &str = "/modules/kdeconnect";
const DAEMON_IFACE: &str = "org.kde.kdeconnect.daemon";
const DEVICE_IFACE: &str = "org.kde.kdeconnect.device";
const NOTIFICATIONS_IFACE: &str = "org.kde.kdeconnect.device.notifications";
const NOTIFICATION_IFACE: &str = "org.kde.kdeconnect.device.notifications.notification";
const CONVERSATIONS_IFACE: &str = "org.kde.kdeconnect.device.conversations";
const BATTERY_IFACE: &str = "org.kde.kdeconnect.device.battery";
const PROPERTIES_IFACE: &str = "org.freedesktop.DBus.Properties";
const PUBLISH_INTERVAL: Duration = Duration::from_secs(15);
const CAPABILITIES_REFRESH_INTERVAL: Duration = Duration::from_secs(5 * 60);
const COMMANDS_REFRESH_INTERVAL: Duration = Duration::from_secs(5 * 60);
const MOUNT_REFRESH_INTERVAL: Duration = Duration::from_secs(60);
const SMS_REMOTE_REFRESH_INTERVAL: Duration = Duration::from_secs(2 * 60);

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct Capabilities {
    ping: bool,
    ring: bool,
    clipboard: bool,
    lock: bool,
    storage: bool,
    share: bool,
    sms: bool,
    mpris: bool,
    remote_commands: bool,
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct Notification {
    app_name: String,
    title: String,
    text: String,
    ticker: String,
    icon_path: String,
}

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct SmsConversation {
    contact: String,
    body: String,
    timestamp: i64,
    thread_id: i64,
    read: bool,
    sent: bool,
}

#[derive(Clone, Debug, Default, Serialize)]
struct RemoteCommand {
    id: String,
    name: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct DeviceSummary {
    id: String,
    name: String,
    available: bool,
    notification_count: usize,
    notifications: Vec<Notification>,
    battery: i32,
    charging: bool,
    remote_commands: Vec<RemoteCommand>,
    mount_point: String,
    sms_conversations: Vec<SmsConversation>,
    capabilities: Capabilities,
}

#[derive(Debug, Serialize)]
struct Payload {
    devices: Vec<DeviceSummary>,
    error: String,
}

#[derive(Debug, Default)]
struct DeviceCache {
    capabilities: Capabilities,
    capabilities_updated: Option<Instant>,
    remote_commands: Vec<RemoteCommand>,
    commands_updated: Option<Instant>,
    mount_point: String,
    mount_updated: Option<Instant>,
    sms_conversations: Vec<SmsConversation>,
    sms_refresh_requested: Option<Instant>,
    was_available: bool,
}

#[derive(Debug, Default)]
struct Bridge {
    connection: Option<Connection>,
    devices: HashMap<String, DeviceCache>,
}

fn runtime_state_path() -> PathBuf {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::geteuid() })));
    runtime.join("linmax-desktop-bridge/kdeconnect.json")
}

fn device_path(device_id: &str) -> String {
    format!("{ROOT_PATH}/devices/{device_id}")
}

fn proxy<'a>(connection: &'a Connection, path: &'a str, interface: &'a str) -> Result<Proxy<'a>> {
    Proxy::new(connection, SERVICE, path, interface).context("create KDE Connect D-Bus proxy")
}

fn capabilities(connection: &Connection, id: &str) -> Result<Capabilities> {
    let loaded = proxy(connection, &device_path(id), DEVICE_IFACE)?
        .call::<_, _, Vec<String>>("loadedPlugins", &())?
        .into_iter()
        .collect::<HashSet<_>>();

    let has = |plugin: &str| loaded.contains(plugin);
    Ok(Capabilities {
        ping: has("kdeconnect_ping"),
        ring: has("kdeconnect_findmyphone"),
        clipboard: has("kdeconnect_clipboard"),
        lock: has("kdeconnect_lockdevice"),
        storage: has("kdeconnect_sftp"),
        share: has("kdeconnect_share"),
        sms: has("kdeconnect_sms"),
        mpris: has("kdeconnect_mprisremote"),
        remote_commands: has("kdeconnect_runcommand"),
    })
}

fn all_properties(
    connection: &Connection,
    path: &str,
    interface: &str,
) -> Result<HashMap<String, OwnedValue>> {
    proxy(connection, path, PROPERTIES_IFACE)?
        .call("GetAll", &(interface,))
        .context("read D-Bus properties")
}

fn take_property<T>(properties: &mut HashMap<String, OwnedValue>, name: &str) -> Option<T>
where
    T: TryFrom<OwnedValue>,
{
    properties
        .remove(name)
        .and_then(|value| T::try_from(value).ok())
}

fn notifications(connection: &Connection, id: &str) -> Vec<Notification> {
    let root = format!("{}/notifications", device_path(id));
    let ids = proxy(connection, &root, NOTIFICATIONS_IFACE)
        .and_then(|p| {
            p.call::<_, _, Vec<String>>("activeNotifications", &())
                .map_err(Into::into)
        })
        .unwrap_or_default();

    ids.into_iter()
        .take(8)
        .filter_map(|notification_id| {
            let path = format!("{root}/{notification_id}");
            let mut properties = all_properties(connection, &path, NOTIFICATION_IFACE).ok()?;
            let item = Notification {
                app_name: take_property(&mut properties, "appName").unwrap_or_default(),
                title: take_property(&mut properties, "title").unwrap_or_default(),
                text: take_property(&mut properties, "text").unwrap_or_default(),
                ticker: take_property(&mut properties, "ticker").unwrap_or_default(),
                icon_path: take_property(&mut properties, "iconPath").unwrap_or_default(),
            };
            (!item.app_name.is_empty() || !item.ticker.is_empty()).then_some(item)
        })
        .collect()
}

fn value_at(fields: &[zbus::zvariant::Value<'_>], index: usize) -> Option<OwnedValue> {
    fields
        .get(index)
        .and_then(|value| OwnedValue::try_from(value).ok())
}

fn request_sms_refresh(connection: &Connection, id: &str) {
    let path = device_path(id);
    let Ok(proxy) = proxy(connection, &path, CONVERSATIONS_IFACE) else {
        return;
    };
    let _ = proxy.call_noreply("requestAllConversationThreads", &());
}

fn sms_conversations(connection: &Connection, id: &str) -> Result<Vec<SmsConversation>> {
    let path = device_path(id);
    let values = proxy(connection, &path, CONVERSATIONS_IFACE)?
        .call::<_, _, Vec<OwnedValue>>("activeConversations", &())?;

    let mut output = values
        .into_iter()
        .filter_map(|value| {
            let structure = Structure::try_from(value).ok()?;
            let fields = structure.fields();
            let message_type = i32::try_from(value_at(fields, 0)?).ok()?;
            let body = String::try_from(value_at(fields, 1)?).ok()?;
            let addresses = Vec::<(String,)>::try_from(value_at(fields, 2)?).unwrap_or_default();
            let timestamp = i64::try_from(value_at(fields, 3)?).unwrap_or_default();
            let read = i32::try_from(value_at(fields, 5)?).unwrap_or(1) != 0;
            let thread_id = i64::try_from(value_at(fields, 6)?).unwrap_or_default();
            Some(SmsConversation {
                contact: addresses
                    .first()
                    .map(|item| item.0.clone())
                    .unwrap_or_default(),
                body,
                timestamp,
                thread_id,
                read,
                sent: message_type == 2,
            })
        })
        .collect::<Vec<_>>();
    output.sort_by_key(|item| std::cmp::Reverse(item.timestamp));
    output.truncate(20);
    Ok(output)
}

fn command_output(program: &str, args: &[&str]) -> Option<String> {
    let Ok(mut child) = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return None;
    };

    // These optional CLI lookups may wait on the phone. Keep them tightly
    // bounded so a sleeping handset cannot stall the state publisher.
    let deadline = Instant::now() + Duration::from_millis(750);
    loop {
        match child.try_wait() {
            Ok(Some(status)) if status.success() => {
                return child
                    .wait_with_output()
                    .ok()
                    .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string());
            }
            Ok(Some(_)) | Err(_) => return None,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    }
}

fn remote_commands(id: &str) -> Option<Vec<RemoteCommand>> {
    Some(
        command_output("kdeconnect-cli", &["--device", id, "--list-commands"])?
            .lines()
            .filter_map(|line| {
                let text = line.trim();
                if text.is_empty() {
                    return None;
                }
                let (id, name) = text.split_once(':').unwrap_or((text, text));
                Some(RemoteCommand {
                    id: id.trim().to_string(),
                    name: name.trim().to_string(),
                })
            })
            .take(12)
            .collect(),
    )
}

fn battery(connection: &Connection, id: &str) -> (i32, bool) {
    let path = format!("{}/battery", device_path(id));
    let Ok(mut properties) = all_properties(connection, &path, BATTERY_IFACE) else {
        return (-1, false);
    };
    (
        take_property(&mut properties, "charge").unwrap_or(-1),
        take_property(&mut properties, "isCharging").unwrap_or(false),
    )
}

fn refresh_due(last: Option<Instant>, interval: Duration, force: bool) -> bool {
    force || last.is_none_or(|last| last.elapsed() >= interval)
}

fn collect_payload(
    connection: &Connection,
    device_cache: &mut HashMap<String, DeviceCache>,
) -> Result<Payload> {
    let daemon = proxy(connection, ROOT_PATH, DAEMON_IFACE)?;
    let paired: HashMap<String, String> = daemon.call("deviceNames", &(false, true))?;
    let reachable = daemon
        .call::<_, _, Vec<String>>("devices", &(true, true))?
        .into_iter()
        .collect::<HashSet<_>>();

    let mut paired = paired.into_iter().collect::<Vec<_>>();
    paired.sort_by(|a, b| a.1.to_lowercase().cmp(&b.1.to_lowercase()));
    let mut devices = Vec::with_capacity(paired.len());
    let paired_ids = paired
        .iter()
        .map(|(id, _)| id.clone())
        .collect::<HashSet<_>>();
    device_cache.retain(|id, _| paired_ids.contains(id));

    for (id, name) in paired {
        let available = reachable.contains(&id);
        let cached = device_cache.entry(id.clone()).or_default();
        let became_available = available && !cached.was_available;

        if refresh_due(
            cached.capabilities_updated,
            CAPABILITIES_REFRESH_INTERVAL,
            became_available,
        ) {
            if let Ok(next) = capabilities(connection, &id) {
                cached.capabilities = next;
                cached.capabilities_updated = Some(Instant::now());
            }
        }
        let capabilities = cached.capabilities.clone();
        let notifications = if available {
            notifications(connection, &id)
        } else {
            Vec::new()
        };
        let conversations = if available && capabilities.sms {
            if refresh_due(
                cached.sms_refresh_requested,
                SMS_REMOTE_REFRESH_INTERVAL,
                became_available,
            ) {
                request_sms_refresh(connection, &id);
                cached.sms_refresh_requested = Some(Instant::now());
            }
            if let Ok(next) = sms_conversations(connection, &id) {
                cached.sms_conversations = next;
            }
            cached.sms_conversations.clone()
        } else {
            Vec::new()
        };
        let commands = if available && capabilities.remote_commands {
            if refresh_due(
                cached.commands_updated,
                COMMANDS_REFRESH_INTERVAL,
                became_available,
            ) {
                cached.commands_updated = Some(Instant::now());
                if let Some(next) = remote_commands(&id) {
                    cached.remote_commands = next;
                }
            }
            cached.remote_commands.clone()
        } else {
            Vec::new()
        };
        let mount_point = if available && capabilities.storage {
            if refresh_due(
                cached.mount_updated,
                MOUNT_REFRESH_INTERVAL,
                became_available,
            ) {
                cached.mount_updated = Some(Instant::now());
                if let Some(next) =
                    command_output("kdeconnect-cli", &["--device", &id, "--get-mount-point"])
                {
                    cached.mount_point = next;
                }
            }
            cached.mount_point.clone()
        } else {
            String::new()
        };
        let (battery, charging) = if available {
            battery(connection, &id)
        } else {
            (-1, false)
        };
        devices.push(DeviceSummary {
            id,
            name,
            available,
            notification_count: notifications.len(),
            notifications,
            battery,
            charging,
            remote_commands: commands,
            mount_point,
            sms_conversations: conversations,
            capabilities,
        });
        cached.was_available = available;
    }

    Ok(Payload {
        devices,
        error: String::new(),
    })
}

impl Bridge {
    fn connect(&mut self) -> Result<()> {
        if self.connection.is_none() {
            self.connection = Some(
                ConnectionBuilder::session()
                    .map(|builder| builder.method_timeout(Duration::from_secs(2)))
                    .and_then(ConnectionBuilder::build)
                    .context("connect to session D-Bus")?,
            );
        }
        Ok(())
    }

    fn payload_json(&mut self) -> String {
        let payload = self.connect().and_then(|()| {
            let connection = self
                .connection
                .as_ref()
                .context("session D-Bus unavailable")?;
            collect_payload(connection, &mut self.devices)
        });
        let payload = payload.unwrap_or_else(|error| {
            // A disconnected session bus connection cannot recover. Rebuild it
            // on the next publish cycle instead of reconnecting every 15 seconds
            // during healthy operation.
            self.connection = None;
            self.devices.clear();
            Payload {
                devices: Vec::new(),
                error: format!("{error:#}"),
            }
        });
        serde_json::to_string(&payload).unwrap_or_else(|error| {
            format!(r#"{{"devices":[],"error":"serialize KDE Connect state: {error}"}}"#)
        })
    }
}

fn write_if_changed(path: &Path, previous: &mut String, next: String) -> Result<()> {
    if *previous == next {
        return Ok(());
    }
    atomic_write(path, format!("{next}\n").as_bytes())?;
    *previous = next;
    Ok(())
}

fn main() -> Result<()> {
    let mut bridge = Bridge::default();
    let once = env::args().any(|arg| arg == "--once");
    if once {
        println!("{}", bridge.payload_json());
        return Ok(());
    }

    let path = runtime_state_path();
    let mut previous = String::new();
    loop {
        if let Err(error) = write_if_changed(&path, &mut previous, bridge.payload_json()) {
            eprintln!("[kdeconnect-bridge] {error:#}");
        }
        thread::sleep(PUBLISH_INTERVAL);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refreshes_empty_and_forced_cache_entries() {
        assert!(refresh_due(None, Duration::from_secs(60), false));
        assert!(refresh_due(
            Some(Instant::now()),
            Duration::from_secs(60),
            true
        ));
    }

    #[test]
    fn keeps_recent_cache_entries() {
        assert!(!refresh_due(
            Some(Instant::now()),
            Duration::from_secs(60),
            false
        ));
    }
}
