//
//  HookSocketServer.swift
//  ClaudeIsland
//
//  Unix domain socket server for real-time hook events
//  Supports request/response for permission decisions
//

import Foundation
import os.log
import os.lock

/// Logger for hook socket server
private let logger = Logger(subsystem: "com.codeisland", category: "Hooks")

// MARK: - TCP Relay Server

/// Event received from Claude Code hooks
struct HookEvent: Codable, Sendable {
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?
    let remoteHost: String?
    let remoteUser: String?
    let remoteTmuxTarget: String?
    let lastToolName: String?  // Set by hook to update UI immediately
    /// Conversation summary fields parsed from JSONL by hook (enables remote session display)
    let conversationSummary: String?
    let conversationFirstMessage: String?
    let conversationLatestMessage: String?
    let conversationLastTool: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd, event, status, pid, tty, tool
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case notificationType = "notification_type"
        case message
        case remoteHost = "remote_host"
        case remoteUser = "remote_user"
        case remoteTmuxTarget = "remote_tmux_target"
        case lastToolName = "last_tool_name"
        // Conversation info from JSONL (sent by hook for remote sessions)
        case conversationSummary = "conversation_summary"
        case conversationFirstMessage = "conversation_first_message"
        case conversationLatestMessage = "conversation_latest_message"
        case conversationLastTool = "conversation_last_tool"
        // Additional keys for compatibility with hook script format
        case hookEventName = "hook_event_name"
        case sessionPhase = "session_phase"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        // Handle both 'event' and 'hook_event_name' for event type
        event = try container.decodeIfPresent(String.self, forKey: .event)
            ?? container.decodeIfPresent(String.self, forKey: .hookEventName)
            ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)
        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        toolInput = try container.decodeIfPresent([String: AnyCodable].self, forKey: .toolInput)
        toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        remoteHost = try container.decodeIfPresent(String.self, forKey: .remoteHost)
        remoteUser = try container.decodeIfPresent(String.self, forKey: .remoteUser)
        remoteTmuxTarget = try container.decodeIfPresent(String.self, forKey: .remoteTmuxTarget)
        lastToolName = try container.decodeIfPresent(String.self, forKey: .lastToolName)
        conversationSummary = try container.decodeIfPresent(String.self, forKey: .conversationSummary)
        conversationFirstMessage = try container.decodeIfPresent(String.self, forKey: .conversationFirstMessage)
        conversationLatestMessage = try container.decodeIfPresent(String.self, forKey: .conversationLatestMessage)
        conversationLastTool = try container.decodeIfPresent(String.self, forKey: .conversationLastTool)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(event, forKey: .event)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(pid, forKey: .pid)
        try container.encodeIfPresent(tty, forKey: .tty)
        try container.encodeIfPresent(tool, forKey: .tool)
        try container.encodeIfPresent(toolInput, forKey: .toolInput)
        try container.encodeIfPresent(toolUseId, forKey: .toolUseId)
        try container.encodeIfPresent(notificationType, forKey: .notificationType)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(remoteHost, forKey: .remoteHost)
        try container.encodeIfPresent(remoteUser, forKey: .remoteUser)
        try container.encodeIfPresent(remoteTmuxTarget, forKey: .remoteTmuxTarget)
        try container.encodeIfPresent(lastToolName, forKey: .lastToolName)
        try container.encodeIfPresent(conversationSummary, forKey: .conversationSummary)
        try container.encodeIfPresent(conversationFirstMessage, forKey: .conversationFirstMessage)
        try container.encodeIfPresent(conversationLatestMessage, forKey: .conversationLatestMessage)
        try container.encodeIfPresent(conversationLastTool, forKey: .conversationLastTool)
    }

    /// Create a copy with updated toolUseId
    init(sessionId: String, cwd: String, event: String, status: String, pid: Int?, tty: String?, tool: String?, toolInput: [String: AnyCodable]?, toolUseId: String?, notificationType: String?, message: String?, remoteHost: String? = nil, remoteUser: String? = nil, remoteTmuxTarget: String? = nil, lastToolName: String? = nil, conversationSummary: String? = nil, conversationFirstMessage: String? = nil, conversationLatestMessage: String? = nil, conversationLastTool: String? = nil) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.event = event
        self.status = status
        self.pid = pid
        self.tty = tty
        self.tool = tool
        self.toolInput = toolInput
        self.toolUseId = toolUseId
        self.notificationType = notificationType
        self.message = message
        self.remoteHost = remoteHost
        self.remoteUser = remoteUser
        self.remoteTmuxTarget = remoteTmuxTarget
        self.lastToolName = lastToolName
        self.conversationSummary = conversationSummary
        self.conversationFirstMessage = conversationFirstMessage
        self.conversationLatestMessage = conversationLatestMessage
        self.conversationLastTool = conversationLastTool
    }

    var sessionPhase: SessionPhase {
        if event == "PreCompact" {
            return .compacting
        }

        switch status {
        case "waiting_for_approval":
            // Note: Full PermissionContext is constructed by SessionStore, not here
            // This is just for quick phase checks
            return .waitingForApproval(PermissionContext(
                toolUseId: toolUseId ?? "",
                toolName: tool ?? "unknown",
                toolInput: toolInput,
                receivedAt: Date()
            ))
        case "waiting_for_input":
            return .waitingForInput
        case "running_tool", "processing", "starting":
            return .processing
        case "compacting":
            return .compacting
        default:
            return .idle
        }
    }

    /// Whether this event expects a response (permission request)
    nonisolated var expectsResponse: Bool {
        event == "PermissionRequest" && status == "waiting_for_approval"
    }
}

