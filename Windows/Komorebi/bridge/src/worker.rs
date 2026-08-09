use std::{
    error::Error,
    fmt,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::mpsc::Receiver,
};

use uds_windows::UnixStream;

use crate::command::payload_for;

pub const SHUTDOWN: u32 = 0;

pub fn socket_path_from(local_app_data: impl AsRef<Path>) -> PathBuf {
    local_app_data
        .as_ref()
        .join("komorebi")
        .join("komorebi.sock")
}

pub fn socket_path() -> io::Result<PathBuf> {
    let local_app_data = std::env::var_os("LOCALAPPDATA")
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "LOCALAPPDATA is not set"))?;
    Ok(socket_path_from(local_app_data))
}

pub fn write_payload<W: Write>(writer: &mut W, payload: &[u8]) -> io::Result<()> {
    writer.write_all(payload)
}

#[derive(Debug)]
struct ContextError {
    operation: &'static str,
    path: PathBuf,
    source: io::Error,
}

impl fmt::Display for ContextError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "{} to {}: {}",
            self.operation,
            self.path.display(),
            self.source
        )
    }
}

impl Error for ContextError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        Some(&self.source)
    }
}

fn contextual_error(operation: &'static str, path: &Path, source: io::Error) -> io::Error {
    io::Error::new(
        source.kind(),
        ContextError {
            operation,
            path: path.to_path_buf(),
            source,
        },
    )
}

fn write_payload_to_path<W: Write>(writer: &mut W, path: &Path, payload: &[u8]) -> io::Result<()> {
    write_payload(writer, payload).map_err(|error| contextual_error("write", path, error))
}

pub fn send_command(path: &Path, id: u32) -> io::Result<()> {
    let payload = payload_for(id).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("unknown command ID {id}"),
        )
    })?;
    let mut stream =
        UnixStream::connect(path).map_err(|error| contextual_error("connect", path, error))?;
    write_payload_to_path(&mut stream, path, payload)
}

fn run_loop<S, L>(receiver: Receiver<u32>, mut send: S, mut log_error: L)
where
    S: FnMut(u32) -> io::Result<()>,
    L: FnMut(&str),
{
    for id in receiver {
        if id == SHUTDOWN {
            return;
        }
        if let Err(error) = send(id) {
            let message = format!("command {id} failed: {error}");
            log_error(&message);
        }
    }
}

pub fn run(receiver: Receiver<u32>, path: PathBuf) {
    run_loop(receiver, |id| send_command(&path, id), crate::window::log);
}

#[cfg(test)]
mod tests {
    use std::{error::Error as _, sync::mpsc::channel};

    use super::*;
    use crate::command::{CLOSE, MINIMIZE, MOVE_LEFT};

    #[derive(Default)]
    struct PartialWriter {
        bytes: Vec<u8>,
    }

    impl Write for PartialWriter {
        fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
            let count = buffer.len().min(3);
            self.bytes.extend_from_slice(&buffer[..count]);
            Ok(count)
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn builds_socket_path_from_local_app_data() {
        assert_eq!(
            socket_path_from(Path::new(r"C:\Users\tester\AppData\Local")),
            PathBuf::from(r"C:\Users\tester\AppData\Local\komorebi\komorebi.sock")
        );
    }

    #[test]
    fn write_payload_handles_partial_writes() {
        let mut writer = PartialWriter::default();
        write_payload(&mut writer, b"abcdef\n").unwrap();
        assert_eq!(writer.bytes, b"abcdef\n");
    }

    #[test]
    fn unknown_command_is_invalid_input() {
        let error = send_command(Path::new("unused"), u32::MAX).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidInput);
    }

    #[test]
    fn run_loop_preserves_fifo_and_stops_at_shutdown() {
        let (sender, receiver) = channel();
        for id in [CLOSE, MINIMIZE, SHUTDOWN, MOVE_LEFT] {
            sender.send(id).unwrap();
        }
        drop(sender);

        let mut sent = Vec::new();
        let mut logged = Vec::new();
        run_loop(
            receiver,
            |id| {
                sent.push(id);
                Ok(())
            },
            |message| logged.push(message.to_owned()),
        );

        assert_eq!(sent, [CLOSE, MINIMIZE]);
        assert!(logged.is_empty());
    }

    #[test]
    fn run_loop_returns_normally_for_disconnected_empty_channel() {
        let (sender, receiver) = channel();
        drop(sender);

        run_loop(
            receiver,
            |_| panic!("send must not be called"),
            |_| panic!("log must not be called"),
        );
    }

    #[test]
    fn run_loop_logs_send_errors_and_continues() {
        let (sender, receiver) = channel();
        sender.send(CLOSE).unwrap();
        sender.send(MINIMIZE).unwrap();
        drop(sender);

        let mut sent = Vec::new();
        let mut logged = Vec::new();
        run_loop(
            receiver,
            |id| {
                sent.push(id);
                if id == CLOSE {
                    Err(io::Error::new(io::ErrorKind::BrokenPipe, "send failed"))
                } else {
                    Ok(())
                }
            },
            |message| logged.push(message.to_owned()),
        );

        assert_eq!(sent, [CLOSE, MINIMIZE]);
        assert_eq!(logged, ["command 1 failed: send failed"]);
    }

    #[test]
    fn connect_failure_includes_operation_path_and_source() {
        let path = PathBuf::from(r"C:\__missing_komorebi_task2__\komorebi.sock");
        let error = send_command(&path, CLOSE).unwrap_err();

        assert!(
            error
                .to_string()
                .starts_with(&format!("connect to {}:", path.display()))
        );
        let source = error.source().expect("underlying IO error source");
        assert!(source.downcast_ref::<io::Error>().is_some());
    }

    struct FailingWriter;

    impl Write for FailingWriter {
        fn write(&mut self, _buffer: &[u8]) -> io::Result<usize> {
            Err(io::Error::new(io::ErrorKind::BrokenPipe, "write failed"))
        }

        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn write_failure_includes_operation_path_and_source() {
        let path = Path::new(r"C:\komorebi\komorebi.sock");
        let mut writer = FailingWriter;
        let error = write_payload_to_path(&mut writer, path, b"payload").unwrap_err();

        assert_eq!(error.kind(), io::ErrorKind::BrokenPipe);
        assert_eq!(
            error.to_string(),
            format!("write to {}: write failed", path.display())
        );
        let source = error.source().expect("underlying IO error source");
        assert!(source.downcast_ref::<io::Error>().is_some());
    }
}
