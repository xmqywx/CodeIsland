#!/usr/bin/env python3
"""
CodeIsland SSH Relay
- Runs on remote server, receives hook events from codeisland-state.py
- Forwards events to Mac via TCP (SSH reverse tunnel)
- Receives commands from Mac (jump, send-text) and executes via tmux

Supports daemon mode with --daemon flag and automatic restart on crash.
"""
import argparse
import atexit
import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from typing import Optional

VERSION = "1.2.0"

# Config from environment or config file (~/.codeisland/relay.conf)
def load_config():
    """Load config from env vars or ~/.codeisland/relay.conf"""
    config_file = os.path.expanduser("~/.codeisland/relay.conf")

    # Env vars take precedence
    relay_host = os.environ.get("CODEISLAND_RELAY_HOST")
    relay_port = os.environ.get("CODEISLAND_RELAY_PORT")
    psk = os.environ.get("CODEISLAND_PSK")

    # If not in env, try config file
    if not relay_host or not relay_port or not psk:
        if os.path.exists(config_file):
            try:
                with open(config_file) as f:
                    for line in f:
                        line = line.strip()
                        if not line or line.startswith("#"):
                            continue
                        if "=" in line:
                            key, value = line.split("=", 1)
                            key = key.strip()
                            value = value.strip()
                            if key == "RELAY_HOST":
                                relay_host = relay_host or value
                            elif key == "RELAY_PORT":
                                relay_port = relay_port or value
                            elif key == "PSK":
                                psk = psk or value
            except Exception as e:
                pass

    return (
        relay_host or "localhost",
        int(relay_port) if relay_port else 0,
        psk or ""
    )

RELAY_HOST, RELAY_PORT, PSK = load_config()
HEARTBEAT_INTERVAL = 30  # seconds
RECONNECT_BASE_DELAY = 1  # seconds
RECONNECT_MAX_DELAY = 60  # seconds

# Global state
sock: Optional[socket.socket] = None
lock = threading.Lock()
should_exit = False
reconnect_delay = RECONNECT_BASE_DELAY

# Config file and pidfile paths
CONFIG_FILE = os.path.expanduser("~/.codeisland/relay.conf")
PIDFILE = os.path.expanduser("~/.codeisland/relay.pid")
LOG_FILE = "/tmp/codeisland-relay.log"


def log(msg: str) -> None:
    print(f"[codeisland-ssh-relay] {msg}", flush=True)


def send_msg(s: socket.socket, msg: dict) -> bool:
    try:
        data = json.dumps(msg).encode()
        s.sendall(len(data).to_bytes(4, "big"))
        s.sendall(data)
        return True
    except Exception as e:
        log(f"send_msg failed: {e}")
        return False


def recv_msg(s: socket.socket) -> Optional[dict]:
    try:
        len_bytes = b""
        while len(len_bytes) < 4:
            len_bytes += s.recv(4 - len(len_bytes))
        msg_len = int.from_bytes(len_bytes, "big")
        data = b""
        while len(data) < msg_len:
            chunk = s.recv(min(4096, msg_len - len(data)))
            if not chunk:
                return None
            data += chunk
        return json.loads(data.decode())
    except Exception as e:
        log(f"recv_msg failed: {e}")
        return None


def connect_to_mac() -> Optional[socket.socket]:
    global reconnect_delay
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect((RELAY_HOST, RELAY_PORT))
        # Auth with PSK
        # SECURITY NOTE: PSK is sent in cleartext during handshake.
        # This is acceptable for LAN connections over SSH tunnels which provide encryption.
        if not send_msg(s, {
            "type": "auth",
            "psk": PSK,
            "version": VERSION,
            "remoteHost": socket.gethostname(),
            "remoteUser": os.getenv("USER", "unknown")
        }):
            s.close()
            return None
        resp = recv_msg(s)
        if resp is None or resp.get("type") != "auth_ok":
            s.close()
            return None
        log("Connected to Mac")
        reconnect_delay = RECONNECT_BASE_DELAY
        return s
    except Exception as e:
        log(f"connect_to_mac failed: {e}")
        return None