/// Response to send back to the hook
struct HookResponse: Codable {
    let decision: String // "allow", "deny", or "ask"
    let reason: String?
}

/// Pending permission request waiting for user decision
struct PendingPermission: Sendable {
    let sessionId: String
    let toolUseId: String
    let clientSocket: Int32
    let event: HookEvent
    let receivedAt: Date
}

/// Callback for hook events
typealias HookEventHandler = @Sendable (HookEvent) -> Void

/// Callback for permission response failures (socket died)
typealias PermissionFailureHandler = @Sendable (_ sessionId: String, _ toolUseId: String) -> Void

/// Incoming message from SSH relay (has extra SSH metadata)
struct RelayMessage: Codable, Sendable {
    let type: String  // "auth", "auth_ok", "hook_event", "ping", "pong", "command", "command_result", "disconnect"
    let psk: String?
    let version: String?
    let event: HookEvent?
    let remoteHost: String?
    let remoteUser: String?
    let remoteTmuxTarget: String?
    let action: String?
    let target: String?
    let text: String?
    let result: [String: AnyCodable]?
    let id: String?

    enum CodingKeys: String, CodingKey {
        case type, psk, version, event, remoteHost, remoteUser, remoteTmuxTarget
        case action, target, text, result, id
    }
}

/// Callback for relay commands (e.g., send-text to remote tmux)
typealias RelayCommandHandler = @Sendable (String, String, String) -> Void

/// Unix domain socket server that receives events from Claude Code hooks
/// Uses GCD DispatchSource for non-blocking I/O
class HookSocketServer {
    static let shared = HookSocketServer()
    static let socketPath = "/tmp/codeisland.sock"

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var eventHandler: HookEventHandler?
    private var permissionFailureHandler: PermissionFailureHandler?
    private var relayCommandHandler: RelayCommandHandler?
    private let queue = DispatchQueue(label: "com.codeisland.socket", qos: .userInitiated)

    /// Pending permission requests indexed by toolUseId
    private var pendingPermissions: [String: PendingPermission] = [:]
    private let permissionsLock = NSLock()

    /// Cache tool_use_id from PreToolUse to correlate with PermissionRequest
    /// Key: "sessionId:toolName:serializedInput" -> Queue of tool_use_ids (FIFO)
    /// PermissionRequest events don't include tool_use_id, so we cache from PreToolUse
    private var toolUseIdCache: [String: [String]] = [:]
    private let cacheLock = NSLock()

    /// TCP server socket for SSH relay connections
    private var tcpServerSocket: Int32 = -1
    private var tcpAcceptSource: DispatchSourceRead?

    /// Active TCP connections keyed by host identifier
    private var tcpConnections: [String: Int32] = [:]
    private let tcpConnectionsLock = NSLock()

