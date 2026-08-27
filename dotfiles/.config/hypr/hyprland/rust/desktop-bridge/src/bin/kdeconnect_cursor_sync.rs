use anyhow::{Context, Result};
use linmax_desktop_bridge::hyprland::HyprlandIpc;
use regex::Regex;
use serde::Deserialize;
use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use x11rb::connection::Connection;
use x11rb::protocol::xproto::ConnectionExt;

#[derive(Clone, Debug)]
struct XMonitor {
    name: String,
    width: i32,
    height: i32,
    x: i32,
    y: i32,
}

#[derive(Clone, Debug, Deserialize)]
struct HyprMonitor {
    name: String,
    x: i32,
    y: i32,
}

#[derive(Debug)]
struct ScrollEngine {
    carry_x: f64,
    carry_y: f64,
    velocity_x: f64,
    velocity_y: f64,
    last_input: Instant,
    divisor: f64,
    inertia: f64,
    min_velocity: f64,
}

impl ScrollEngine {
    fn new(divisor: f64, inertia: f64, min_velocity: f64) -> Self {
        Self {
            carry_x: 0.0,
            carry_y: 0.0,
            velocity_x: 0.0,
            velocity_y: 0.0,
            last_input: Instant::now() - Duration::from_secs(60),
            divisor,
            inertia,
            min_velocity,
        }
    }

    fn reset(&mut self) {
        self.carry_x = 0.0;
        self.carry_y = 0.0;
        self.velocity_x = 0.0;
        self.velocity_y = 0.0;
        self.last_input = Instant::now() - Duration::from_secs(60);
    }

    fn input(&mut self, dx: f64, dy: f64, log_path: &PathBuf) {
        self.last_input = Instant::now();
        self.velocity_x = dx * 0.55;
        self.velocity_y = dy * 0.55;
        self.emit(dx, dy, "scroll", log_path);
    }

    fn tick(&mut self, log_path: &PathBuf) {
        if self.last_input.elapsed() < Duration::from_millis(80) {
            return;
        }
        if self.velocity_x.abs() < self.min_velocity && self.velocity_y.abs() < self.min_velocity {
            self.velocity_x = 0.0;
            self.velocity_y = 0.0;
            return;
        }
        let (vx, vy) = (self.velocity_x, self.velocity_y);
        self.velocity_x *= self.inertia;
        self.velocity_y *= self.inertia;
        self.emit(vx, vy, "inertia", log_path);
    }

    fn emit(&mut self, raw_dx: f64, raw_dy: f64, source: &str, log_path: &PathBuf) {
        self.carry_x += raw_dx / self.divisor;
        self.carry_y += raw_dy / self.divisor;
        let sx = (self.carry_x as i32).clamp(-2, 2);
        let sy = (self.carry_y as i32).clamp(-2, 2);
        self.carry_x -= f64::from(sx);
        self.carry_y -= f64::from(sy);
        if sx == 0 && sy == 0 {
            return;
        }

        log(
            log_path,
            &format!("{source} dx={raw_dx:.2} dy={raw_dy:.2} sx={sx} sy={sy}"),
        );
        let _ = Command::new("ydotool")
            .args([
                "mousemove",
                "--wheel",
                "-x",
                &sx.to_string(),
                "-y",
                &sy.to_string(),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
}
fn env_f64(name: &str, default: f64) -> f64 {
    env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}

fn cache_home() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".cache"))
}

fn log(path: &PathBuf, message: &str) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs())
        .unwrap_or_default();
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{timestamp} {message}");
    }
}

fn x_monitors() -> Vec<XMonitor> {
    let output = Command::new("xrandr")
        .arg("--query")
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).into_owned())
        .unwrap_or_default();
    let regex = Regex::new(r"^(\S+)\s+connected\b.*?(\d+)x(\d+)\+(-?\d+)\+(-?\d+)").unwrap();
    output
        .lines()
        .filter_map(|line| {
            let captures = regex.captures(line)?;
            Some(XMonitor {
                name: captures[1].to_string(),
                width: captures[2].parse().ok()?,
                height: captures[3].parse().ok()?,
                x: captures[4].parse().ok()?,
                y: captures[5].parse().ok()?,
            })
        })
        .collect()
}

