#!/usr/bin/env python3
"""
Code Island Hook
- Sends session state to CodeIsland.app via Unix socket
- For PermissionRequest: waits for user decision from the app with segmented timeout
"""
import json
import os
import socket
import sys
import time

SOCKET_PATH = "/tmp/codeisland.sock"
TIMEOUT_SECONDS = 300  # Total budget for permission decisions (5 min)
SOCKET_TIMEOUT = 30    # Per-attempt socket read timeout
POLL_INTERVAL = 2       # Seconds between polling attempts

# Load config from environment or config file (~/.codeisland/relay.conf)
def load_config():
    """Load config from env vars or ~/.codeisland/relay.conf"""
    config_file = os.path.expanduser("~/.codeisland/relay.conf")

    # Env vars override config file (even if empty string - use "" to force Unix socket mode)
    relay_host = os.environ.get("CODEISLAND_RELAY_HOST", "")
    relay_port = os.environ.get("CODEISLAND_RELAY_PORT", "")
    psk = os.environ.get("CODEISLAND_PSK", "")

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
                            # Only use config value if env var was not set (empty string means Unix socket)
                            if key == "RELAY_HOST" and relay_host == "":
                                relay_host = value
                            elif key == "RELAY_PORT" and relay_port == "":
                                relay_port = value
                            elif key == "PSK" and psk == "":
                                psk = value
            except Exception as e:
                import sys
                print(f"Failed to load config from {config_file}: {e}", file=sys.stderr)

    # Empty RELAY_HOST means use Unix socket (local mode)
    return (
        relay_host if relay_host != "" else None,  # None = Unix socket
        int(relay_port) if relay_port else 0,
        psk
    )

RELAY_HOST, RELAY_PORT, PSK = load_config()


def get_tty():
    """Get the TTY of the Claude process (parent)"""
    import subprocess

    # Get parent PID (Claude process)
    ppid = os.getppid()

    # Try to get TTY from ps command for the parent process
    try:
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            # ps returns just "ttys001", we need "/dev/ttys001"
            if not tty.startswith("/dev/"):
                tty = "/dev/" + tty
            return tty
    except Exception:
        pass

    # Fallback: try current process stdin/stdout
    try:
        return os.ttyname(sys.stdin.fileno())
    except (OSError, AttributeError):
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except (OSError, AttributeError):
        pass
    return None


def parse_conversation_info(session_id):
    """Parse conversation info from JSONL file for remote session display.

    Returns dict with: conversation_summary, conversation_first_message,
    conversation_latest_message, conversation_last_tool
    """
    jsonl_path = os.path.expanduser(f"~/.claude/sessions/{session_id}.jsonl")

    result = {
        "conversation_summary": None,
        "conversation_first_message": None,
        "conversation_latest_message": None,
        "conversation_last_tool": None,
    }

    if not os.path.exists(jsonl_path):
        return result

    try:
        with open(jsonl_path, "r") as f:
            lines = f.readlines()

        if not lines:
            return result

        first_message = None
        latest_message = None
        last_tool = None

        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                msg_type = entry.get("type", "")
                message = entry.get("message", {})

                # Track first human message
                if msg_type == "human" and first_message is None:
                    # Get text content from message
                    if isinstance(message, dict):
                        content = message.get("content", [])
                        if isinstance(content, list):
                            text = " ".join(c.get("text", "") for c in content if c.get("type") == "text")
                        else:
                            text = str(content)
                    else:
                        text = str(message)
                    first_message = text[:200] if text else None  # Limit length

                # Track latest message (prefer human, fall back to assistant)
                if msg_type in ("human", "assistant"):
                    if isinstance(message, dict):
                        content = message.get("content", [])
                        if isinstance(content, list):
                            text = " ".join(c.get("text", "") for c in content if c.get("type") == "text")
                        else:
                            text = str(content)
                    else:
                        text = str(message)
                    latest_message = text[:200] if text else None

                # Track last tool usage
                if msg_type == "assistant":
                    tool_calls = entry.get("message", {}).get("tool_calls", [])
                    if tool_calls:
                        last_tool = tool_calls[-1].get("function", {}).get("name")

            except (json.JSONDecodeError, KeyError, TypeError):
                continue

        result["conversation_first_message"] = first_message
        result["conversation_latest_message"] = latest_message
        result["conversation_last_tool"] = last_tool

        # Generate summary from latest message
        if latest_message:
            result["conversation_summary"] = latest_message[:100] + "..." if len(latest_message) > 100 else latest_message

    except (OSError, IOError) as e:
        pass

    return result


def send_msg(s, msg):
    """Send length-prefixed JSON message"""
    try:
        data = json.dumps(msg).encode()
        s.sendall(len(data).to_bytes(4, "big"))
        s.sendall(data)
        return True
    except (socket.error, OSError):
        return False


def recv_msg(s, timeout=None):
    """Receive length-prefixed JSON message"""
    if timeout:
        s.settimeout(timeout)
    len_bytes = b""
    while len(len_bytes) < 4:
        chunk = s.recv(4 - len(len_bytes))
        if not chunk:
            return None
        len_bytes += chunk
    msg_len = int.from_bytes(len_bytes, "big")
    if msg_len <= 0 or msg_len > 1_000_000:
        return None
    data = b""
    while len(data) < msg_len:
        chunk = s.recv(min(4096, msg_len - len(data)))
        if not chunk:
            return None
        data += chunk
    return json.loads(data.decode())