    /// PSK for relay authentication
    private var relayPSK: String?

    private init() {}

    /// Start the socket server
    func start(onEvent: @escaping HookEventHandler, onPermissionFailure: PermissionFailureHandler? = nil) {
        queue.async { [weak self] in
            self?.startServer(onEvent: onEvent, onPermissionFailure: onPermissionFailure)
        }
    }

    /// Start the TCP relay server on the given port
    func startTCPServer(port: Int, psk: String, onEvent: @escaping HookEventHandler, onCommand: @escaping RelayCommandHandler) {
        queue.async { [weak self] in
            self?.startTCPAcceptLoop(port: port, psk: psk, onEvent: onEvent, onCommand: onCommand)
        }
    }

    /// Stop the TCP relay server
    func stopTCPServer() {
        queue.async { [weak self] in
            self?.stopTCP()
        }
    }

    /// Send a command to a relay connection identified by host:user
    func sendRelayCommand(hostId: String, command: RelayCommand) {
        queue.async { [weak self] in
            self?.sendCommandToRelay(hostId: hostId, command: command)
        }
    }

    private func startServer(onEvent: @escaping HookEventHandler, onPermissionFailure: PermissionFailureHandler?) {
        guard serverSocket < 0 else { return }

        eventHandler = onEvent
        permissionFailureHandler = onPermissionFailure

        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            return
        }

        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBufferPtr = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBufferPtr, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        chmod(Self.socketPath, 0o700)

