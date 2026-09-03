use std::env;
use std::fs;
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use crate::protocol::{ApiError, MAX_REQUEST_BYTES, Request, Response, State};

const MAX_CLIENTS: usize = 32;

pub fn serve(socket_path: PathBuf) -> io::Result<()> {
    prepare_parent(&socket_path)?;
    remove_stale_socket(&socket_path)?;
    let listener = UnixListener::bind(&socket_path)?;
    fs::set_permissions(&socket_path, fs::Permissions::from_mode(0o600))?;
    let _socket_guard = SocketGuard::new(socket_path.clone())?;
    let state = Arc::new(State::new());
    let active_clients = Arc::new(AtomicUsize::new(0));
    eprintln!("ii-settingsd: listening on {}", socket_path.display());

    for connection in listener.incoming() {
        let stream = match connection {
            Ok(stream) => stream,
            Err(error) => {
                eprintln!("ii-settingsd: accept failed: {error}");
                continue;
            }
        };
        if let Err(error) = require_same_user(&stream) {
            eprintln!("ii-settingsd: rejected peer: {error}");
            continue;
        }
        if active_clients.fetch_add(1, Ordering::AcqRel) >= MAX_CLIENTS {
            active_clients.fetch_sub(1, Ordering::AcqRel);
            let _ = write_one_response(
                stream,
                &Response::failure(
                    serde_json::Value::Null,
                    ApiError::new("server_busy", "too many connected clients"),
                ),
            );
            continue;
        }

        let state = Arc::clone(&state);
        let client_counter = Arc::clone(&active_clients);
        if let Err(error) = std::thread::Builder::new()
            .name("ii-settings-client".to_string())
            .spawn(move || {
                let _guard = ClientGuard(client_counter);
                if let Err(error) = handle_client(stream, &state) {
                    eprintln!("ii-settingsd: client error: {error}");
                }
            })
        {
            active_clients.fetch_sub(1, Ordering::AcqRel);
            eprintln!("ii-settingsd: could not start client worker: {error}");
        }
    }
    Ok(())
}

pub fn call(socket_path: &Path, request: &Request, timeout: Duration) -> io::Result<Response> {
    let stream = UnixStream::connect(socket_path)?;
    stream.set_read_timeout(Some(timeout))?;
    stream.set_write_timeout(Some(timeout))?;
    let reader_stream = stream.try_clone()?;
    let mut writer = BufWriter::new(stream);
    serde_json::to_writer(&mut writer, request).map_err(io::Error::other)?;
    writer.write_all(b"\n")?;
    writer.flush()?;

    let mut reader = BufReader::new(reader_stream);
    match read_limited_line(&mut reader, MAX_REQUEST_BYTES)? {
        Line::Data(bytes) => serde_json::from_slice(&bytes).map_err(io::Error::other),
        Line::Eof => Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "daemon closed the socket without a response",
        )),
        Line::TooLong => Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "daemon response exceeded the protocol limit",
        )),
    }
}

fn handle_client(stream: UnixStream, state: &State) -> io::Result<()> {
    stream.set_write_timeout(Some(Duration::from_secs(10)))?;
    let reader_stream = stream.try_clone()?;
    let mut reader = BufReader::new(reader_stream);
    let mut writer = BufWriter::new(stream);
    loop {
        let line = match read_limited_line(&mut reader, MAX_REQUEST_BYTES)? {
            Line::Eof => return Ok(()),
            Line::TooLong => {
                write_response(
                    &mut writer,
                    &Response::failure(
                        serde_json::Value::Null,
                        ApiError::new(
                            "request_too_large",
                            format!("requests are limited to {MAX_REQUEST_BYTES} bytes"),
                        ),
                    ),
                )?;
                return Ok(());
            }
            Line::Data(line) => line,
        };
        if line.iter().all(u8::is_ascii_whitespace) {
            continue;
        }
        let request: Request = match serde_json::from_slice(&line) {
            Ok(request) => request,
            Err(error) => {
                write_response(
                    &mut writer,
                    &Response::failure(
                        serde_json::Value::Null,
                        ApiError::new("invalid_json", error.to_string()),
                    ),
                )?;
                continue;
            }
        };
        if request.method.is_empty() || request.method.len() > 128 {
            write_response(
                &mut writer,
                &Response::failure(
                    request.id,
                    ApiError::new(
                        "invalid_request",
                        "method must contain between 1 and 128 bytes",
                    ),
                ),
            )?;
            continue;
        }
        write_response(&mut writer, &state.dispatch(request))?;
    }
}

fn write_one_response(stream: UnixStream, response: &Response) -> io::Result<()> {
    let mut writer = BufWriter::new(stream);
    write_response(&mut writer, response)
}

fn write_response(writer: &mut impl Write, response: &Response) -> io::Result<()> {
    serde_json::to_writer(&mut *writer, response).map_err(io::Error::other)?;
    writer.write_all(b"\n")?;
    writer.flush()
}

enum Line {
    Eof,
    Data(Vec<u8>),
    TooLong,
}

fn read_limited_line(reader: &mut impl BufRead, limit: usize) -> io::Result<Line> {
    let mut output = Vec::new();
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return if output.is_empty() {
                Ok(Line::Eof)
            } else {
                Ok(Line::Data(output))
            };
        }
        let newline = available.iter().position(|byte| *byte == b'\n');
        let consumed = newline.map_or(available.len(), |index| index + 1);
        if output.len().saturating_add(consumed) > limit {
            reader.consume(consumed);
            return Ok(Line::TooLong);
        }
        output.extend_from_slice(&available[..consumed]);
        reader.consume(consumed);
        if newline.is_some() {
            if output.last() == Some(&b'\n') {
                output.pop();
            }
            if output.last() == Some(&b'\r') {
                output.pop();
            }
            return Ok(Line::Data(output));
        }
    }
}