fn hypr_monitors(ipc: &HyprlandIpc) -> Vec<HyprMonitor> {
    ipc.json("monitors")
        .ok()
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default()
}

fn map_pointer(
    x: i32,
    y: i32,
    x_monitors: &[XMonitor],
    hypr_monitors: &[HyprMonitor],
) -> Option<(i32, i32)> {
    let monitor = x_monitors.iter().find(|monitor| {
        x >= monitor.x
            && x < monitor.x + monitor.width
            && y >= monitor.y
            && y < monitor.y + monitor.height
    })?;
    let hypr = hypr_monitors
        .iter()
        .find(|candidate| candidate.name == monitor.name)?;
    Some((hypr.x + x - monitor.x, hypr.y + y - monitor.y))
}

fn main() -> Result<()> {
    let interval =
        Duration::from_secs_f64(env_f64("KDECONNECT_CURSOR_SYNC_INTERVAL", 0.025).max(0.005));
    let scroll_mode_file = cache_home().join("kdeconnect-phone-scroll-mode");
    let log_path = cache_home().join("kdeconnect-cursor-sync.log");
    let mut scroll = ScrollEngine::new(
        env_f64("KDECONNECT_PHONE_SCROLL_DIVISOR", 46.0).max(1.0),
        env_f64("KDECONNECT_PHONE_SCROLL_INERTIA", 0.88).clamp(0.0, 0.999),
        env_f64("KDECONNECT_PHONE_SCROLL_MIN_VELOCITY", 0.35).max(0.0),
    );

    let (connection, screen_number) =
        x11rb::connect(None).context("connect to Xwayland display")?;
    let root = connection.setup().roots[screen_number].root;
    let ipc = HyprlandIpc::new();
    let mut x_layout = x_monitors();
    let mut hypr_layout = hypr_monitors(&ipc);
    let mut layouts_updated = Instant::now();
    let mut last_pointer: Option<(i32, i32)> = None;
    let mut last_scroll_mode: Option<bool> = None;

    if env::args().any(|arg| arg == "--once") {
        let pointer = connection.query_pointer(root)?.reply()?;
        let mapped = map_pointer(
            i32::from(pointer.root_x),
            i32::from(pointer.root_y),
            &x_layout,
            &hypr_layout,
        );
        println!(
            "{}",
            serde_json::json!({"x": pointer.root_x, "y": pointer.root_y, "mapped": mapped})
        );
        return Ok(());
    }

    loop {
        let started = Instant::now();
        if layouts_updated.elapsed() >= Duration::from_secs(5) {
            x_layout = x_monitors();
            hypr_layout = hypr_monitors(&ipc);
            layouts_updated = Instant::now();
        }

        let scroll_mode = scroll_mode_file.exists();
        if last_scroll_mode != Some(scroll_mode) {
            log(
                &log_path,
                &format!("kde-scroll-mode={}", if scroll_mode { "on" } else { "off" }),
            );
            scroll.reset();
            last_scroll_mode = Some(scroll_mode);
        }

        if let Ok(cookie) = connection.query_pointer(root) {
            if let Ok(pointer) = cookie.reply() {
                let current = (i32::from(pointer.root_x), i32::from(pointer.root_y));
                if let Some(previous) = last_pointer {
                    if current != previous {
                        let dx = current.0 - previous.0;
                        let dy = current.1 - previous.1;
                        if scroll_mode {
                            scroll.input(f64::from(dx), f64::from(dy), &log_path);
                        } else if let Some(mapped) =
                            map_pointer(current.0, current.1, &x_layout, &hypr_layout)
                        {
                            let _ =
                                ipc.dispatch("movecursor", &format!("{} {}", mapped.0, mapped.1));
                        }
                    }
                }
                last_pointer = Some(current);
            }
        }

        if scroll_mode {
            scroll.tick(&log_path);
        }

        thread::sleep(interval.saturating_sub(started.elapsed()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_xwayland_monitor_offsets_to_hyprland() {
        let x = vec![XMonitor {
            name: "HDMI-A-1".into(),
            width: 1920,
            height: 1080,
            x: 0,
            y: 0,
        }];
        let hypr = vec![HyprMonitor {
            name: "HDMI-A-1".into(),
            x: 0,
            y: 550,
        }];
        assert_eq!(map_pointer(960, 540, &x, &hypr), Some((960, 1090)));
    }
}