        guard listen(serverSocket, 10) == 0 else {
            logger.error("Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        logger.info("Listening on \(Self.socketPath, privacy: .public)")

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        acceptSource?.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        acceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
                self?.serverSocket = -1
            }
        }
        acceptSource?.resume()
    }

    // MARK: - TCP Relay Server

    private func startTCPAcceptLoop(port: Int, psk: String, onEvent: @escaping HookEventHandler, onCommand: @escaping RelayCommandHandler) {
        guard tcpServerSocket < 0 else { return }

        relayPSK = psk
        relayCommandHandler = onCommand
        eventHandler = onEvent

        tcpServerSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard tcpServerSocket >= 0 else {
            logger.error("Failed to create TCP socket: \(errno)")
            return
        }

        var nosigpipe: Int32 = 1
        setsockopt(tcpServerSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        var reuseAddr: Int32 = 1
        setsockopt(tcpServerSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        // Bind to all interfaces for LAN access, or use SSH tunnel for remote
        addr.sin_addr.s_addr = inet_addr("0.0.0.0")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(tcpServerSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let bindErrno = errno
            logger.error("Failed to bind TCP socket on port \(port): errno=\(bindErrno) \(String(cString: strerror(bindErrno)), privacy: .public)")
            close(tcpServerSocket)
            tcpServerSocket = -1
            return
        }

        guard listen(tcpServerSocket, 10) == 0 else {
            logger.error("Failed to listen on TCP port \(port): \(errno)")
            close(tcpServerSocket)
            tcpServerSocket = -1
            return
        }

        logger.info("TCP relay server listening on port \(port)")

        tcpAcceptSource = DispatchSource.makeReadSource(fileDescriptor: tcpServerSocket, queue: queue)
        tcpAcceptSource?.setEventHandler { [weak self] in
            self?.acceptTCPConnection()
        }
        tcpAcceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.tcpServerSocket, fd >= 0 {
                close(fd)
                self?.tcpServerSocket = -1
            }
        }
        tcpAcceptSource?.resume()
    }

    private func stopTCP() {
        tcpAcceptSource?.cancel()
        tcpAcceptSource = nil

        tcpConnectionsLock.lock()
        for (_, fd) in tcpConnections {
            close(fd)
        }
        tcpConnections.removeAll()
        tcpConnectionsLock.unlock()

        relayPSK = nil
        relayCommandHandler = nil
    }

    private func acceptTCPConnection() {
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientSocket = accept(tcpServerSocket, nil, &addrLen)
        guard clientSocket >= 0 else {
            logger.warning("TCP accept failed: errno=\(errno)")
            return
        }

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        logger.debug("TCP client accepted on fd \(clientSocket)")

        // Hand off auth handshake to a task so the serial queue isn't blocked by slow clients
        Task {
            await performTCPAuth(clientSocket: clientSocket)
        }
    }

    private func performTCPAuth(clientSocket: Int32) async {
        // Set a 10-second receive deadline for auth handshake
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(clientSocket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Read first message for PSK auth (4-byte length header)
        var lenBuf = [UInt8](repeating: 0, count: 4)
        let lenRead = lenBuf.withUnsafeMutableBytes { bytes in
            read(clientSocket, bytes.baseAddress, bytes.count)
        }
        guard lenRead == 4 else {
            let readErrno = errno
            logger.warning("TCP auth failed: length header read=\(lenRead), errno=\(readErrno)")
            close(clientSocket)
            return
        }
        let msgLen = Int(lenBuf[0]) << 24 | Int(lenBuf[1]) << 16 | Int(lenBuf[2]) << 8 | Int(lenBuf[3])

        guard msgLen > 0 && msgLen < 1_000_000 else {
            logger.warning("TCP auth failed: invalid message length \(msgLen)")
            close(clientSocket)
            return
        }

        var msgData = Data()
        while msgData.count < msgLen {
            var buf = [UInt8](repeating: 0, count: msgLen - msgData.count)
            let r = buf.withUnsafeMutableBytes { bytes in
                read(clientSocket, bytes.baseAddress, bytes.count)
            }
            if r <= 0 {
                let readErrno = errno
                logger.warning("TCP auth failed: payload read=\(r), received=\(msgData.count)/\(msgLen), errno=\(readErrno)")
                close(clientSocket)
                return
            }
            msgData.append(contentsOf: buf[0..<r])
        }
        guard let relayMsg = try? JSONDecoder().decode(RelayMessage.self, from: msgData) else {
            logger.warning("TCP auth failed: invalid JSON payload (\(msgData.count) bytes)")
            close(clientSocket)
            return
        }

        // Verify PSK and require remoteHost/remoteUser to avoid hostId collisions
        let pskToVerify = relayPSK
        logger.info("TCP auth: type=\(relayMsg.type), presented_psk=\((relayMsg.psk ?? "nil").prefix(8)), expected_psk=\((pskToVerify ?? "nil").prefix(8)), remoteHost=\(relayMsg.remoteHost ?? "nil"), remoteUser=\(relayMsg.remoteUser ?? "nil")")
        guard relayMsg.type == "auth",
              let presentedPSK = relayMsg.psk,
              presentedPSK == pskToVerify,
              relayMsg.remoteHost != nil,
              relayMsg.remoteUser != nil else {
            logger.warning("Relay auth failed - invalid PSK or missing remote identity")
            close(clientSocket)
            return
        }

        // Send auth_ok with proper 4-byte length framing (matching recv_msg expectation)
        let authOk = RelayMessage(type: "auth_ok", psk: nil, version: nil, event: nil, remoteHost: nil, remoteUser: nil, remoteTmuxTarget: nil, action: nil, target: nil, text: nil, result: nil, id: nil)
        if let authData = try? JSONEncoder().encode(authOk) {
            var framed = Data()
            var len = UInt32(authData.count).bigEndian
            framed.append(Data(bytes: &len, count: 4))
            framed.append(authData)
            let writeResult = write(clientSocket, (framed as NSData).bytes, framed.count)
            if writeResult <= 0 {
                logger.warning("TCP auth failed: auth_ok write=\(writeResult), errno=\(errno)")
                close(clientSocket)
                return
            }
        }

        // Register connection using socket fd to ensure uniqueness (prevents collisions when same user reconnects)
        let hostId = "\(relayMsg.remoteHost ?? "unknown"):\(relayMsg.remoteUser ?? "unknown"):\(clientSocket)"
        tcpConnectionsLock.lock()
        tcpConnections[hostId] = clientSocket
        tcpConnectionsLock.unlock()

        logger.info("Relay connected: \(hostId, privacy: .public)")

        // Handle this connection
        handleTCPClient(clientSocket: clientSocket, hostId: hostId)
    }

    private func handleTCPClient(clientSocket: Int32, hostId: String) {
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        var allData = Data()

        while true {
            var buf = [UInt8](repeating: 0, count: 65536)
            let bytesRead = read(clientSocket, &buf, buf.count)

            if bytesRead > 0 {
                allData.append(contentsOf: buf[0..<bytesRead])
            } else if bytesRead == 0 {
                // EOF - connection closed
                break
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                // No data available yet, wait a bit before next read
                Thread.sleep(forTimeInterval: 0.05)
                continue
            } else {
                // Error
                break
            }

            // Process complete messages (4-byte length prefix + body)
            while allData.count >= 4 {
                let msgLen = Int(allData[0]) << 24 | Int(allData[1]) << 16 | Int(allData[2]) << 8 | Int(allData[3])
                guard msgLen > 0 && msgLen < 1_000_000 else {
                    // Invalid length - consume 1 byte and continue
                    allData.removeFirst()
                    continue
                }
                guard allData.count >= 4 + msgLen else { break }

                let msgData = allData.subdata(in: 4..<(4 + msgLen))
                allData.removeSubrange(0..<(4 + msgLen))

                processTCPMessage(data: msgData, hostId: hostId, clientSocket: clientSocket)
            }
        }

        // Cleanup
        tcpConnectionsLock.lock()
        tcpConnections.removeValue(forKey: hostId)
        tcpConnectionsLock.unlock()
        close(clientSocket)
        logger.info("Relay disconnected: \(hostId, privacy: .public)")
    }

    private func processTCPMessage(data: Data, hostId: String, clientSocket: Int32) {
        guard let relayMsg = try? JSONDecoder().decode(RelayMessage.self, from: data) else {
            logger.warning("Failed to decode RelayMessage from \(data.count) bytes")
            return
        }

        logger.info("processTCPMessage: type=\(relayMsg.type), event=\(relayMsg.event?.event ?? "nil"), sessionId=\(relayMsg.event?.sessionId.prefix(8) ?? "nil")")

        switch relayMsg.type {
        case "hook_event":
            if let event = relayMsg.event {
                logger.info("Forwarding hook_event: sid=\(event.sessionId.prefix(8)), event=\(event.event), status=\(event.status)")
                // Mirror Unix socket path: cache toolUseId on PreToolUse, clean cache on SessionEnd
                if event.event == "PreToolUse" {
                    cacheToolUseId(event: event)
                }
                if event.event == "SessionEnd" {
                    cleanupCache(sessionId: event.sessionId)
                }
                // Track pending permission for approval requests so app-side approve/deny can route back
                if event.status == "waiting_for_approval" {
                    let toolUseId: String
                    if let eventToolUseId = event.toolUseId {
                        toolUseId = eventToolUseId
                    } else if let cachedToolUseId = popCachedToolUseId(event: event) {
                        toolUseId = cachedToolUseId
                    } else {
                        logger.warning("Permission request missing tool_use_id for \(event.sessionId.prefix(8), privacy: .public) - no cache hit")
                        eventHandler?(event)
                        return
                    }

                    let pending = PendingPermission(
                        sessionId: event.sessionId,
                        toolUseId: toolUseId,
                        clientSocket: clientSocket,
                        event: event,
                        receivedAt: Date()
                    )
                    permissionsLock.lock()
                    pendingPermissions[toolUseId] = pending
                    permissionsLock.unlock()

                    logger.debug("TCP relay: tracking pending permission for \(event.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public), socket=\(clientSocket)")
                    // Don't close clientSocket - keep it open for permission response
                    eventHandler?(event)
                } else {
                    eventHandler?(event)
                }
            } else {
                logger.warning("hook_event type but no event payload")
            }

        case "ping":
            let pong = RelayMessage(type: "pong", psk: nil, version: nil, event: nil, remoteHost: nil, remoteUser: nil, remoteTmuxTarget: nil, action: nil, target: nil, text: nil, result: nil, id: nil)
            if let pongData = try? JSONEncoder().encode(pong) {
                var len = UInt32(pongData.count).bigEndian
                var frame = Data(bytes: &len, count: 4)
                frame.append(pongData)
                _ = write(clientSocket, (frame as NSData).bytes, frame.count)
            }

        case "command_result":
            // Command result from relay (future use)
            break

        default:
            break
        }
    }

    private func sendCommandToRelay(hostId: String, command: RelayCommand) {
        tcpConnectionsLock.lock()
        guard let fd = tcpConnections[hostId] else {
            tcpConnectionsLock.unlock()
            logger.warning("No relay connection for \(hostId, privacy: .public)")
            return
        }
        tcpConnectionsLock.unlock()

        let relayMsg = RelayMessage(
            type: "command",
            psk: nil,
            version: nil,
            event: nil,
            remoteHost: nil,
            remoteUser: nil,
            remoteTmuxTarget: nil,
            action: command.action,
            target: command.target,
            text: command.text,
            result: nil,
            id: command.id
        )

        guard let msgData = try? JSONEncoder().encode(relayMsg) else { return }

        var len = UInt32(msgData.count).bigEndian
        var frame = Data(bytes: &len, count: 4)
        frame.append(msgData)

        var sent = 0
        while sent < frame.count {
            let result = write(fd, (frame as NSData).bytes + sent, frame.count - sent)
            if result <= 0 { break }
            sent += result
        }
    }

    /// Stop the socket server
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(Self.socketPath)

        // Also stop TCP relay server
        stopTCP()

        permissionsLock.lock()
        for (_, pending) in pendingPermissions {
            close(pending.clientSocket)
        }
        pendingPermissions.removeAll()
        permissionsLock.unlock()
    }

    /// Respond to a pending permission request by toolUseId
    func respondToPermission(toolUseId: String, decision: String, reason: String? = nil) {
        queue.async { [weak self] in
            self?.sendPermissionResponse(toolUseId: toolUseId, decision: decision, reason: reason)
        }
    }

    /// Respond to permission by sessionId (finds the most recent pending for that session)
    func respondToPermissionBySession(sessionId: String, decision: String, reason: String? = nil) {
        queue.async { [weak self] in
            self?.sendPermissionResponseBySession(sessionId: sessionId, decision: decision, reason: reason)
        }
    }

    /// Cancel all pending permissions for a session (when Claude stops waiting)
    func cancelPendingPermissions(sessionId: String) {
        queue.async { [weak self] in
            self?.cleanupPendingPermissions(sessionId: sessionId)
        }
    }

    /// Check if there's a pending permission request for a session
    func hasPendingPermission(sessionId: String) -> Bool {
        permissionsLock.lock()
        defer { permissionsLock.unlock() }
        return pendingPermissions.values.contains { $0.sessionId == sessionId }
    }

    /// Get the pending permission details for a session (if any)
    func getPendingPermission(sessionId: String) -> (toolName: String?, toolId: String?, toolInput: [String: AnyCodable]?)? {
        permissionsLock.lock()
        defer { permissionsLock.unlock() }
        guard let pending = pendingPermissions.values.first(where: { $0.sessionId == sessionId }) else {
            return nil
        }
        return (pending.event.tool, pending.toolUseId, pending.event.toolInput)
    }

    /// Cancel a specific pending permission by toolUseId (when tool completes via terminal approval)
    func cancelPendingPermission(toolUseId: String) {
        queue.async { [weak self] in
            self?.cleanupSpecificPermission(toolUseId: toolUseId)
        }
    }

    private func cleanupSpecificPermission(toolUseId: String) {
        permissionsLock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionsLock.unlock()
            return
        }
        permissionsLock.unlock()

        logger.debug("Tool completed externally, closing socket for \(pending.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")
        close(pending.clientSocket)
    }

    private func cleanupPendingPermissions(sessionId: String) {
        permissionsLock.lock()
        let matching = pendingPermissions.filter { $0.value.sessionId == sessionId }
        for (toolUseId, pending) in matching {
            logger.debug("Cleaning up stale permission for \(sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")
            close(pending.clientSocket)
            pendingPermissions.removeValue(forKey: toolUseId)
        }
        permissionsLock.unlock()
    }

    // MARK: - Tool Use ID Cache

    /// Encoder with sorted keys for deterministic cache keys
    private static let sortedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Generate cache key from event properties
    private func cacheKey(sessionId: String, toolName: String?, toolInput: [String: AnyCodable]?) -> String {
        let inputStr: String
        if let input = toolInput,
           let data = try? Self.sortedEncoder.encode(input),
           let str = String(data: data, encoding: .utf8) {
            inputStr = str
        } else {
            inputStr = "{}"
        }
        return "\(sessionId):\(toolName ?? "unknown"):\(inputStr)"
    }

    /// Cache tool_use_id from PreToolUse event (FIFO queue per key)
    private func cacheToolUseId(event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }

        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        if toolUseIdCache[key] == nil {
            toolUseIdCache[key] = []
        }
        toolUseIdCache[key]?.append(toolUseId)
        cacheLock.unlock()

        logger.debug("Cached tool_use_id for \(event.sessionId.prefix(8), privacy: .public) tool:\(event.tool ?? "?", privacy: .public) id:\(toolUseId.prefix(12), privacy: .public)")
    }

    /// Pop and return cached tool_use_id for PermissionRequest (FIFO)
    private func popCachedToolUseId(event: HookEvent) -> String? {
        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard var queue = toolUseIdCache[key], !queue.isEmpty else {
            return nil
        }

        let toolUseId = queue.removeFirst()

        if queue.isEmpty {
            toolUseIdCache.removeValue(forKey: key)
        } else {
            toolUseIdCache[key] = queue
        }

        logger.debug("Retrieved cached tool_use_id for \(event.sessionId.prefix(8), privacy: .public) tool:\(event.tool ?? "?", privacy: .public) id:\(toolUseId.prefix(12), privacy: .public)")
        return toolUseId
    }

    /// Clean up cache entries for a session (on session end)
    private func cleanupCache(sessionId: String) {
        cacheLock.lock()
        let keysToRemove = toolUseIdCache.keys.filter { $0.hasPrefix("\(sessionId):") }
        for key in keysToRemove {
            toolUseIdCache.removeValue(forKey: key)
        }
        cacheLock.unlock()

        if !keysToRemove.isEmpty {
            logger.debug("Cleaned up \(keysToRemove.count) cache entries for session \(sessionId.prefix(8), privacy: .public)")
        }
    }

    // MARK: - Private

    private func acceptConnection() {
        let clientSocket = accept(serverSocket, nil, nil)
        guard clientSocket >= 0 else { return }

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        handleClient(clientSocket)
    }

    private func handleClient(_ clientSocket: Int32) {
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 131072)
        var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 0.5 {
            let pollResult = poll(&pollFd, 1, 50)

            if pollResult > 0 && (pollFd.revents & Int16(POLLIN)) != 0 {
                let bytesRead = read(clientSocket, &buffer, buffer.count)

                if bytesRead > 0 {
                    allData.append(contentsOf: buffer[0..<bytesRead])
                } else if bytesRead == 0 {
                    break
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    break
                }
            } else if pollResult == 0 {
                if !allData.isEmpty {
                    break
                }
            } else {
                break
            }
        }

        guard !allData.isEmpty else {
            close(clientSocket)
            return
        }

        let data = allData

        if let relayMsg = try? JSONDecoder().decode(RelayMessage.self, from: data),
           relayMsg.type == "ping" {
            let pong = RelayMessage(type: "pong", psk: nil, version: nil, event: nil, remoteHost: nil, remoteUser: nil, remoteTmuxTarget: nil, action: nil, target: nil, text: nil, result: nil, id: nil)
            if let pongData = try? JSONEncoder().encode(pong) {
                _ = write(clientSocket, (pongData as NSData).bytes, pongData.count)
            }
            close(clientSocket)
            return
        }

        guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
            logger.warning("Failed to parse Unix socket payload: \(String(data: data, encoding: .utf8) ?? "?", privacy: .public)")
            close(clientSocket)
            return
        }

        logger.debug("Received: \(event.event, privacy: .public) for \(event.sessionId.prefix(8), privacy: .public)")

        if event.event == "PreToolUse" {
            cacheToolUseId(event: event)
        }

        if event.event == "SessionEnd" {
            cleanupCache(sessionId: event.sessionId)
        }

        if event.expectsResponse {
            let toolUseId: String
            if let eventToolUseId = event.toolUseId {
                toolUseId = eventToolUseId
            } else if let cachedToolUseId = popCachedToolUseId(event: event) {
                toolUseId = cachedToolUseId
            } else {
                logger.warning("Permission request missing tool_use_id for \(event.sessionId.prefix(8), privacy: .public) - no cache hit")
                close(clientSocket)
                eventHandler?(event)
                return
            }

            logger.debug("Permission request - keeping socket open for \(event.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")

            let updatedEvent = HookEvent(
                sessionId: event.sessionId,
                cwd: event.cwd,
                event: event.event,
                status: event.status,
                pid: event.pid,
                tty: event.tty,
                tool: event.tool,
                toolInput: event.toolInput,
                toolUseId: toolUseId,  // Use resolved toolUseId
                notificationType: event.notificationType,
                message: event.message
            )

            let pending = PendingPermission(
                sessionId: event.sessionId,
                toolUseId: toolUseId,
                clientSocket: clientSocket,
                event: updatedEvent,
                receivedAt: Date()
            )
            permissionsLock.lock()
            pendingPermissions[toolUseId] = pending
            permissionsLock.unlock()

            eventHandler?(updatedEvent)
            return
        } else {
            close(clientSocket)
        }

        eventHandler?(event)
    }

    private func sendPermissionResponse(toolUseId: String, decision: String, reason: String?) {
        permissionsLock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionsLock.unlock()
            logger.debug("No pending permission for toolUseId: \(toolUseId.prefix(12), privacy: .public)")
            return
        }
        permissionsLock.unlock()

        let response = HookResponse(decision: decision, reason: reason)
        guard let data = try? JSONEncoder().encode(response) else {
            close(pending.clientSocket)
            return
        }

        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending response: \(decision, privacy: .public) for \(pending.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public) (age: \(String(format: "%.1f", age), privacy: .public)s)")

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                logger.error("Failed to get data buffer address")
                return
            }
            let result = write(pending.clientSocket, baseAddress, data.count)
            if result < 0 {
                logger.error("Write failed with errno: \(errno)")
            } else {
                logger.debug("Write succeeded: \(result) bytes")
            }
        }

        close(pending.clientSocket)
    }

    private func sendPermissionResponseBySession(sessionId: String, decision: String, reason: String?) {
        permissionsLock.lock()
        let matchingPending = pendingPermissions.values
            .filter { $0.sessionId == sessionId }
            .sorted { $0.receivedAt > $1.receivedAt }
            .first

        guard let pending = matchingPending else {
            permissionsLock.unlock()
            logger.debug("No pending permission for session: \(sessionId.prefix(8), privacy: .public)")
            return
        }

        pendingPermissions.removeValue(forKey: pending.toolUseId)
        permissionsLock.unlock()

        let response = HookResponse(decision: decision, reason: reason)
        guard let data = try? JSONEncoder().encode(response) else {
            close(pending.clientSocket)
            permissionFailureHandler?(sessionId, pending.toolUseId)
            return
        }

        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending response: \(decision, privacy: .public) for \(sessionId.prefix(8), privacy: .public) tool:\(pending.toolUseId.prefix(12), privacy: .public) (age: \(String(format: "%.1f", age), privacy: .public)s)")

        var writeSuccess = false
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                logger.error("Failed to get data buffer address")
                return
            }
            let result = write(pending.clientSocket, baseAddress, data.count)
            if result < 0 {
                logger.error("Write failed with errno: \(errno)")
            } else {
                logger.debug("Write succeeded: \(result) bytes")
                writeSuccess = true
            }
        }

        close(pending.clientSocket)

        if !writeSuccess {
            permissionFailureHandler?(sessionId, pending.toolUseId)
        }
    }
}

// MARK: - Relay Command

struct RelayCommand: Codable {
    let type: String
    let action: String
    let target: String
    let text: String?
    let id: String?
}

// MARK: - AnyCodable for tool_input

/// Type-erasing codable wrapper for heterogeneous values
/// Used to decode JSON objects with mixed value types
struct AnyCodable: Codable, @unchecked Sendable {
    /// The underlying value (nonisolated(unsafe) because Any is not Sendable)
    nonisolated(unsafe) let value: Any

    /// Initialize with any value
    init(_ value: Any) {
        self.value = value
    }

    /// Decode from JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    /// Encode to JSON
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}