VERSION = "1.0.0"
REMOTE_HOST = socket.gethostname()
REMOTE_USER = os.environ.get("USER", "unknown")


def send_event(state):
    """Send event to app, return response if any.

    For permission requests: uses segmented timeout (30s socket read + 2s polling)
    up to TIMEOUT_SECONDS total. Falls back to 'ask' if total timeout exceeded,
    allowing Claude Code to show its own permission UI.
    """
    try:
        if RELAY_HOST and RELAY_PORT > 0 and PSK:
            # Remote mode: TCP connection via SSH tunnel with framed+auth protocol
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.connect((RELAY_HOST, RELAY_PORT))

            # Authenticate with PSK (short timeout for auth handshake)
            if not send_msg(sock, {"type": "auth", "psk": PSK, "version": VERSION, "remoteHost": REMOTE_HOST, "remoteUser": REMOTE_USER}):
                sock.close()
                return None
            resp = recv_msg(sock, timeout=10)
            if resp is None or resp.get("type") != "auth_ok":
                sock.close()
                return None

            if state.get("status") == "waiting_for_approval":
                # Segmented timeout: poll with short reads, fallback on total budget exceeded
                start_time = time.time()
                last_poll = start_time

                while time.time() - start_time < TIMEOUT_SECONDS:
                    remaining = TIMEOUT_SECONDS - (time.time() - start_time)
                    sock.settimeout(min(SOCKET_TIMEOUT, remaining))

                    # Send event
                    if not send_msg(sock, {"type": "hook_event", "event": state}):
                        sock.close()
                        return None

                    # Wait for response with polling
                    while time.time() - last_poll < POLL_INTERVAL:
                        poll_remaining = POLL_INTERVAL - (time.time() - last_poll)
                        sock.settimeout(min(poll_remaining, remaining))
                        try:
                            resp = recv_msg(sock, timeout=poll_remaining)
                            if resp is not None:
                                sock.close()
                                return resp
                        except socket.timeout:
                            pass

                        if time.time() - start_time >= TIMEOUT_SECONDS:
                            break
                        if time.time() - last_poll >= POLL_INTERVAL:
                            break

                    last_poll = time.time()

                    # Send keepalive ping to let App know we're still waiting
                    if not send_msg(sock, {"type": "hook_ping"}):
                        break

                # Total timeout exceeded — return 'ask' to fallback to Claude Code's native UI
                sock.close()
                return {"decision": "ask", "reason": "timeout"}
            else:
                # Non-blocking event: fire and forget
                if not send_msg(sock, {"type": "hook_event", "event": state}):
                    sock.close()
                    return None
                sock.close()
        else:
            # Local mode: Unix socket with plain JSON (no segmented timeout — local is fast)
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(TIMEOUT_SECONDS)
            sock.connect(SOCKET_PATH)
            sock.sendall(json.dumps(state).encode())

            if state.get("status") == "waiting_for_approval":
                response = sock.recv(4096)
                sock.close()
                if response:
                    return json.loads(response.decode())
            else:
                sock.close()

        return None
    except (socket.error, OSError, json.JSONDecodeError):
        return None


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    session_id = data.get("session_id", "unknown")
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd", "")
    tool_input = data.get("tool_input", {})

    # Parse conversation info from JSONL for remote session display
    conversation_info = parse_conversation_info(session_id)

    # Get process info
    claude_pid = os.getppid()
    tty = get_tty()

    # Build state object
    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": claude_pid,
        "tty": tty,
        "conversation_summary": conversation_info["conversation_summary"],
        "conversation_first_message": conversation_info["conversation_first_message"],
        "conversation_latest_message": conversation_info["conversation_latest_message"],
        "conversation_last_tool": conversation_info["conversation_last_tool"],
    }

    # Map events to status
    if event == "UserPromptSubmit":
        # User just sent a message - Claude is now processing
        state["status"] = "processing"

    elif event == "PreToolUse":
        state["status"] = "running_tool"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id to Swift for caching
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # Send tool_use_id so Swift can cancel the specific pending permission
        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

    elif event == "PermissionRequest":
        # This is where we can control the permission
        state["status"] = "waiting_for_approval"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # tool_use_id lookup handled by Swift-side cache from PreToolUse

        # Send to app and wait for decision
        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")

            if decision == "allow":
                # Output JSON to approve
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

            elif decision == "deny":
                # Output JSON to deny
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via CodeIsland",
                        },
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

        # No response or "ask" - let Claude Code show its normal UI
        sys.exit(0)

    elif event == "Notification":
        notification_type = data.get("notification_type")
        # Skip permission_prompt - PermissionRequest hook handles this with better info
        if notification_type == "permission_prompt":
            sys.exit(0)
        elif notification_type == "idle_prompt":
            state["status"] = "waiting_for_input"
        else:
            state["status"] = "notification"
        state["notification_type"] = notification_type
        state["message"] = data.get("message")

    elif event == "Stop":
        state["status"] = "waiting_for_input"

    elif event == "SubagentStop":
        # SubagentStop fires when a subagent completes - usually means back to waiting
        state["status"] = "waiting_for_input"

    elif event == "SessionStart":
        # New session starts waiting for user input
        state["status"] = "waiting_for_input"

    elif event == "SessionEnd":
        state["status"] = "ended"

    elif event == "PreCompact":
        # Context is being compacted (manual or auto)
        state["status"] = "compacting"

    else:
        state["status"] = "unknown"

    # Send to socket (fire and forget for non-permission events)
    send_event(state)


if __name__ == "__main__":
    main()