def read_stdin_events():
    """Read hook events from stdin and forward them."""
    try:
        for line in sys.stdin:
            if not line.strip():
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            # Enrich with tmux info if available
            if event.get("event") == "SessionStart":
                tmux_target = find_tmux_target_for_pid(os.getppid())
                if tmux_target:
                    event["remote_tmux_target"] = tmux_target

            with lock:
                if sock and sock.fileno() != -1:
                    if not send_msg(sock, {"type": "hook_event", "event": event}):
                        log("Failed to forward event, will reconnect")
    except Exception as e:
        log(f"stdin reader error: {e}")


def find_tmux_target_for_pid(pid: int) -> Optional[str]:
    """
    Find tmux session:window.pane for a given PID using direct pane query.
    Uses `tmux list-panes -a` to get all panes with their session+pane info in one pass,
    then checks process ancestry via ps --ppid for each pane's root pid.
    This is more reliable than parsing pane_start_command.
    """
    try:
        # Get all panes: pane_id, session_name, window_index, pane_pid
        result = subprocess.run(
            ["tmux", "list-panes", "-a", "-F", "#{pane_id}:#{session_name}:#{window_index}:#{pane_pid}"],
            capture_output=True, text=True, timeout=5
        )
        for line in result.stdout.strip().split("\n"):
            if not line:
                continue
            parts = line.split(":")
            if len(parts) < 4:
                continue
            pane_id, session_name, window_index = parts[0], parts[1], parts[2]
            pane_pid_str = parts[3]

            # Check if our PID is in this pane's process tree (descendant of pane_pid)
            is_child = subprocess.run(
                ["sh", "-c", f"ps -o pid= --ppid {pane_pid_str} 2>/dev/null | grep -w {pid} || true"],
                capture_output=True, text=True, timeout=5
            )
            if str(pid) in is_child.stdout or is_child.returncode == 0:
                return f"{session_name}:{window_index}.{pane_id}"
    except Exception as e:
        log(f"find_tmux_target_for_pid error: {e}")
    return None


TARGET_PATTERN = re.compile(r'^[a-zA-Z0-9_.:#@-]+$')

def validate_target(target: str) -> bool:
    """Validate tmux target to prevent command injection."""
    return bool(TARGET_PATTERN.match(target))


def execute_tmux_command(action: str, target: str, text: str) -> dict:
    """Execute a tmux command from Mac."""
    # Validate target to prevent injection attacks
    if not validate_target(target):
        return {"ok": False, "stderr": f"Invalid target: {target}"}
    try:
        if action == "send-text":
            # Use -- to pass literal text (stops option parsing)
            # Escape single quotes for shell
            escaped = text.replace("'", "'\\''")
            result = subprocess.run(
                ["tmux", "send-keys", "-t", target, "--", text],
                capture_output=True, text=True, timeout=5
            )
            return {"ok": result.returncode == 0, "stderr": result.stderr}
        elif action == "select-window":
            result = subprocess.run(
                ["tmux", "select-window", "-t", target],
                capture_output=True, text=True, timeout=5
            )
            return {"ok": result.returncode == 0, "stderr": result.stderr}
        elif action == "send-enter":
            result = subprocess.run(
                ["tmux", "send-keys", "-t", target, "Enter"],
                capture_output=True, text=True, timeout=5
            )
            return {"ok": result.returncode == 0, "stderr": result.stderr}
        else:
            return {"ok": False, "stderr": f"Unknown action: {action}"}
    except Exception as e:
        return {"ok": False, "stderr": str(e)}


def heartbeat_loop():
    """Send periodic heartbeats to Mac."""
    global should_exit
    while not should_exit:
        time.sleep(HEARTBEAT_INTERVAL)
        with lock:
            if sock and sock.fileno() != -1:
                if not send_msg(sock, {"type": "ping"}):
                    log("Heartbeat failed")
                    try:
                        sock.close()
                    except Exception:
                        pass


def write_pidfile():
    """Write our PID to the pidfile."""
    try:
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()) + "\n")
    except Exception as e:
        log(f"Failed to write pidfile: {e}")


def remove_pidfile():
    """Remove the pidfile on exit."""
    try:
        os.unlink(PIDFILE)
    except Exception:
        pass


