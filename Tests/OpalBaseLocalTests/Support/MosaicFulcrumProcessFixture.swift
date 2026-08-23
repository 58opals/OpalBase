// MosaicFulcrumProcessFixture.swift

#if os(macOS)
import Foundation
import Network
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

enum MosaicFulcrumProcessFixture {
    enum Presence: Equatable {
        case absent
        case mempool
        case confirmed(blockHash: Data, confirmations: UInt32)
    }

    static let integrationEnvironmentKey =
        "OPALBASE_RUN_MOSAIC_FULCRUM_PROCESS_INTEGRATION"
    static let workerEnvironmentKey =
        "OPALBASE_MOSAIC_FULCRUM_PROCESS_WORKER"
    static let rootEnvironmentKey =
        "OPALBASE_MOSAIC_FULCRUM_PROCESS_ROOT"

    static var isParentIntegrationEnabled: Bool {
        ProcessInfo.processInfo.environment[integrationEnvironmentKey] == "1"
            && isWorker == false
    }

    static var isWorker: Bool {
        ProcessInfo.processInfo.environment[workerEnvironmentKey] == "1"
    }

    static func launch(
        transactionBytes: Data,
        transactionIdentifier: String
    ) throws -> Session {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "OpalBaseMosaicFulcrum.\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let state = State(
            transactionHexadecimal: transactionBytes.hexadecimalString,
            transactionIdentifier: transactionIdentifier,
            presence: .absent,
            blockHashHexadecimal: nil,
            confirmations: 0
        )
        try writeState(state, at: rootURL)

        let bundleURL = Bundle(
            for: MosaicFulcrumProcessBundleMarker.self
        ).bundleURL
        var environment = ProcessInfo.processInfo.environment
        for key in Array(environment.keys) where
            key.hasPrefix("XCTest") || key.hasPrefix("XCInject") {
            environment.removeValue(forKey: key)
        }
        environment.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
        environment.removeValue(forKey: integrationEnvironmentKey)
        environment[workerEnvironmentKey] = "1"
        environment[rootEnvironmentKey] = rootURL.path

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.arguments = [
            "xctest",
            "-XCTest",
            "OpalBaseLocalTests.MosaicFulcrumProcessWorkerValidator",
            bundleURL.path
        ]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: rootURL)
            throw error
        }

        do {
            let endpoint = try waitForEndpoint(
                process: process,
                outputPipe: outputPipe,
                rootURL: rootURL
            )
            return Session(
                rootURL: rootURL,
                endpoint: endpoint,
                process: process,
                outputPipe: outputPipe
            )
        } catch {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            try? FileManager.default.removeItem(at: rootURL)
            throw error
        }
    }

    static func runWorker() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment[
            rootEnvironmentKey
        ] else {
            throw FixtureFailure.invalidConfiguration(
                "Missing isolated Fulcrum fixture root."
            )
        }
        let rootURL = URL(filePath: rootPath, directoryHint: .isDirectory)
        let server = try Server(rootURL: rootURL)
        let endpoint = try await server.start()
        try endpoint.absoluteString.write(
            to: endpointURL(rootURL),
            atomically: true,
            encoding: .utf8
        )

        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while FileManager.default.fileExists(
            atPath: stopURL(rootURL).path
        ) == false {
            guard ContinuousClock.now < deadline else {
                await server.stop()
                throw FixtureFailure.deadlineExceeded
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        await server.stop()
    }

    fileprivate static func writeState(
        _ state: State,
        at rootURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(
            to: stateURL(rootURL),
            options: .atomic
        )
    }

    fileprivate static func readState(at rootURL: URL) throws -> State {
        try JSONDecoder().decode(
            State.self,
            from: Data(contentsOf: stateURL(rootURL))
        )
    }

    fileprivate static func endpointURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: "endpoint")
    }

    fileprivate static func stateURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: "state.json")
    }

    fileprivate static func methodsURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: "methods.json")
    }

    fileprivate static func stopURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: "stop")
    }

    private static func waitForEndpoint(
        process: Process,
        outputPipe: Pipe,
        rootURL: URL
    ) throws -> URL {
        let endpointFileURL = endpointURL(rootURL)
        let deadline = Date().addingTimeInterval(5)
        while FileManager.default.fileExists(
            atPath: endpointFileURL.path
        ) == false,
        process.isRunning,
        Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard FileManager.default.fileExists(
            atPath: endpointFileURL.path
        ) else {
            let summary: String
            if process.isRunning {
                summary = "Worker did not publish an endpoint within five seconds."
            } else {
                let output = outputPipe.fileHandleForReading
                    .readDataToEndOfFile()
                summary = String(data: output, encoding: .utf8) ?? ""
            }
            throw FixtureFailure.workerFailed(summary)
        }
        let endpointText = try String(
            contentsOf: endpointFileURL,
            encoding: .utf8
        )
        guard let endpoint = URL(
            string: endpointText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ) else {
            throw FixtureFailure.invalidConfiguration(
                "Worker returned an invalid endpoint."
            )
        }
        return endpoint
    }
}

