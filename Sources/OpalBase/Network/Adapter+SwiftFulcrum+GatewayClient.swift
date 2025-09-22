// Adapter+SwiftFulcrum+GatewayClient.swift

import Foundation
import SwiftFulcrum

extension Adapter.SwiftFulcrum {
    public struct GatewayClient: Network.Gateway.Client {
        private let fulcrum: SwiftFulcrum.Fulcrum
        
        public init(fulcrum: SwiftFulcrum.Fulcrum) {
            self.fulcrum = fulcrum
        }
        
        public var currentMempool: Set<Transaction.Hash> = .init()
        
        public func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash {
            let response = try await fulcrum.submit(
                method: .blockchain(.transaction(.broadcast(rawTransaction: transaction.encode().hexadecimalString))),
                responseType: Response.Result.Blockchain.Transaction.Broadcast.self
            )
            guard case .single(_, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
            return .init(dataFromRPC: result.transactionHash)
        }
        
        public func fetch(_ hash: Transaction.Hash) async throws -> Transaction? {
            do {
                let detailed = try await getDetailedTransaction(for: hash)
                return detailed.transaction
            } catch {
                return nil
            }
        }
        
        public func getRawTransaction(for hash: Transaction.Hash) async throws -> Data {
            let response = try await fulcrum.submit(
                method: .blockchain(.transaction(.get(transactionHash: hash.externallyUsedFormat.hexadecimalString, verbose: true))),
                responseType: Response.Result.Blockchain.Transaction.Get.self
            )
            guard case .single(_, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
            
            return try Data(hexString: result.hex)
        }
        
        public func getDetailedTransaction(for hash: Transaction.Hash) async throws -> Transaction.Detailed {
            let response = try await fulcrum.submit(
                method: .blockchain(.transaction(.get(transactionHash: hash.externallyUsedFormat.hexadecimalString, verbose: true))),
                responseType: Response.Result.Blockchain.Transaction.Get.self
            )
            guard case .single(_, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
            
            return try .init(from: result)
        }
        
        public func getEstimateFee(targetBlocks: Int) async throws -> Satoshi {
            let response = try await fulcrum.submit(
                method: .blockchain(.estimateFee(numberOfBlocks: targetBlocks)),
                responseType: Response.Result.Blockchain.EstimateFee.self
            )
            guard case .single(_, let result) = response else {
                throw Fulcrum.Error.coding(.decode(nil))
            }
            return try Satoshi(bch: result.fee)
        }
        
        public func getRelayFee() async throws -> Satoshi {
            let response = try await fulcrum.submit(
                method: .blockchain(.relayFee),
                responseType: Response.Result.Blockchain.RelayFee.self
            )
            guard case .single(_, let result) = response else {
                throw Fulcrum.Error.coding(.decode(nil))
            }
            return try Satoshi(bch: result.fee)
        }
        
        public func getHeader(height: UInt32) async throws -> Network.Gateway.HeaderPayload? {
            let response = try await fulcrum.submit(
                method: .blockchain(.block(.header(height: .init(height), checkpointHeight: nil))),
                responseType: Response.Result.Blockchain.Block.Header.self
            )
            guard case .single(let identifier, let result) = response else {
                return nil
            }
            let payload = try Data(hexString: result.hex)
            return .init(identifier: identifier, raw: payload)
        }
        
        public func pingHeadersTip() async throws {
            _ = try await fulcrum.submit(
                method: .blockchain(.headers(.getTip)),
                responseType: Response.Result.Blockchain.Headers.GetTip.self
            )
        }
        
        public func interpretBroadcastError(
            _ error: Swift.Error,
            expectedHash: Transaction.Hash
        ) -> Network.Gateway.BroadcastResolution? {
            guard let fulcrumError = error as? Fulcrum.Error else { return nil }
            switch fulcrumError {
            case .rpc(let server):
                if isDuplicate(server: server) {
                    return .alreadyKnown(expectedHash)
                }
                return retry(.rejected(code: server.code, message: server.message), hint: .never)
            case .transport(let transport):
                let description = describeTransport(transport)
                let delay = transportRetryDelay(for: transport)
                return retry(.transport(description: description), hint: .after(delay))
            case .client(let clientError):
                return interpret(clientError, expectedHash: expectedHash)
            case .coding(let codingError):
                let description = describeCoding(codingError)
                return retry(.transport(description: description), hint: .after(5))
            }
        }
        
        private func retry(
            _ reason: Network.Gateway.Error.Reason,
            hint: Network.Gateway.Error.RetryHint
        ) -> Network.Gateway.BroadcastResolution {
            .retry(.init(reason: reason, retry: hint))
        }
        
        private func isDuplicate(server: Fulcrum.Error.Server) -> Bool {
            if server.code == -27 { return true }
            let lowered = server.message.lowercased()
            let duplicatePhrases = [
                "already have transaction",
                "already known",
                "already in block chain",
                "txn-already-known",
                "txn-already-in-mempool"
            ]
            return duplicatePhrases.contains { lowered.contains($0) }
        }
        
        private func transportRetryDelay(for transport: Fulcrum.Error.Transport) -> TimeInterval {
            switch transport {
            case .setupFailed:
                return 5
            case .connectionClosed:
                return 3
            case .network:
                return 5
            case .reconnectFailed:
                return 8
            case .heartbeatTimeout:
                return 10
            }
        }
        
        private func describeTransport(_ transport: Fulcrum.Error.Transport) -> String {
            switch transport {
            case .setupFailed:
                return "Transport setup failed"
            case .connectionClosed(let code, let reason):
                if let reason, !reason.isEmpty {
                    return "Connection closed (\(code.rawValue)): \(reason)"
                }
                return "Connection closed (\(code.rawValue))"
            case .network(let networkError):
                switch networkError {
                case .tlsNegotiationFailed(let underlying):
                    return "TLS negotiation failed: \(detail(from: underlying))"
                }
            case .reconnectFailed:
                return "Reconnect failed"
            case .heartbeatTimeout:
                return "Heartbeat timeout"
            }
        }
        
        private func interpret(
            _ error: Fulcrum.Error.Client,
            expectedHash _: Transaction.Hash
        ) -> Network.Gateway.BroadcastResolution {
            switch error {
            case .duplicateHandler:
                return retry(.transport(description: "Duplicate handler detected"), hint: .immediately)
            case .cancelled:
                return retry(.transport(description: "Request cancelled"), hint: .after(1))
            case .timeout(let duration):
                let seconds = max(1, seconds(from: duration))
                let description = String(format: "Request timed out after %.2f seconds", seconds)
                return retry(.transport(description: description), hint: .after(seconds))
            case .emptyResponse(let identifier):
                if let identifier {
                    return retry(.transport(description: "Empty response for request \(identifier.uuidString)"), hint: .after(1))
                }
                return retry(.transport(description: "Empty response from server"), hint: .after(1))
            case .protocolMismatch(let message):
                let detail = message ?? "unknown mismatch"
                return retry(.transport(description: "Protocol mismatch: \(detail)"), hint: .after(5))
            case .unknown(let underlying):
                let description = "Unknown client error: \(detail(from: underlying))"
                return retry(.transport(description: description), hint: .after(5))
            }
        }
        
        private func describeCoding(_ error: Fulcrum.Error.Coding) -> String {
            switch error {
            case .encode(let underlying):
                return "Encoding failure: \(detail(from: underlying))"
            case .decode(let underlying):
                return "Decoding failure: \(detail(from: underlying))"
            }
        }
        
        private func seconds(from duration: Duration) -> TimeInterval {
            let components = duration.components
            let fractional = Double(components.attoseconds) / 1_000_000_000_000_000_000
            return Double(components.seconds) + fractional
        }
        
        private func detail(from error: Swift.Error?) -> String {
            if let error { return String(describing: error) }
            return "unknown"
        }
    }
}

extension Adapter.SwiftFulcrum.GatewayClient: Sendable {}
