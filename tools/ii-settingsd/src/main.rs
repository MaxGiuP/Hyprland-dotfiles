mod native_bus;
mod protocol;
mod server;
mod system;

use std::env;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Duration;

use protocol::{Request, Response};

fn default_socket_path() -> Result<PathBuf, String> {
    let runtime = env::var_os("XDG_RUNTIME_DIR")
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            "XDG_RUNTIME_DIR is not set; pass --socket with an absolute path".to_string()
        })?;
    Ok(PathBuf::from(runtime)
        .join("ii-settingsd")
        .join("daemon.sock"))
}

fn take_socket_option(arguments: &mut Vec<String>) -> Result<PathBuf, String> {
    let mut socket = None;
    let mut index = 0;
    while index < arguments.len() {
        if arguments[index] != "--socket" {
            index += 1;
            continue;
        }
        if socket.is_some() {
            return Err("--socket may only be specified once".to_string());
        }
        if index + 1 >= arguments.len() {
            return Err("--socket requires a path".to_string());
        }
        socket = Some(PathBuf::from(arguments.remove(index + 1)));
        arguments.remove(index);
    }
    let socket = match socket {
        Some(path) => path,
        None => default_socket_path()?,
    };
    if !socket.is_absolute() {
        return Err("the socket path must be absolute".to_string());
    }
    Ok(socket)
}

fn usage(mut output: impl Write) -> io::Result<()> {
    writeln!(output, "ii-settingsd 0.1.0")?;
    writeln!(output, "native settings service for Illogical Impulse")?;
    writeln!(output)?;
    writeln!(output, "USAGE:")?;
    writeln!(output, "  ii-settingsd serve [--socket PATH]")?;
    writeln!(
        output,
        "  ii-settingsd call [--socket PATH] METHOD [PARAMS_JSON]"
    )?;
    writeln!(output)?;
    writeln!(
        output,
        "With no subcommand, `serve` is used. The default socket is"
    )?;
    writeln!(output, "$XDG_RUNTIME_DIR/ii-settingsd/daemon.sock.")
}

fn call(socket: &Path, arguments: Vec<String>) -> Result<(), String> {
    if arguments.is_empty() || arguments.len() > 2 {
        return Err("call expects METHOD and, optionally, one JSON params object".to_string());
    }
    let method = arguments[0].clone();
    let params = match arguments.get(1) {
        Some(raw) => {
            serde_json::from_str(raw).map_err(|error| format!("invalid params JSON: {error}"))?
        }
        None => serde_json::json!({}),
    };
    let request = Request {
        id: serde_json::json!(1),
        method,
        params,
    };
    let response: Response = server::call(socket, &request, Duration::from_secs(15))
        .map_err(|error| format!("request failed: {error}"))?;
    if response.ok {
        println!(
            "{}",
            serde_json::to_string_pretty(&response.result.unwrap_or(serde_json::Value::Null))
                .map_err(|error| error.to_string())?
        );
        Ok(())
    } else {
        let error = response.error.unwrap_or_else(|| {
            protocol::ApiError::new(
                "invalid_response",
                "daemon returned an unsuccessful response without an error",
            )
        });
        Err(format!("{}: {}", error.code, error.message))
    }
}

fn run() -> Result<(), String> {
    let mut arguments: Vec<String> = env::args().skip(1).collect();
    if arguments
        .iter()
        .any(|argument| argument == "-h" || argument == "--help")
    {
        usage(io::stdout()).map_err(|error| error.to_string())?;
        return Ok(());
    }

    let command = if arguments
        .first()
        .is_some_and(|value| value == "serve" || value == "call")
    {
        arguments.remove(0)
    } else {
        "serve".to_string()
    };
    let socket = take_socket_option(&mut arguments)?;

    match command.as_str() {
        "serve" => {
            if !arguments.is_empty() {
                return Err(format!("unexpected argument: {}", arguments[0]));
            }
            server::serve(socket).map_err(|error| error.to_string())
        }
        "call" => call(&socket, arguments),
        _ => unreachable!(),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("ii-settingsd: {error}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn socket_option_can_appear_before_method() {
        let mut arguments = vec![
            "--socket".to_string(),
            "/tmp/ii-settingsd-test.sock".to_string(),
            "snapshot".to_string(),
        ];
        let socket = take_socket_option(&mut arguments).unwrap();
        assert_eq!(socket, PathBuf::from("/tmp/ii-settingsd-test.sock"));
        assert_eq!(arguments, ["snapshot"]);
    }

    #[test]
    fn relative_socket_is_rejected() {
        let mut arguments = vec!["--socket".to_string(), "daemon.sock".to_string()];
        assert!(take_socket_option(&mut arguments).is_err());
    }
}