extension MosaicFulcrumProcessFixture {
    final class Session {
        let endpoint: URL

        private let rootURL: URL
        private let process: Process
        private let outputPipe: Pipe
        private var stopped = false

        fileprivate init(
            rootURL: URL,
            endpoint: URL,
            process: Process,
            outputPipe: Pipe
        ) {
            self.rootURL = rootURL
            self.endpoint = endpoint
            self.process = process
            self.outputPipe = outputPipe
        }

        func setPresence(_ presence: Presence) throws {
            var state = try MosaicFulcrumProcessFixture.readState(
                at: rootURL
            )
            switch presence {
            case .absent:
                state.presence = .absent
                state.blockHashHexadecimal = nil
                state.confirmations = 0
            case .mempool:
                state.presence = .mempool
                state.blockHashHexadecimal = nil
                state.confirmations = 0
            case let .confirmed(blockHash, confirmations):
                guard blockHash.count
                        == OpalBase.Transaction.Hash.expectedByteCount,
                      confirmations > 0 else {
                    throw FixtureFailure.invalidConfiguration(
                        "Confirmed fixture state requires an exact block hash and a positive confirmation count."
                    )
                }
                state.presence = .confirmed
                state.blockHashHexadecimal = blockHash.hexadecimalString
                state.confirmations = confirmations
            }
            try MosaicFulcrumProcessFixture.writeState(
                state,
                at: rootURL
            )
        }

        func readRecordedMethods() throws -> [String] {
            let url = MosaicFulcrumProcessFixture.methodsURL(rootURL)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }
            return try JSONDecoder().decode(
                [String].self,
                from: Data(contentsOf: url)
            )
        }

        func stop() {
            guard stopped == false else { return }
            stopped = true
            FileManager.default.createFile(
                atPath: MosaicFulcrumProcessFixture.stopURL(rootURL).path,
                contents: Data()
            )
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            _ = outputPipe.fileHandleForReading.readDataToEndOfFile()
            try? FileManager.default.removeItem(at: rootURL)
        }

        deinit {
            stop()
        }
    }
}

extension MosaicFulcrumProcessFixture {
    fileprivate struct State: Codable {
        enum StoredPresence: String, Codable {
            case absent
            case mempool
            case confirmed
        }

        let transactionHexadecimal: String
        let transactionIdentifier: String
        var presence: StoredPresence
        var blockHashHexadecimal: String?
        var confirmations: UInt32
    }

    fileprivate enum FixtureFailure: Error, CustomStringConvertible {
        case deadlineExceeded
        case invalidConfiguration(String)
        case workerFailed(String)

        var description: String {
            switch self {
            case .deadlineExceeded:
                "Isolated Fulcrum fixture exceeded its 60-second deadline."
            case let .invalidConfiguration(summary):
                summary
            case let .workerFailed(summary):
                "Isolated Fulcrum worker failed: \(summary)"
            }
        }
    }
}

