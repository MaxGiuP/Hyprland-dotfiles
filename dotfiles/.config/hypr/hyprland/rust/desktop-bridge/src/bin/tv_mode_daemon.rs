use anyhow::Result;
use evdev::{AbsoluteAxisCode, Device, EventSummary, KeyCode};
use linmax_desktop_bridge::hyprland::{atomic_write, HyprlandIpc};
use regex::Regex;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, ErrorKind};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const TV_MONITOR_CANDIDATES: &[&str] = &["HDMI-A-2", "HDMI-2", "HDMI2"];
const TV_WORKSPACE: &str = "special:tv";
const APP_WORKSPACE: &str = "special:tv-app";
const ACTIVE_STATUSES: &[&str] = &["starting", "active", "loading"];
const STEAM_CLASSES: &[&str] = &["steam", "Steam", "steamwebhelper"];
const BIG_PICTURE_TITLES: &[&str] = &["Steam Big Picture Mode", "Modalità Big Picture di Steam"];
const STEAM_GAME_MARKERS: &[&str] = &[
    "SteamLaunch AppId=",
    "/steamapps/common/",
    "/steamapps/compatdata/",
    "lanoire-stable-launch",
];
const DIRECT_CONTROLLER_CLASSES: &[&str] = &["gamescope", "rpcs3"];

const KEY_ESC: u16 = 1;
const KEY_TAB: u16 = 15;
const KEY_ENTER: u16 = 28;
const KEY_LEFTCTRL: u16 = 29;
const KEY_LEFTSHIFT: u16 = 42;
const KEY_SPACE: u16 = 57;
const KEY_LEFTALT: u16 = 56;
const KEY_PAGEUP: u16 = 104;
const KEY_LEFT: u16 = 105;
const KEY_RIGHT: u16 = 106;
const KEY_DOWN: u16 = 108;
const KEY_PAGEDOWN: u16 = 109;
const KEY_UP: u16 = 103;

fn state_path() -> PathBuf {
    let state_home = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    state_home.join("tv-mode/state.json")
}

fn now_epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs())
        .unwrap_or_default()
}

