use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

const ADDRESS: &str = "127.0.0.1:9274";
const MAX_HANDOFFS: u8 = 2;
const VKMT_ROOT: &str = "/Volumes/AverySSD/VKMT";
const PREFIX: &str = "/Volumes/AverySSD/VKMT/prefixes/steam-no-tso-phase6";

#[derive(Default)]
struct State {
    accepted: u8,
    active: bool,
    last_error: Option<String>,
    last_child_pid: Option<u32>,
}

fn json_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
}

fn state_json(state: &State) -> String {
    let error = state
        .last_error
        .as_deref()
        .map(|value| format!("\"{}\"", json_escape(value)))
        .unwrap_or_else(|| "null".to_string());
    let pid = state
        .last_child_pid
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string());
    format!(
        "{{\"ok\":true,\"accepted\":{},\"remaining\":{},\"active\":{},\"last_child_pid\":{},\"last_error\":{}}}",
        state.accepted,
        MAX_HANDOFFS.saturating_sub(state.accepted),
        state.active,
        pid,
        error
    )
}

fn respond(mut stream: TcpStream, status: &str, body: &str) {
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    let _ = stream.write_all(response.as_bytes());
    let _ = stream.flush();
}

fn runtime_log() -> std::io::Result<File> {
    let path = Path::new(VKMT_ROOT).join("logs/steam-handoff-backend.log");
    OpenOptions::new().create(true).append(true).open(path)
}