extension MosaicFulcrumProcessFixture {
    fileprivate actor Server {
        private let rootURL: URL
        private let listener: NWListener
        private let queue = DispatchQueue(
            label: "OpalBase.MosaicFulcrumProcessFixture"
        )
        private var connections: [NWConnection] = []
        private var methods: [String] = []
        private var startContinuation:
            CheckedContinuation<URL, any Error>?

        init(rootURL: URL) throws {
            self.rootURL = rootURL
            let webSocket = NWProtocolWebSocket.Options()
            webSocket.autoReplyPing = true
            webSocket.maximumMessageSize = 4 * 1_024 * 1_024
            let queue = self.queue
            webSocket.setClientRequestHandler(queue) { _, _ in
                .init(status: .accept, subprotocol: nil)
            }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(.loopback),
                port: .any
            )
            parameters.defaultProtocolStack.applicationProtocols.insert(
                webSocket,
                at: 0
            )
            listener = try NWListener(using: parameters, on: .any)
        }

        func start() async throws -> URL {
            try await withCheckedThrowingContinuation {
                continuation in
                startContinuation = continuation
                listener.stateUpdateHandler = { [server = self] state in
                    Task { await server.handleListenerState(state) }
                }
                listener.newConnectionHandler = {
                    [server = self] connection in
                    Task { await server.accept(connection) }
                }
                listener.start(queue: queue)
            }
        }

        func stop() {
            let activeConnections = connections
            connections.removeAll(keepingCapacity: false)
            for connection in activeConnections {
                connection.cancel()
            }
            startContinuation?.resume(throwing: CancellationError())
            startContinuation = nil
            listener.cancel()
        }

        private func handleListenerState(_ state: NWListener.State) {
            switch state {
            case .ready:
                guard let port = listener.port else { return }
                resolveStart(
                    .success(
                        URL(
                            string: "ws://127.0.0.1:\(port.rawValue)"
                        )!
                    )
                )
            case let .failed(error):
                resolveStart(.failure(error))
            default:
                break
            }
        }

        private func accept(_ connection: NWConnection) {
            connections.append(connection)
            connection.stateUpdateHandler = {
                [server = self, connection] state in
                if case .failed = state {
                    Task { await server.remove(connection) }
                } else if case .cancelled = state {
                    Task { await server.remove(connection) }
                }
            }
            connection.start(queue: queue)
            receive(on: connection)
        }

        private func remove(_ connection: NWConnection) {
            connections.removeAll { $0 === connection }
        }

        private func receive(on connection: NWConnection) {
            connection.receiveMessage {
                [server = self, connection] data, _, _, error in
                Task {
                    await server.handleMessage(
                        data,
                        error: error,
                        connection: connection
                    )
                }
            }
        }

        private func handleMessage(
            _ data: Data?,
            error: NWError?,
            connection: NWConnection
        ) {
            if error != nil {
                remove(connection)
                return
            }
            guard let data,
                  let request = try? JSONSerialization.jsonObject(
                    with: data
                  ) as? [String: Any],
                  let method = request["method"] as? String,
                  let identifier = request["id"] else {
                send(
                    errorCode: -32_700,
                    message: "Invalid JSON-RPC request.",
                    identifier: NSNull(),
                    connection: connection
                )
                receive(on: connection)
                return
            }

            record(method)
            let parameters = request["params"] as? [Any] ?? []
            do {
                switch method {
                case "server.version":
                    send(
                        result: ["Mosaic Fulcrum Fixture", "1.5.3"],
                        identifier: identifier,
                        connection: connection
                    )
                case "server.features":
                    send(
                        result: [
                            "genesis_hash": Data(
                                OpalBase.Network.Environment.mainnet
                                    .mosaicGenesisHash
                            ).hexadecimalString,
                            "hash_function": "sha256",
                            "server_version": "Mosaic Fulcrum Fixture",
                            "protocol_max": "1.6.0",
                            "protocol_min": "1.4.0"
                        ],
                        identifier: identifier,
                        connection: connection
                    )
                case "server.ping":
                    send(
                        result: NSNull(),
                        identifier: identifier,
                        connection: connection
                    )
                case "blockchain.transaction.broadcast":
                    try handleBroadcast(
                        parameters: parameters,
                        identifier: identifier,
                        connection: connection
                    )
                case "blockchain.transaction.get":
                    try handleTransactionGet(
                        parameters: parameters,
                        identifier: identifier,
                        connection: connection
                    )
                default:
                    send(
                        errorCode: -32_601,
                        message: "Method not found.",
                        identifier: identifier,
                        connection: connection
                    )
                }
            } catch {
                send(
                    errorCode: -32_602,
                    message: "Invalid fixture request.",
                    identifier: identifier,
                    connection: connection
                )
            }
            receive(on: connection)
        }