fn prepare_parent(socket_path: &Path) -> io::Result<()> {
    let parent = socket_path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "socket path has no parent"))?;
    if parent.exists() {
        let metadata = fs::symlink_metadata(parent)?;
        if !metadata.file_type().is_dir() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "socket parent is not a real directory",
            ));
        }
        if metadata.uid() != effective_uid() {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "socket parent belongs to another user",
            ));
        }
        if is_default_runtime_directory(parent) {
            fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;
        }
        return Ok(());
    }
    fs::create_dir_all(parent)?;
    fs::set_permissions(parent, fs::Permissions::from_mode(0o700))
}

fn is_default_runtime_directory(path: &Path) -> bool {
    env::var_os("XDG_RUNTIME_DIR")
        .is_some_and(|runtime| path == Path::new(&runtime).join("ii-settingsd"))
}

fn remove_stale_socket(socket_path: &Path) -> io::Result<()> {
    let metadata = match fs::symlink_metadata(socket_path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    if !metadata.file_type().is_socket() || metadata.uid() != effective_uid() {
        return Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "refusing to replace a non-socket, symlink, or socket owned by another user",
        ));
    }
    match UnixStream::connect(socket_path) {
        Ok(_) => Err(io::Error::new(
            io::ErrorKind::AddrInUse,
            "another ii-settingsd instance is already listening",
        )),
        Err(error)
            if matches!(
                error.kind(),
                io::ErrorKind::ConnectionRefused | io::ErrorKind::NotFound
            ) =>
        {
            fs::remove_file(socket_path)
        }
        Err(error) => Err(error),
    }
}

fn require_same_user(stream: &UnixStream) -> io::Result<()> {
    let mut credentials = MaybeCredentials::new();
    let mut length = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    // SAFETY: the socket descriptor is valid for the lifetime of `stream`, and
    // `credentials` and `length` point to writable objects of the right size.
    let result = unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            credentials.as_mut_ptr(),
            &mut length,
        )
    };
    if result != 0 {
        return Err(io::Error::last_os_error());
    }
    if length as usize != std::mem::size_of::<libc::ucred>() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "kernel returned malformed peer credentials",
        ));
    }
    // SAFETY: getsockopt succeeded and returned exactly one initialized ucred.
    let credentials = unsafe { credentials.assume_init() };
    if credentials.uid != effective_uid() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "peer belongs to a different user",
        ));
    }
    Ok(())
}

struct MaybeCredentials(std::mem::MaybeUninit<libc::ucred>);

impl MaybeCredentials {
    fn new() -> Self {
        Self(std::mem::MaybeUninit::uninit())
    }

    fn as_mut_ptr(&mut self) -> *mut libc::c_void {
        self.0.as_mut_ptr().cast()
    }

    unsafe fn assume_init(self) -> libc::ucred {
        // SAFETY: upheld by the caller after a successful getsockopt call.
        unsafe { self.0.assume_init() }
    }
}

fn effective_uid() -> u32 {
    // SAFETY: geteuid has no preconditions and cannot fail.
    unsafe { libc::geteuid() }
}

struct ClientGuard(Arc<AtomicUsize>);

impl Drop for ClientGuard {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::AcqRel);
    }
}

struct SocketGuard {
    path: PathBuf,
    device: u64,
    inode: u64,
}

impl SocketGuard {
    fn new(path: PathBuf) -> io::Result<Self> {
        let metadata = fs::symlink_metadata(&path)?;
        Ok(Self {
            path,
            device: metadata.dev(),
            inode: metadata.ino(),
        })
    }
}

impl Drop for SocketGuard {
    fn drop(&mut self) {
        if let Ok(metadata) = fs::symlink_metadata(&self.path) {
            if metadata.file_type().is_socket()
                && metadata.uid() == effective_uid()
                && metadata.dev() == self.device
                && metadata.ino() == self.inode
            {
                let _ = fs::remove_file(&self.path);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn reads_lf_and_crlf_lines() {
        let mut reader = Cursor::new(b"first\r\nsecond\n".to_vec());
        assert!(matches!(
            read_limited_line(&mut reader, 20).unwrap(),
            Line::Data(value) if value == b"first"
        ));
        assert!(matches!(
            read_limited_line(&mut reader, 20).unwrap(),
            Line::Data(value) if value == b"second"
        ));
        assert!(matches!(
            read_limited_line(&mut reader, 20).unwrap(),
            Line::Eof
        ));
    }

    #[test]
    fn rejects_oversized_lines_without_allocating_the_whole_input() {
        let input = vec![b'a'; 1024];
        let mut reader = BufReader::with_capacity(16, Cursor::new(input));
        assert!(matches!(
            read_limited_line(&mut reader, 100).unwrap(),
            Line::TooLong
        ));
    }

    #[test]
    fn accepts_an_unterminated_final_line() {
        let mut reader = Cursor::new(b"request".to_vec());
        assert!(matches!(
            read_limited_line(&mut reader, 20).unwrap(),
            Line::Data(value) if value == b"request"
        ));
    }
}
