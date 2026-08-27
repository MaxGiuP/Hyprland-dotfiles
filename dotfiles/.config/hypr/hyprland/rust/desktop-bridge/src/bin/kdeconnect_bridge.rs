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

#[derive(Debug, Default, Serialize)]
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

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct SmsConversation {
    contact: String,
    body: String,
    timestamp: i64,
    thread_id: i64,
    read: bool,
    sent: bool,
}

#[derive(Debug, Default, Serialize)]
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

fn capabilities(connection: &Connection, id: &str) -> Capabilities {
    let loaded = proxy(connection, &device_path(id), DEVICE_IFACE)
        .and_then(|p| {
            p.call::<_, _, Vec<String>>("loadedPlugins", &())
                .map_err(Into::into)
        })
        .unwrap_or_default()
        .into_iter()
        .collect::<HashSet<_>>();

    let has = |plugin: &str| loaded.contains(plugin);
    Capabilities {
        ping: has("kdeconnect_ping"),
        ring: has("kdeconnect_findmyphone"),
        clipboard: has("kdeconnect_clipboard"),
        lock: has("kdeconnect_lockdevice"),
        storage: has("kdeconnect_sftp"),
        share: has("kdeconnect_share"),
        sms: has("kdeconnect_sms"),
        mpris: has("kdeconnect_mprisremote"),
        remote_commands: has("kdeconnect_runcommand"),
    }
}
fn string_property(connection: &Connection, path: &str, interface: &str, name: &str) -> String {
    proxy(connection, path, interface)
        .and_then(|p| p.get_property::<String>(name).map_err(Into::into))
        .unwrap_or_default()
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
            let item = Notification {
                app_name: string_property(connection, &path, NOTIFICATION_IFACE, "appName"),
                title: string_property(connection, &path, NOTIFICATION_IFACE, "title"),
                text: string_property(connection, &path, NOTIFICATION_IFACE, "text"),
                ticker: string_property(connection, &path, NOTIFICATION_IFACE, "ticker"),
                icon_path: string_property(connection, &path, NOTIFICATION_IFACE, "iconPath"),
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

fn sms_conversations(connection: &Connection, id: &str) -> Vec<SmsConversation> {
    let path = device_path(id);
    let Ok(proxy) = proxy(connection, &path, CONVERSATIONS_IFACE) else {
        return Vec::new();
    };

    let _ = proxy.call_noreply("requestAllConversationThreads", &());
    let values = proxy
        .call::<_, _, Vec<OwnedValue>>("activeConversations", &())
        .unwrap_or_default();

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
    output
}

fn command_output(program: &str, args: &[&str]) -> String {
    let Ok(mut child) = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return String::new();
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
                    .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
                    .unwrap_or_default();
            }
            Ok(Some(_)) | Err(_) => return String::new(),
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return String::new();
            }
        }
    }
}

fn remote_commands(id: &str, enabled: bool, available: bool) -> Vec<RemoteCommand> {
    if !enabled || !available {
        return Vec::new();
    }
    command_output("kdeconnect-cli", &["--device", id, "--list-commands"])
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
        .collect()
}

fn battery(connection: &Connection, id: &str) -> (i32, bool) {
    let path = format!("{}/battery", device_path(id));
    let Ok(proxy) = proxy(connection, &path, BATTERY_IFACE) else {
        return (-1, false);
    };
    (
        proxy.get_property::<i32>("charge").unwrap_or(-1),
        proxy.get_property::<bool>("isCharging").unwrap_or(false),
    )
}

fn collect_payload(connection: &Connection) -> Result<Payload> {
    let daemon = proxy(connection, ROOT_PATH, DAEMON_IFACE)?;
    let paired: HashMap<String, String> = daemon.call("deviceNames", &(false, true))?;
    let reachable = daemon
        .call::<_, _, Vec<String>>("devices", &(true, true))?
        .into_iter()
        .collect::<HashSet<_>>();

    let mut paired = paired.into_iter().collect::<Vec<_>>();
    paired.sort_by(|a, b| a.1.to_lowercase().cmp(&b.1.to_lowercase()));
    let mut devices = Vec::with_capacity(paired.len());

    for (id, name) in paired {
        let available = reachable.contains(&id);
        let capabilities = capabilities(connection, &id);
        let notifications = if available {
            notifications(connection, &id)
        } else {
            Vec::new()
        };
        let conversations = if available && capabilities.sms {
            sms_conversations(connection, &id)
        } else {
            Vec::new()
        };
        let commands = remote_commands(&id, capabilities.remote_commands, available);
        let mount_point = if available && capabilities.storage {
            command_output("kdeconnect-cli", &["--device", &id, "--get-mount-point"])
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
    }

    Ok(Payload {
        devices,
        error: String::new(),
    })
}

fn payload_json() -> String {
    let payload = ConnectionBuilder::session()
        .map(|builder| builder.method_timeout(Duration::from_secs(2)))
        .and_then(ConnectionBuilder::build)
        .context("connect to session D-Bus")
        .and_then(|connection| collect_payload(&connection))
        .unwrap_or_else(|error| Payload {
            devices: Vec::new(),
            error: format!("{error:#}"),
        });
    serde_json::to_string(&payload).unwrap_or_else(|error| {
        format!(r#"{{"devices":[],"error":"serialize KDE Connect state: {error}"}}"#)
    })
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
    let once = env::args().any(|arg| arg == "--once");
    if once {
        println!("{}", payload_json());
        return Ok(());
    }

    let path = runtime_state_path();
    let mut previous = String::new();
    loop {
        if let Err(error) = write_if_changed(&path, &mut previous, payload_json()) {
            eprintln!("[kdeconnect-bridge] {error:#}");
        }
        thread::sleep(Duration::from_secs(15));
    }
}