        private func handleBroadcast(
            parameters: [Any],
            identifier: Any,
            connection: NWConnection
        ) throws {
            let state = try MosaicFulcrumProcessFixture.readState(
                at: rootURL
            )
            guard parameters.count == 1,
                  parameters[0] as? String
                    == state.transactionHexadecimal else {
                throw FixtureFailure.invalidConfiguration(
                    "Broadcast bytes did not match the isolated fixture transaction."
                )
            }
            send(
                result: state.transactionIdentifier,
                identifier: identifier,
                connection: connection
            )
        }

        private func handleTransactionGet(
            parameters: [Any],
            identifier: Any,
            connection: NWConnection
        ) throws {
            let state = try MosaicFulcrumProcessFixture.readState(
                at: rootURL
            )
            guard parameters.count == 2,
                  parameters[0] as? String
                    == state.transactionIdentifier,
                  parameters[1] as? Bool == true else {
                throw FixtureFailure.invalidConfiguration(
                    "Transaction lookup did not request the exact verbose transaction."
                )
            }
            guard state.presence != .absent else {
                send(
                    errorCode: -5,
                    message: "No such mempool or blockchain transaction.",
                    identifier: identifier,
                    connection: connection
                )
                return
            }

            var result: [String: Any] = [
                "hash": state.transactionIdentifier,
                "hex": state.transactionHexadecimal,
                "locktime": 0,
                "size": state.transactionHexadecimal.count / 2,
                "txid": state.transactionIdentifier,
                "version": 2,
                "vin": [],
                "vout": []
            ]
            if state.presence == .confirmed,
               let blockHash = state.blockHashHexadecimal {
                result["blockhash"] = blockHash
                result["blocktime"] = 1_900_000_000
                result["confirmations"] = state.confirmations
            }
            send(
                result: result,
                identifier: identifier,
                connection: connection
            )
        }

        private func record(_ method: String) {
            methods.append(method)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(methods) {
                try? data.write(
                    to: MosaicFulcrumProcessFixture.methodsURL(rootURL),
                    options: .atomic
                )
            }
        }

        private func send(
            result: Any,
            identifier: Any,
            connection: NWConnection
        ) {
            send(
                [
                    "jsonrpc": "2.0",
                    "id": identifier,
                    "result": result
                ],
                connection: connection
            )
        }

        private func send(
            errorCode: Int,
            message: String,
            identifier: Any,
            connection: NWConnection
        ) {
            send(
                [
                    "jsonrpc": "2.0",
                    "id": identifier,
                    "error": ["code": errorCode, "message": message]
                ],
                connection: connection
            )
        }

        private func send(
            _ response: [String: Any],
            connection: NWConnection
        ) {
            guard let data = try? JSONSerialization.data(
                withJSONObject: response
            ) else {
                connection.cancel()
                return
            }
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(
                identifier: UUID().uuidString,
                metadata: [metadata]
            )
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if error != nil { connection.cancel() }
                }
            )
        }

        private func resolveStart(
            _ result: Result<URL, any Error>
        ) {
            let continuation = startContinuation
            startContinuation = nil
            continuation?.resume(with: result)
        }
    }
}

private final class MosaicFulcrumProcessBundleMarker: NSObject {}

@Suite(
    "Mosaic isolated Fulcrum process worker",
    .serialized,
    .enabled(if: MosaicFulcrumProcessFixture.isWorker)
)
struct MosaicFulcrumProcessWorkerValidator {
    @Test("Serves the exact local Fulcrum boundary")
    func serve() async throws {
        try await MosaicFulcrumProcessFixture.runWorker()
    }
}
#endif