fn run_wineserver(argument: &str) -> Result<(), String> {
    let status = Command::new(Path::new(VKMT_ROOT).join("wine/build-ec/server/wineserver"))
        .env("WINEPREFIX", PREFIX)
        .arg(argument)
        .status()
        .map_err(|error| format!("wineserver {argument}: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("wineserver {argument} exited with {status}"))
    }
}

fn relaunch_steam() -> Result<u32, String> {
    let build = Path::new(VKMT_ROOT).join("wine/build-ec");
    let steam = PathBuf::from(PREFIX).join("drive_c/Program Files (x86)/Steam/Steam.exe");
    if !steam.is_file() {
        return Err(format!("Steam executable is missing: {}", steam.display()));
    }

    run_wineserver("-k")?;
    run_wineserver("-w")?;

    let output = runtime_log().map_err(|error| format!("open backend log: {error}"))?;
    let errors = output
        .try_clone()
        .map_err(|error| format!("clone backend log: {error}"))?;
    let dyld = format!(
        "{0}/runtime/gstreamer-arm64/lib:{0}/dlls/winecoreaudio.drv:{0}/dlls/secur32:{0}/dlls/ntdll:{0}/dlls/win32u",
        build.display()
    );
    let gst = build.join("runtime/gstreamer-arm64");
    let gst_registry = PathBuf::from(PREFIX).join(".vkmt/gstreamer-registry.bin");

    let child = Command::new(build.join("wine"))
        .arg(&steam)
        .env("WINEPREFIX", PREFIX)
        .env("WINEBUILDDIR", &build)
        .env("WINEBOOTSTRAPMODE", "1")
        .env("DYLD_LIBRARY_PATH", dyld)
        .env("GI_TYPELIB_PATH", gst.join("girepository-1.0"))
        .env("GST_PLUGIN_PATH_1_0", gst.join("lib/gstreamer-1.0"))
        .env("GST_PLUGIN_SYSTEM_PATH_1_0", gst.join("lib/gstreamer-1.0"))
        .env("GST_PLUGIN_SCANNER_1_0", gst.join("libexec/gstreamer-1.0/gst-plugin-scanner"))
        .env("GST_REGISTRY", gst_registry)
        .env("FEX_TSOENABLED", "0")
        .env("FEX_VECTORTSOENABLED", "0")
        .env("FEX_MEMCPYSETTSOENABLED", "0")
        .env("VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY", "0")
        .env("VKMT_STEAM_HANDOFF_NOTIFY", "1")
        .env("WINEDEBUG", "-all")
        .env("WINEDEBUGGER", "none")
        .env("MS_FWD_COMPAT_GL_CTX", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::from(output))
        .stderr(Stdio::from(errors))
        .spawn()
        .map_err(|error| format!("launch Steam: {error}"))?;
    Ok(child.id())
}

fn schedule_handoff(state: Arc<Mutex<State>>) {
    thread::spawn(move || {
        // Let ntdll finish the localhost request before its wineserver is shut down.
        thread::sleep(Duration::from_millis(350));
        let outcome = relaunch_steam();
        let mut guard = state.lock().expect("handoff state poisoned");
        guard.active = false;
        match outcome {
            Ok(pid) => {
                guard.last_child_pid = Some(pid);
                guard.last_error = None;
                eprintln!(
                    "steam-handoff: cycle {} launched pid {}",
                    guard.accepted, pid
                );
            }
            Err(error) => {
                eprintln!("steam-handoff: cycle {} failed: {}", guard.accepted, error);
                guard.last_error = Some(error);
            }
        }
    });
}

fn handle_connection(stream: TcpStream, state: Arc<Mutex<State>>) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    let cloned = match stream.try_clone() {
        Ok(value) => value,
        Err(error) => {
            respond(
                stream,
                "500 Internal Server Error",
                &format!(
                    "{{\"ok\":false,\"error\":\"{}\"}}",
                    json_escape(&error.to_string())
                ),
            );
            return;
        }
    };
    let mut reader = BufReader::new(cloned);
    let mut first = String::new();
    if reader.read_line(&mut first).is_err() {
        respond(
            stream,
            "400 Bad Request",
            "{\"ok\":false,\"error\":\"request line\"}",
        );
        return;
    }
    let mut parts = first.split_whitespace();
    let method = parts.next().unwrap_or("");
    let path = parts.next().unwrap_or("");

    // Consume headers and any small request body so the client can receive a
    // complete response before the scheduled wineserver shutdown.
    let mut content_length = 0usize;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).is_err() || line == "\r\n" || line == "\n" || line.is_empty()
        {
            break;
        }
        if let Some(value) = line.to_ascii_lowercase().strip_prefix("content-length:") {
            content_length = value.trim().parse().unwrap_or(0).min(4096);
        }
    }
    if content_length > 0 {
        let mut body = vec![0u8; content_length];
        let _ = reader.read_exact(&mut body);
    }

    match (method, path) {
        ("GET", "/status") => {
            let body = state_json(&state.lock().expect("handoff state poisoned"));
            respond(stream, "200 OK", &body);
        }
        ("POST", "/steam/handoff") => {
            let mut guard = state.lock().expect("handoff state poisoned");
            if guard.active {
                respond(
                    stream,
                    "409 Conflict",
                    "{\"ok\":false,\"accepted\":false,\"reason\":\"handoff-active\"}",
                );
                return;
            }
            if guard.accepted >= MAX_HANDOFFS {
                respond(
                    stream,
                    "429 Too Many Requests",
                    "{\"ok\":false,\"accepted\":false,\"reason\":\"handoff-limit\"}",
                );
                return;
            }
            guard.accepted += 1;
            guard.active = true;
            let cycle = guard.accepted;
            drop(guard);
            respond(
                stream,
                "202 Accepted",
                &format!(
                    "{{\"ok\":true,\"accepted\":true,\"cycle\":{cycle},\"limit\":{MAX_HANDOFFS}}}"
                ),
            );
            schedule_handoff(state);
        }
        ("POST", "/reset") => {
            let mut guard = state.lock().expect("handoff state poisoned");
            if guard.active {
                respond(
                    stream,
                    "409 Conflict",
                    "{\"ok\":false,\"reason\":\"handoff-active\"}",
                );
                return;
            }
            *guard = State::default();
            respond(stream, "200 OK", "{\"ok\":true,\"reset\":true}");
        }
        _ => respond(
            stream,
            "404 Not Found",
            "{\"ok\":false,\"error\":\"not-found\"}",
        ),
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let listener = TcpListener::bind(ADDRESS)?;
    let state = Arc::new(Mutex::new(State::default()));
    eprintln!("vkmt-steam-handoff-backend listening on http://{ADDRESS}");
    for incoming in listener.incoming() {
        match incoming {
            Ok(stream)
                if stream
                    .peer_addr()
                    .map(|peer| peer.ip().is_loopback())
                    .unwrap_or(false) =>
            {
                handle_connection(stream, Arc::clone(&state));
            }
            Ok(stream) => respond(
                stream,
                "403 Forbidden",
                "{\"ok\":false,\"error\":\"loopback-only\"}",
            ),
            Err(error) => eprintln!("steam-handoff: accept failed: {error}"),
        }
    }
    Ok(())
}
