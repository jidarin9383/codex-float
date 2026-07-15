import Foundation

/// Actor that owns the local `codex app-server --stdio` process and JSONL protocol.
public actor CodexAppServerClient {
    public struct Configuration: Sendable {
        public var executableURL: URL
        public var requestTimeout: TimeInterval
        public var clientInfo: AppServerClientInfo
        public var arguments: [String]

        public init(
            executableURL: URL,
            requestTimeout: TimeInterval = 15,
            clientInfo: AppServerClientInfo = .init(name: "CodexFloat", version: "0.1.0"),
            arguments: [String] = ["app-server", "--stdio"]
        ) {
            self.executableURL = executableURL
            self.requestTimeout = requestTimeout
            self.clientInfo = clientInfo
            self.arguments = arguments
        }
    }

    private let configuration: Configuration
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var framer = JSONLFramer()
    private var nextRequestID: Int64 = 1
    private var pending: [Int64: CheckedContinuation<Data, Error>] = [:]
    private var isInitialized = false
    private var latestRateLimitsUpdate: WireRateLimitSnapshot?
    /// Prevents double-resume when EOF and terminationHandler both fire.
    private var didHandleTermination = false

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public init(executableURL: URL, requestTimeout: TimeInterval = 15) {
        self.init(configuration: .init(executableURL: executableURL, requestTimeout: requestTimeout))
    }

    /// Ensure process is running and handshake completed.
    public func start() async throws {
        if process?.isRunning == true, isInitialized {
            return
        }
        try await launchAndHandshake()
    }

    public func shutdown() {
        failAllPending(AppServerClientError.processExited(status: -1))
        clearHandlers()
        if let process, process.isRunning {
            process.terminate()
        }
        closePipes()
        process = nil
        framer = JSONLFramer()
        isInitialized = false
        nextRequestID = 1
        latestRateLimitsUpdate = nil
        didHandleTermination = true
    }

    /// Read current account rate limits.
    public func readRateLimits() async throws -> WireGetAccountRateLimitsResponse {
        try await start()
        let data = try await request(method: "account/rateLimits/read", paramsJSON: "null")
        return try JSONDecoder().decode(WireGetAccountRateLimitsResponse.self, from: data)
    }

    /// Optional rolling update snapshot received via `account/rateLimits/updated`.
    public func consumeLatestRateLimitsUpdate() -> WireRateLimitSnapshot? {
        defer { latestRateLimitsUpdate = nil }
        return latestRateLimitsUpdate
    }

    // MARK: - Process lifecycle

    private func launchAndHandshake() async throws {
        shutdown()
        didHandleTermination = false

        let executable = configuration.executableURL
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppServerClientError.executableNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = configuration.arguments
        process.environment = Self.childEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdout = stdoutPipe.fileHandleForReading
        let stderr = stderrPipe.fileHandleForReading
        let stdin = stdinPipe.fileHandleForWriting

        // Avoid SIGPIPE on write after child exit (also ignored process-wide at app launch).
        stdin.writeabilityHandler = nil

        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.ingest(data) }
        }
        // Drain stderr so the pipe cannot fill; never persist contents (may include paths).
        stderr.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] proc in
            Task { await self?.handleProcessTermination(status: proc.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            stdout.readabilityHandler = nil
            stderr.readabilityHandler = nil
            throw AppServerClientError.ioFailure(error.localizedDescription)
        }

        self.process = process
        self.stdinHandle = stdin
        self.stdoutHandle = stdout
        self.stderrHandle = stderr

        let params = AppServerInitializeParams(clientInfo: configuration.clientInfo)
        let paramsData = try JSONEncoder().encode(params)
        let paramsJSON = String(decoding: paramsData, as: UTF8.self)
        _ = try await request(method: "initialize", paramsJSON: paramsJSON)

        try writeLine(#"{"method":"initialized"}"#)
        isInitialized = true
    }

    /// Prefer Homebrew paths when Xcode launches with a minimal PATH.
    private static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        let merged = (extras + existing.split(separator: ":").map(String.init))
        var seen = Set<String>()
        env["PATH"] = merged.filter { seen.insert($0).inserted }.joined(separator: ":")
        // Reduce interactive/TUI assumptions for the child.
        env["TERM"] = env["TERM"] ?? "dumb"
        env["NO_COLOR"] = "1"
        return env
    }

    private func clearHandlers() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        process?.terminationHandler = nil
    }

    private func closePipes() {
        try? stdinHandle?.close()
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
    }

    private func ingest(_ data: Data) {
        if data.isEmpty {
            let status = process?.terminationStatus ?? -1
            handleProcessTermination(status: status)
            return
        }
        for line in framer.push(data) {
            handleLine(line)
        }
    }

    private func handleProcessTermination(status: Int32) {
        guard !didHandleTermination else { return }
        didHandleTermination = true
        clearHandlers()
        for line in framer.finish() {
            handleLine(line)
        }
        failAllPending(AppServerClientError.processExited(status: status))
        isInitialized = false
        process = nil
        closePipes()
    }

    private func handleLine(_ line: String) {
        let envelope: AppServerEnvelope
        do {
            envelope = try AppServerMessageParsing.parseLine(line)
        } catch {
            return
        }

        switch envelope {
        case .response(let id, let result):
            resume(id: id, with: .success(result))
        case .error(let id, let code, let message):
            resume(id: id, with: .failure(AppServerClientError.protocolError(code: code, message: message)))
        case .notification(let method, let params):
            guard method == "account/rateLimits/updated", let params else { return }
            if let wrapper = try? JSONDecoder().decode(WireRateLimitsUpdatedParams.self, from: params) {
                latestRateLimitsUpdate = wrapper.rateLimits
            } else if let update = try? JSONDecoder().decode(WireRateLimitSnapshot.self, from: params) {
                latestRateLimitsUpdate = update
            }
        case .unknown:
            break
        }
    }

    private struct WireRateLimitsUpdatedParams: Decodable {
        var rateLimits: WireRateLimitSnapshot
    }

    // MARK: - Request / response

    private func request(method: String, paramsJSON: String) async throws -> Data {
        guard let process, process.isRunning else {
            throw AppServerClientError.notRunning
        }

        let id = nextRequestID
        nextRequestID += 1

        let line = #"{"id":\#(id),"method":"\#(method)","params":\#(paramsJSON)}"#
        try writeLine(line)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pending[id] = continuation
            let timeout = configuration.requestTimeout
            Task { [weak self] in
                let ns = UInt64(max(timeout, 0.1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                await self?.timeoutIfNeeded(id: id)
            }
        }
    }

    private func timeoutIfNeeded(id: Int64) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: AppServerClientError.timeout)
    }

    private func resume(id: AppServerRequestID, with result: Result<Data, Error>) {
        let key: Int64?
        switch id {
        case .int(let value):
            key = value
        case .string(let value):
            key = Int64(value)
        }
        guard let key, let continuation = pending.removeValue(forKey: key) else { return }
        switch result {
        case .success(let data):
            continuation.resume(returning: data)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func failAllPending(_ error: AppServerClientError) {
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func writeLine(_ line: String) throws {
        guard let stdinHandle, let process, process.isRunning else {
            throw AppServerClientError.notRunning
        }
        var data = Data(line.utf8)
        data.append(0x0A)
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            // Broken pipe / closed stdin after child exit — never crash the host.
            isInitialized = false
            throw AppServerClientError.processExited(status: process.terminationStatus)
        }
    }
}
