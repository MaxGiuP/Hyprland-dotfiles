use anyhow::{anyhow, Context, Result};
use serde_json::Value;
use std::env;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Clone, Debug)]
pub struct HyprlandIpc {
    runtime_dir: PathBuf,
}

impl Default for HyprlandIpc {
    fn default() -> Self {
        Self::new()
    }
}

impl HyprlandIpc {
    pub fn new() -> Self {
        let runtime_dir = env::var_os("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(format!("/run/user/{}", unsafe { libc::geteuid() })));
        Self { runtime_dir }
    }

    fn hypr_dir(&self) -> PathBuf {
        self.runtime_dir.join("hypr")
    }

    pub fn socket_path(&self, socket_name: &str) -> Result<PathBuf> {
        if let Some(signature) = env::var_os("HYPRLAND_INSTANCE_SIGNATURE") {
            let candidate = self.hypr_dir().join(signature).join(socket_name);
            if candidate.exists() {
                return Ok(candidate);
            }
        }

        let mut candidates = fs::read_dir(self.hypr_dir())
            .context("read Hyprland runtime directory")?
            .filter_map(Result::ok)
            .map(|entry| entry.path().join(socket_name))
            .filter(|path| path.exists())
            .filter_map(|path| {
                let modified = fs::metadata(&path).ok()?.modified().ok()?;
                Some((modified, path))
            })
            .collect::<Vec<_>>();
        candidates.sort_by(|a, b| b.0.cmp(&a.0));
        candidates
            .into_iter()
            .next()
            .map(|(_, path)| path)
            .ok_or_else(|| anyhow!("Hyprland socket {socket_name} not found"))
    }

    pub fn command(&self, command: &str) -> Result<String> {
        let path = self.socket_path(".socket.sock")?;
        let mut socket =
            UnixStream::connect(&path).with_context(|| format!("connect to {}", path.display()))?;
        socket.set_read_timeout(Some(Duration::from_millis(1500)))?;
        socket.set_write_timeout(Some(Duration::from_millis(1500)))?;
        socket.write_all(command.as_bytes())?;
        socket.shutdown(std::net::Shutdown::Write)?;

        let mut output = String::new();
        socket.read_to_string(&mut output)?;
        Ok(output)
    }

    pub fn json(&self, query: &str) -> Result<Value> {
        let output = self.command(&format!("j/{query}"))?;
        serde_json::from_str(&output)
            .with_context(|| format!("parse Hyprland JSON response for {query}"))
    }

    pub fn dispatch(&self, dispatcher: &str, args: &str) -> Result<()> {
        let command = if args.is_empty() {
            format!("dispatch {dispatcher}")
        } else {
            format!("dispatch {dispatcher} {args}")
        };
        self.command(&command).map(|_| ())
    }

    pub fn keyword(&self, name: &str, value: &str) -> Result<()> {
        self.command(&format!("keyword {name} {value}")).map(|_| ())
    }

    pub fn event_stream(&self) -> Result<UnixStream> {
        let path = self.socket_path(".socket2.sock")?;
        UnixStream::connect(&path).with_context(|| format!("connect to {}", path.display()))
    }
}

pub fn atomic_write(path: &Path, contents: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("create {}", parent.display()))?;
    }

    let temp = path.with_extension(format!("tmp.{}", std::process::id()));
    fs::write(&temp, contents).with_context(|| format!("write {}", temp.display()))?;
    fs::rename(&temp, path).with_context(|| format!("replace {}", path.display()))?;
    Ok(())
}