fn text(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn integer(value: &Value, key: &str) -> i64 {
    value.get(key).and_then(Value::as_i64).unwrap_or_default()
}

fn normalize_address(address: &str) -> String {
    let address = address.trim();
    if address.starts_with("0x") {
        address.to_string()
    } else {
        format!("0x{address}")
    }
}

fn address_selector(address: &str) -> String {
    format!("address:{}", normalize_address(address))
}

fn workspace_name(client: &Value) -> String {
    client
        .get("workspace")
        .and_then(|workspace| workspace.get("name"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn is_live(client: &Value) -> bool {
    client
        .get("mapped")
        .and_then(Value::as_bool)
        .unwrap_or(true)
        && !client
            .get("hidden")
            .and_then(Value::as_bool)
            .unwrap_or(false)
}

fn window_class(client: &Value) -> String {
    let class = text(client, "class");
    if class.is_empty() {
        text(client, "initialClass")
    } else {
        class
    }
}

fn window_title(client: &Value) -> String {
    let title = text(client, "title");
    if title.is_empty() {
        text(client, "initialTitle")
    } else {
        title
    }
}

fn is_steam_ui(class: &str, title: &str) -> bool {
    STEAM_CLASSES.contains(&class)
        && (title == "Steam"
            || BIG_PICTURE_TITLES.contains(&title)
            || title.contains("Big Picture")
            || title.contains("Modalità Big Picture"))
}

fn proc_cmdline(pid: i64) -> String {
    fs::read(format!("/proc/{pid}/cmdline"))
        .map(|bytes| {
            String::from_utf8_lossy(&bytes)
                .replace('\0', " ")
                .trim()
                .to_string()
        })
        .unwrap_or_default()
}

fn parent_pid(pid: i64) -> i64 {
    fs::read_to_string(format!("/proc/{pid}/status"))
        .ok()
        .and_then(|status| {
            status.lines().find_map(|line| {
                line.strip_prefix("PPid:")
                    .and_then(|value| value.trim().parse().ok())
            })
        })
        .unwrap_or_default()
}

fn process_tree_has_steam_launch(pid: i64) -> bool {
    let mut current = pid;
    let mut seen = HashSet::new();
    for _ in 0..32 {
        if current <= 1 || !seen.insert(current) {
            return false;
        }
        let command = proc_cmdline(current);
        if STEAM_GAME_MARKERS
            .iter()
            .any(|marker| command.contains(marker))
        {
            return true;
        }
        current = parent_pid(current);
    }
    false
}

struct Router {
    ipc: HyprlandIpc,
    app_windows: HashSet<String>,
    big_picture_windows: HashSet<String>,
    tv_app_regex: Regex,
    fallback_workspace: String,
    state_path: PathBuf,
}

impl Router {
    fn new() -> Self {
        Self {
            ipc: HyprlandIpc::new(),
            app_windows: HashSet::new(),
            big_picture_windows: HashSet::new(),
            tv_app_regex: Regex::new(r"(?i)^(steam_app_.*|chrome-.*-TV)$").unwrap(),
            fallback_workspace: env::var("TV_MODE_FALLBACK_WORKSPACE")
                .unwrap_or_else(|_| "1".into()),
            state_path: state_path(),
        }
    }

    fn clients(&self) -> Vec<Value> {
        self.ipc
            .json("clients")
            .ok()
            .and_then(|value| value.as_array().cloned())
            .unwrap_or_default()
    }

    fn monitors(&self) -> Vec<Value> {
        self.ipc
            .json("monitors")
            .ok()
            .and_then(|value| value.as_array().cloned())
            .unwrap_or_default()
    }

    fn resolve_tv_monitor(&self) -> Option<String> {
        let available = self
            .monitors()
            .into_iter()
            .map(|monitor| text(&monitor, "name"))
            .collect::<HashSet<_>>();
        TV_MONITOR_CANDIDATES
            .iter()
            .find(|candidate| available.contains(**candidate))
            .map(|value| (*value).to_string())
    }

    fn clear_state(&self) {
        let state = json!({
            "status": "stopped", "message": "", "mode": "", "app": "", "monitor": "", "updated_at": now_epoch()
        });
        let _ = atomic_write(&self.state_path, format!("{state}\n").as_bytes());
    }

    fn enabled(&mut self) -> bool {
        let status = fs::read_to_string(&self.state_path)
            .ok()
            .and_then(|contents| serde_json::from_str::<Value>(&contents).ok())
            .map(|value| text(&value, "status"))
            .unwrap_or_default();
        if !ACTIVE_STATUSES.contains(&status.as_str()) {
            return false;
        }
        if self.resolve_tv_monitor().is_none() {
            self.stop_without_monitor();
            return false;
        }
        true
    }

    fn dispatch(&self, name: &str, args: &str) {
        let _ = self.ipc.dispatch(name, args);
    }

    fn keyword(&self, name: &str, value: &str) {
        let _ = self.ipc.keyword(name, value);
    }

    fn is_tv_app(&self, class: &str) -> bool {
        self.tv_app_regex.is_match(class)
    }

    fn is_tv_app_client(&self, client: &Value) -> bool {
        let class = window_class(client);
        let title = window_title(client);
        if is_steam_ui(&class, &title) {
            return false;
        }
        self.is_tv_app(&class) || process_tree_has_steam_launch(integer(client, "pid"))
    }

    fn refresh_tracked(&mut self, clients: &[Value]) {
        self.app_windows.clear();
        self.big_picture_windows.clear();
        for client in clients.iter().filter(|client| is_live(client)) {
            let address = normalize_address(&text(client, "address"));
            if address == "0x" {
                continue;
            }
            if self.is_tv_app_client(client) {
                self.app_windows.insert(address);
            } else if is_steam_ui(&window_class(client), &window_title(client)) {
                self.big_picture_windows.insert(address);
            }
        }
    }

    fn live_tv_apps(&self, clients: &[Value]) -> Vec<String> {
        clients
            .iter()
            .filter(|client| is_live(client) && self.is_tv_app_client(client))
            .map(|client| normalize_address(&text(client, "address")))
            .filter(|address| address != "0x")
            .collect()
    }

    fn live_steam_ui(&self, clients: &[Value]) -> Vec<String> {
        clients
            .iter()
            .filter(|client| {
                is_live(client) && is_steam_ui(&window_class(client), &window_title(client))
            })
            .map(|client| normalize_address(&text(client, "address")))
            .filter(|address| address != "0x")
            .collect()
    }

    fn find_client(&self, address: &str) -> Option<Value> {
        let address = normalize_address(address);
        self.clients()
            .into_iter()
            .find(|client| normalize_address(&text(client, "address")) == address)
    }

    fn fallback_workspace(&self) -> String {
        for monitor in self.monitors() {
            if TV_MONITOR_CANDIDATES.contains(&text(&monitor, "name").as_str()) {
                continue;
            }
            let name = monitor
                .get("activeWorkspace")
                .and_then(|workspace| workspace.get("name"))
                .and_then(Value::as_str)
                .unwrap_or_default();
            if !name.is_empty() && !name.starts_with("special:") {
                return name.to_string();
            }
        }
        self.fallback_workspace.clone()
    }

    fn visible_monitor_for_special(&self, workspace: &str) -> Option<String> {
        self.monitors().into_iter().find_map(|monitor| {
            let special = monitor
                .get("specialWorkspace")
                .and_then(|value| value.get("name"))
                .and_then(Value::as_str)
                .unwrap_or_default();
            (special == workspace).then(|| text(&monitor, "name"))
        })
    }

    fn special_visible_on_monitor(&self, monitor_name: &str) -> Option<String> {
        self.monitors().into_iter().find_map(|monitor| {
            if text(&monitor, "name") != monitor_name {
                return None;
            }
            monitor
                .get("specialWorkspace")
                .and_then(|value| value.get("name"))
                .and_then(Value::as_str)
                .map(ToString::to_string)
        })
    }

    fn hide_workspace_everywhere(&self, workspace: &str) {
        for _ in 0..6 {
            let Some(monitor) = self.visible_monitor_for_special(workspace) else {
                return;
            };
            self.dispatch("focusmonitor", &monitor);
            self.dispatch(
                "togglespecialworkspace",
                workspace.trim_start_matches("special:"),
            );
            thread::sleep(Duration::from_millis(50));
        }
    }

    fn stop_without_monitor(&mut self) {
        for client in self.clients() {
            if is_live(&client)
                && [TV_WORKSPACE, APP_WORKSPACE].contains(&workspace_name(&client).as_str())
            {
                let address = normalize_address(&text(&client, "address"));
                if address != "0x" {
                    self.dispatch("closewindow", &address_selector(&address));
                }
            }
        }
        for _ in 0..20 {
            let any = self.clients().iter().any(|client| {
                is_live(client)
                    && [TV_WORKSPACE, APP_WORKSPACE].contains(&workspace_name(client).as_str())
            });
            if !any {
                break;
            }
            thread::sleep(Duration::from_millis(100));
        }
        self.clear_state();
        self.hide_workspace_everywhere(TV_WORKSPACE);
        self.hide_workspace_everywhere(APP_WORKSPACE);
    }

    fn follow_mouse(&self) -> i32 {
        self.ipc
            .command("getoption input:follow_mouse")
            .ok()
            .and_then(|output| {
                output.lines().find_map(|line| {
                    line.strip_prefix("int:")
                        .and_then(|value| value.trim().parse().ok())
                })
            })
            .unwrap_or(1)
    }

    fn toggle_workspace_on_monitor(&self, workspace: &str, monitor: &str) {
        let follow_mouse = self.follow_mouse();
        self.keyword("input:follow_mouse", "0");
        self.dispatch("moveworkspacetomonitor", &format!("{workspace} {monitor}"));
        self.dispatch("focusmonitor", monitor);
        self.dispatch(
            "togglespecialworkspace",
            workspace.trim_start_matches("special:"),
        );
        self.dispatch("moveworkspacetomonitor", &format!("{workspace} {monitor}"));
        self.keyword("input:follow_mouse", &follow_mouse.to_string());
    }

    fn ensure_workspace_rules(&mut self) -> bool {
        let Some(monitor) = self.resolve_tv_monitor() else {
            self.stop_without_monitor();
            return false;
        };
        let opts = format!("persistent:true, monitor:{monitor}, gapsin:0, gapsout:0, border:false, rounding:false, decorate:false");
        self.keyword("workspace", &format!("{TV_WORKSPACE}, {opts}"));
        self.keyword("workspace", &format!("{APP_WORKSPACE}, {opts}"));
        self.dispatch(
            "moveworkspacetomonitor",
            &format!("{TV_WORKSPACE} {monitor}"),
        );
        self.dispatch(
            "moveworkspacetomonitor",
            &format!("{APP_WORKSPACE} {monitor}"),
        );
        true
    }

    fn show_workspace(&mut self, workspace: &str) {
        if !self.ensure_workspace_rules() {
            return;
        }
        let Some(monitor) = self.resolve_tv_monitor() else {
            return;
        };
        self.dispatch("moveworkspacetomonitor", &format!("{workspace} {monitor}"));
        if self.visible_monitor_for_special(workspace).as_deref() == Some(&monitor) {
            return;
        }
        if let Some(visible) = self.special_visible_on_monitor(&monitor) {
            if !visible.is_empty() && visible != workspace {
                self.toggle_workspace_on_monitor(&visible, &monitor);
                thread::sleep(Duration::from_millis(50));
            }
        }
        if self
            .visible_monitor_for_special(workspace)
            .as_deref()
            .is_some_and(|name| name != monitor)
        {
            self.hide_workspace_everywhere(workspace);
        }
        if self.visible_monitor_for_special(workspace).as_deref() != Some(&monitor) {
            self.toggle_workspace_on_monitor(workspace, &monitor);
        }
    }

    fn place_big_picture(&mut self, address: &str, show: bool) {
        let Some(monitor) = self.resolve_tv_monitor() else {
            self.stop_without_monitor();
            return;
        };
        let address = normalize_address(address);
        self.big_picture_windows.insert(address.clone());
        self.dispatch(
            "movetoworkspacesilent",
            &format!("{TV_WORKSPACE},{}", address_selector(&address)),
        );
        self.dispatch(
            "moveworkspacetomonitor",
            &format!("{TV_WORKSPACE} {monitor}"),
        );
        if show {
            self.show_workspace(TV_WORKSPACE);
        }
    }

    fn place_tv_app(&mut self, address: &str, show: bool) {
        let Some(monitor) = self.resolve_tv_monitor() else {
            self.stop_without_monitor();
            return;
        };
        let address = normalize_address(address);
        self.app_windows.insert(address.clone());
        self.dispatch(
            "movetoworkspacesilent",
            &format!("{APP_WORKSPACE},{}", address_selector(&address)),
        );
        self.dispatch(
            "moveworkspacetomonitor",
            &format!("{APP_WORKSPACE} {monitor}"),
        );
        if show {
            self.show_workspace(APP_WORKSPACE);
        }
    }

    fn route_client(&mut self, client: &Value, show: bool) {
        let address = normalize_address(&text(client, "address"));
        if address == "0x" {
            return;
        }
        if self.is_tv_app_client(client) {
            self.place_tv_app(&address, show);
        } else if is_steam_ui(&window_class(client), &window_title(client)) {
            let scanned = self.clients();
            self.refresh_tracked(&scanned);
            let should_show = show && self.live_tv_apps(&scanned).is_empty();
            self.place_big_picture(&address, should_show);
        } else if [TV_WORKSPACE, APP_WORKSPACE].contains(&workspace_name(client).as_str()) {
            self.dispatch(
                "movetoworkspacesilent",
                &format!(
                    "{},{}",
                    self.fallback_workspace(),
                    address_selector(&address)
                ),
            );
        }
    }

    fn route_address(&mut self, address: &str, show: bool, delay: Duration) {
        thread::sleep(delay);
        if let Some(client) = self.find_client(address) {
            self.route_client(&client, show);
        }
    }

    fn rescan(&mut self, show: bool) {
        if show && !self.enabled() {
            return;
        }
        let clients = self.clients();
        self.refresh_tracked(&clients);
        let apps = self.live_tv_apps(&clients);
        let steam = self.live_steam_ui(&clients);
        if show {
            for address in &steam {
                self.place_big_picture(address, false);
            }
            if let Some(last) = apps.last() {
                for address in &apps {
                    self.place_tv_app(address, false);
                }
                self.show_workspace(APP_WORKSPACE);
                let _ = last;
            } else if let Some(last) = steam.last() {
                self.place_big_picture(last, true);
            }
        }
    }

    fn return_to_big_picture_if_empty(&mut self) {
        if !self.enabled() {
            return;
        }
        thread::sleep(Duration::from_millis(50));
        let clients = self.clients();
        self.refresh_tracked(&clients);
        if !self.live_tv_apps(&clients).is_empty() {
            return;
        }
        self.show_workspace(TV_WORKSPACE);
    }

    fn handle_event(&mut self, line: &str) {
        if !self.enabled() {
            return;
        }
        if let Some(payload) = line.strip_prefix("openwindow>>") {
            let mut fields = payload.splitn(4, ',');
            let Some(address) = fields.next() else { return };
            let _workspace = fields.next();
            let class = fields.next().unwrap_or_default();
            let title = fields.next().unwrap_or_default();
            thread::sleep(Duration::from_millis(120));
            if self.is_tv_app(class) {
                self.place_tv_app(address, true);
            } else if is_steam_ui(class, title) {
                let clients = self.clients();
                self.refresh_tracked(&clients);
                self.place_big_picture(address, self.live_tv_apps(&clients).is_empty());
            } else {
                self.route_address(address, true, Duration::ZERO);
            }
        } else if let Some(address) = line.strip_prefix("closewindow>>") {
            let address = normalize_address(address);
            let was_big_picture = self.big_picture_windows.remove(&address);
            self.app_windows.remove(&address);
            let clients = self.clients();
            self.refresh_tracked(&clients);
            if was_big_picture && self.big_picture_windows.is_empty() {
                self.clear_state();
            } else {
                self.return_to_big_picture_if_empty();
            }
        } else if let Some(address) = line.strip_prefix("windowtitle>>") {
            self.route_address(address, false, Duration::from_millis(100));
        } else if let Some(payload) = line.strip_prefix("movewindow>>") {
            self.route_address(
                payload.split(',').next().unwrap_or_default(),
                false,
                Duration::from_millis(100),
            );
        } else if let Some(address) = line.strip_prefix("activewindowv2>>") {
            self.route_address(address, false, Duration::from_millis(50));
        }
    }

    fn event_loop(&mut self) -> ! {
        let _ = self.ensure_workspace_rules();
        self.rescan(false);
        loop {
            match self.ipc.event_stream() {
                Ok(stream) => {
                    for line in BufReader::new(stream).lines() {
                        match line {
                            Ok(line) => self.handle_event(&line),
                            Err(_) => break,
                        }
                    }
                }
                Err(error) => eprintln!("[tv-mode] Hyprland event socket: {error:#}"),
            }
            thread::sleep(Duration::from_secs(1));
        }
    }
}

fn tv_app_client(ipc: &HyprlandIpc) -> Option<Value> {
    let mut candidates = ipc
        .json("clients")
        .ok()?
        .as_array()?
        .iter()
        .filter(|client| is_live(client) && workspace_name(client) == APP_WORKSPACE)
        .cloned()
        .collect::<Vec<_>>();
    candidates.sort_by_key(|client| integer(client, "focusHistoryID"));
    candidates.into_iter().next()
}

fn should_inject_controller_key(ipc: &HyprlandIpc) -> bool {
    let Some(client) = tv_app_client(ipc) else {
        return false;
    };
    let class = window_class(&client).to_lowercase();
    !DIRECT_CONTROLLER_CLASSES.contains(&class.as_str())
        && !process_tree_has_steam_launch(integer(&client, "pid"))
}

fn spawn_quiet(program: &str, args: &[String]) {
    let _ = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

fn ydotool_key(ipc: &HyprlandIpc, keycodes: &[u16], combo: bool) {
    if keycodes.is_empty() || !should_inject_controller_key(ipc) {
        return;
    }
    let mut args = vec!["key".to_string()];
    if combo {
        args.extend(keycodes.iter().map(|key| format!("{key}:1")));
        args.extend(keycodes.iter().rev().map(|key| format!("{key}:0")));
    } else {
        for key in keycodes {
            args.extend([format!("{key}:1"), format!("{key}:0")]);
        }
    }
    spawn_quiet("ydotool", &args);
}

fn notify(summary: &str, body: &str) {
    spawn_quiet("notify-send", &[summary.to_string(), body.to_string()]);
}

fn move_cursor_to_tv(ipc: &HyprlandIpc) {
    let monitor = ipc
        .json("monitors")
        .ok()
        .and_then(|value| value.as_array().cloned())
        .and_then(|monitors| {
            monitors
                .into_iter()
                .find(|monitor| TV_MONITOR_CANDIDATES.contains(&text(monitor, "name").as_str()))
        });
    let Some(monitor) = monitor else { return };
    let x = integer(&monitor, "x") + integer(&monitor, "width") / 2;
    let y = integer(&monitor, "y") + integer(&monitor, "height") / 2;
    let _ = ipc.dispatch("movecursor", &format!("{x} {y}"));
}

fn fire_script(prefix: &str, script: &Path) {
    let args = vec![
        "--user".into(),
        "--collect".into(),
        "--quiet".into(),
        "--property=StandardOutput=journal".into(),
        "--property=StandardError=journal".into(),
        format!("--unit={prefix}"),
        script.display().to_string(),
    ];
    spawn_quiet("systemd-run", &args);
}

fn scripts_dir() -> PathBuf {
    env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(Path::to_path_buf))
        .and_then(|_| env::var_os("HOME").map(PathBuf::from))
        .unwrap_or_default()
        .join(".config/hypr/hyprland/scripts/tv_mode")
}

fn normalize_axis(absinfo: &HashMap<u16, (i32, i32)>, axis: u16, value: i32) -> f64 {
    let Some((minimum, maximum)) = absinfo.get(&axis) else {
        return 0.0;
    };
    let center = f64::from(minimum + maximum) / 2.0;
    let span = (f64::from(maximum - minimum) / 2.0).max(1.0);
    ((f64::from(value) - center) / span).clamp(-1.0, 1.0)
}

fn axis_key(axis: u16, value: f64, held: Duration, scroll: bool) -> Option<u16> {
    if value.abs() < 0.35 {
        return None;
    }
    let positive = value > 0.0;
    let vertical = axis == AbsoluteAxisCode::ABS_Y.0 || axis == AbsoluteAxisCode::ABS_RY.0;
    if scroll && vertical && held > Duration::from_millis(1200) {
        return Some(if positive { KEY_PAGEDOWN } else { KEY_PAGEUP });
    }
    Some(if vertical {
        if positive {
            KEY_DOWN
        } else {
            KEY_UP
        }
    } else if positive {
        KEY_RIGHT
    } else {
        KEY_LEFT
    })
}

fn watch_controller(mut device: Device, path: PathBuf) {
    let ipc = HyprlandIpc::new();
    let _ = device.set_nonblocking(true);
    let absinfo = device
        .get_absinfo()
        .map(|entries| {
            entries
                .map(|(axis, info)| (axis.0, (info.minimum(), info.maximum())))
                .collect()
        })
        .unwrap_or_default();
    let mut pressed = HashSet::<u16>::new();
    let mut triggers = HashMap::from([
        (AbsoluteAxisCode::ABS_Z.0, false),
        (AbsoluteAxisCode::ABS_RZ.0, false),
    ]);
    let mut focus_axes = HashMap::from([
        (AbsoluteAxisCode::ABS_X.0, 0.0),
        (AbsoluteAxisCode::ABS_Y.0, 0.0),
    ]);
    let mut scroll_axes = HashMap::from([
        (AbsoluteAxisCode::ABS_RX.0, 0.0),
        (AbsoluteAxisCode::ABS_RY.0, 0.0),
    ]);
    let mut scroll_started = HashMap::<u16, Instant>::new();
    let mut active_command = false;
    let mut close_active = false;
    let mut last_repeat = Instant::now();
    let mut cooldowns = HashMap::<&'static str, Instant>::new();
    eprintln!(
        "[tv-controller] watching {} ({})",
        path.display(),
        device.name().unwrap_or("unknown")
    );

    loop {
        match device.fetch_events() {
            Ok(events) => {
                for event in events {
                    match event.destructure() {
                        EventSummary::Key(_, key, value) => {
                            let code = key.code();
                            if value == 1 {
                                pressed.insert(code);
                            } else if value == 0 {
                                pressed.remove(&code);
                            }
                            let close_now = [
                                KeyCode::BTN_SELECT.code(),
                                KeyCode::BTN_THUMBL.code(),
                                KeyCode::BTN_THUMBR.code(),
                            ]
                            .iter()
                            .all(|key| pressed.contains(key));
                            let button = match code {
                                value if value == KeyCode::BTN_SOUTH.code() => Some(KEY_ENTER),
                                value if value == KeyCode::BTN_EAST.code() => Some(KEY_ESC),
                                value if value == KeyCode::BTN_NORTH.code() => Some(KEY_SPACE),
                                value if value == KeyCode::BTN_WEST.code() => Some(KEY_TAB),
                                _ => None,
                            };
                            if let Some(button) =
                                button.filter(|_| !(code == KeyCode::BTN_EAST.code() && close_now))
                            {
                                if value == 1 || value == 2 {
                                    ydotool_key(&ipc, &[button], false);
                                }
                            }
                            let dpad = match code {
                                value if value == KeyCode::BTN_DPAD_UP.code() => Some(KEY_UP),
                                value if value == KeyCode::BTN_DPAD_DOWN.code() => Some(KEY_DOWN),
                                value if value == KeyCode::BTN_DPAD_LEFT.code() => Some(KEY_LEFT),
                                value if value == KeyCode::BTN_DPAD_RIGHT.code() => Some(KEY_RIGHT),
                                _ => None,
                            };
                            if let Some(key) = dpad {
                                if value == 1 || value == 2 {
                                    ydotool_key(&ipc, &[KEY_LEFTCTRL, KEY_LEFTALT, key], true);
                                }
                            }
                        }
                        EventSummary::AbsoluteAxis(_, axis, value) => {
                            let code = axis.0;
                            if triggers.contains_key(&code) {
                                triggers.insert(code, value >= 100);
                            }
                            if focus_axes.contains_key(&code) {
                                focus_axes.insert(code, normalize_axis(&absinfo, code, value));
                            }
                            if scroll_axes.contains_key(&code) {
                                scroll_axes.insert(code, normalize_axis(&absinfo, code, value));
                            }
                            if code == AbsoluteAxisCode::ABS_HAT0X.0 && value != 0 {
                                ydotool_key(
                                    &ipc,
                                    &[
                                        KEY_LEFTCTRL,
                                        KEY_LEFTALT,
                                        if value > 0 { KEY_RIGHT } else { KEY_LEFT },
                                    ],
                                    true,
                                );
                            } else if code == AbsoluteAxisCode::ABS_HAT0Y.0 && value != 0 {
                                ydotool_key(
                                    &ipc,
                                    &[
                                        KEY_LEFTCTRL,
                                        KEY_LEFTALT,
                                        if value > 0 { KEY_DOWN } else { KEY_UP },
                                    ],
                                    true,
                                );
                            }
                        }
                        _ => {}
                    }

                    let digital = [KeyCode::BTN_SELECT.code(), KeyCode::BTN_START.code()]
                        .iter()
                        .all(|key| pressed.contains(key));
                    if digital && !active_command {
                        let now = Instant::now();
                        let bumpers = [KeyCode::BTN_TL.code(), KeyCode::BTN_TR.code()]
                            .iter()
                            .all(|key| pressed.contains(key));
                        let triggers_active = triggers.values().all(|value| *value);
                        let (name, script, summary, body) = if bumpers {
                            (
                                "focus",
                                "focus_tv_target.sh",
                                "TV mode command registered",
                                "Back + Start + LB + RB: focusing the current TV target.",
                            )
                        } else if triggers_active {
                            (
                                "clean",
                                "clean_stale_steam.sh",
                                "TV mode command registered",
                                "Back + Start + LT + RT: cleaning stale Steam TV state.",
                            )
                        } else {
                            ("", "", "", "")
                        };
                        if !name.is_empty()
                            && cooldowns.get(name).is_none_or(|last| {
                                now.duration_since(*last) >= Duration::from_millis(1750)
                            })
                        {
                            cooldowns.insert(name, now);
                            move_cursor_to_tv(&ipc);
                            notify(summary, body);
                            fire_script(
                                if name == "focus" {
                                    "tv-focus-target"
                                } else {
                                    "tv-steam-clean-stale"
                                },
                                &scripts_dir().join(script),
                            );
                            active_command = true;
                        }
                    } else if !digital {
                        active_command = false;
                    }

                    let close_now = [
                        KeyCode::BTN_SELECT.code(),
                        KeyCode::BTN_THUMBL.code(),
                        KeyCode::BTN_THUMBR.code(),
                    ]
                    .iter()
                    .all(|key| pressed.contains(key));
                    if close_now && !close_active {
                        fire_script("tv-close-app", &scripts_dir().join("close_tv_app.sh"));
                    }
                    close_active = close_now;
                }
            }
            Err(error) if error.kind() == ErrorKind::WouldBlock => {}
            Err(_) => break,
        }

        if last_repeat.elapsed() >= Duration::from_millis(120) {
            if let Some((&axis, &value)) = focus_axes
                .iter()
                .max_by(|a, b| a.1.abs().total_cmp(&b.1.abs()))
            {
                if let Some(key) = axis_key(axis, value, Duration::ZERO, false) {
                    ydotool_key(&ipc, &[KEY_LEFTCTRL, KEY_LEFTALT, key], true);
                }
            }
            for (&axis, &value) in &scroll_axes {
                if value.abs() < 0.35 {
                    scroll_started.remove(&axis);
                    continue;
                }
                let started = *scroll_started.entry(axis).or_insert_with(Instant::now);
                if let Some(key) = axis_key(axis, value, started.elapsed(), true) {
                    ydotool_key(&ipc, &[KEY_LEFTCTRL, KEY_LEFTALT, KEY_LEFTSHIFT, key], true);
                }
            }
            last_repeat = Instant::now();
        }
        thread::sleep(Duration::from_millis(10));
    }
    eprintln!(
        "[tv-controller] controller disconnected: {}",
        path.display()
    );
}

fn controller_supervisor() -> ! {
    let name = Regex::new("(?i)x-?box").unwrap();
    let mut active = HashSet::<PathBuf>::new();
    loop {
        active.retain(|path| path.exists());
        for (path, device) in evdev::enumerate() {
            if active.contains(&path) || !name.is_match(device.name().unwrap_or_default()) {
                continue;
            }
            let keys = device.supported_keys();
            let axes = device.supported_absolute_axes();
            let matching = keys.is_some_and(|keys| {
                keys.contains(KeyCode::BTN_SELECT) && keys.contains(KeyCode::BTN_START)
            }) && axes.is_some_and(|axes| {
                axes.contains(AbsoluteAxisCode::ABS_Z) && axes.contains(AbsoluteAxisCode::ABS_RZ)
            });
            if matching {
                active.insert(path.clone());
                thread::spawn(move || watch_controller(device, path));
            }
        }
        thread::sleep(Duration::from_secs(2));
    }
}

fn main() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let mut router = Router::new();
    match args.first().map(String::as_str) {
        Some("--rescan-once") => {
            router.ensure_workspace_rules();
            router.rescan(true);
            return Ok(());
        }
        Some("--rescan-for") => {
            let seconds = args
                .get(1)
                .and_then(|value| value.parse::<f64>().ok())
                .unwrap_or(10.0);
            router.ensure_workspace_rules();
            router.rescan(true);
            let deadline = Instant::now() + Duration::from_secs_f64(seconds.max(0.0));
            while Instant::now() < deadline {
                router.rescan(false);
                thread::sleep(Duration::from_millis(350));
            }
            return Ok(());
        }
        Some("--check") => {
            let controller_name = Regex::new("(?i)x-?box").unwrap();
            println!(
                "{}",
                json!({
                    "hyprland": router.ipc.json("version").is_ok(),
                    "tvMonitor": router.resolve_tv_monitor(),
                    "controllers": evdev::enumerate().filter(|(_, device)| controller_name.is_match(device.name().unwrap_or_default())).count()
                })
            );
            return Ok(());
        }
        _ => {}
    }

    thread::spawn(controller_supervisor);
    router.event_loop()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_hyprland_addresses() {
        assert_eq!(normalize_address("abc"), "0xabc");
        assert_eq!(normalize_address("0xabc"), "0xabc");
    }

    #[test]
    fn classifies_steam_ui_titles() {
        assert!(is_steam_ui("steam", "Steam Big Picture Mode"));
        assert!(!is_steam_ui("steam_app_123", "A game"));
    }
}