def daemonize():
    """
    Double-fork daemonization.
    Returns True if we are the daemon process, False if parent.
    """
    # First fork
    try:
        pid = os.fork()
        if pid > 0:
            # Parent: wait for child, then exit
            _, status = os.waitpid(pid, 0)
            sys.exit(os.WEXITSTATUS(status))
    except OSError as e:
        sys.stderr.write(f"First fork failed: {e}\n")
        sys.exit(1)

    # Decouple from parent environment
    os.chdir("/")
    os.setsid()
    os.umask(0o022)

    # Second fork
    try:
        pid = os.fork()
        if pid > 0:
            # First child: exit
            sys.exit(0)
    except OSError as e:
        sys.stderr.write(f"Second fork failed: {e}\n")
        sys.exit(1)

    # Redirect stdio to /dev/null or log file
    sys.stdout.flush()
    sys.stderr.flush()
    devnull = open(os.devnull, "r+")
    os.dup2(devnull.fileno(), sys.stdin.fileno())
    os.dup2(devnull.fileno(), sys.stdout.fileno())
    os.dup2(devnull.fileno(), sys.stderr.fileno())
    devnull.close()

    # Write pidfile and register cleanup
    write_pidfile()
    atexit.register(remove_pidfile)

    return True


def reload_config(signum, frame):
    """Handle SIGHUP: reload config from file."""
    global RELAY_HOST, RELAY_PORT, PSK
    log("SIGHUP received, reloading config...")
    RELAY_HOST, RELAY_PORT, PSK = load_config()
    log(f"Config reloaded: host={RELAY_HOST}, port={RELAY_PORT}")


def graceful_shutdown(signum, frame):
    """Handle SIGTERM/SIGINT: graceful shutdown."""
    global should_exit
    log(f"Signal {signum} received, shutting down...")
    should_exit = True


def main():
    global sock, should_exit, reconnect_delay

    parser = argparse.ArgumentParser(description="CodeIsland SSH Relay")
    parser.add_argument("--daemon", action="store_true", help="Run as daemon")
    parser.add_argument("--foreground", action="store_true", help="Run in foreground (default)")
    parser.add_argument("--pidfile", default=PIDFILE, help="Path to pidfile")
    parser.add_argument("--config", default=CONFIG_FILE, help="Path to config file")
    args = parser.parse_args()

    if not RELAY_PORT:
        log("ERROR: CODEISLAND_RELAY_PORT not set")
        sys.exit(1)

    log(f"Starting relay v{VERSION} -> {RELAY_HOST}:{RELAY_PORT}")

    # Register signal handlers
    signal.signal(signal.SIGHUP, reload_config)
    signal.signal(signal.SIGTERM, graceful_shutdown)
    signal.signal(signal.SIGINT, graceful_shutdown)

    # Daemonize if requested
    if args.daemon and not args.foreground:
        log("Daemonizing...")
        daemonize()

    log(f"Relay started (pid={os.getpid()})")

    # Start heartbeat thread
    hb_thread = threading.Thread(target=heartbeat_loop, daemon=True)
    hb_thread.start()

    # Start stdin reader in background
    stdin_thread = threading.Thread(target=read_stdin_events, daemon=True)
    stdin_thread.start()

    while not should_exit:
        s = connect_to_mac()
        with lock:
            sock = s

        if s is None:
            log(f"Reconnecting in {reconnect_delay}s...")
            time.sleep(reconnect_delay)
            reconnect_delay = min(reconnect_delay * 2, RECONNECT_MAX_DELAY)
            continue

        reconnect_delay = RECONNECT_BASE_DELAY  # Reset backoff on successful connect

        # Connected — read commands from Mac
        while not should_exit:
            try:
                s.settimeout(60)
                msg = recv_msg(s)
                if msg is None:
                    break

                msg_type = msg.get("type")
                if msg_type == "pong":
                    pass  # heartbeat response, ignore
                elif msg_type == "command":
                    action = msg.get("action", "")
                    target = msg.get("target", "")
                    text = msg.get("text", "")
                    result = execute_tmux_command(action, target, text)
                    send_msg(s, {"type": "command_result", "id": msg.get("id"), "result": result})
                elif msg_type == "disconnect":
                    log("Mac requested disconnect")
                    break
            except socket.timeout:
                continue
            except Exception as e:
                log(f"Command loop error: {e}")
                break

        with lock:
            if sock and sock.fileno() != -1:
                try:
                    sock.close()
                except Exception:
                    pass
                sock = None

    log("Relay exited")

    log("Relay exiting")


if __name__ == "__main__":
    main()
