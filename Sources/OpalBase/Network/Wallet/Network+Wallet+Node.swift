// Network+Wallet+Node.swift

import Foundation
import SwiftFulcrum

extension Network.Wallet {
    public struct Node: Sendable {
        private let fulcrum: SwiftFulcrum.Fulcrum
        
        public init(fulcrum: SwiftFulcrum.Fulcrum) {
            self.fulcrum = fulcrum
        }
        
        public func balance(for address: Address, includeUnconfirmed: Bool) async throws -> Satoshi {
            do {
                let response = try await fulcrum.submit(
                    method: .blockchain(.address(.getBalance(address: address.string, tokenFilter: nil))),
                    responseType: Response.Result.Blockchain.Address.GetBalance.self
                )
                guard case .single(_, let result) = response else {
                    throw Network.Wallet.NodeError(reason: .coding(description: "Unexpected response"))
                }
                
                let delta = includeUnconfirmed ? result.unconfirmed : 0
                let balance: UInt64
                if delta >= 0 {
                    balance = result.confirmed &+ UInt64(delta)
                } else {
                    let decrease = UInt64(-delta)
                    balance = result.confirmed > decrease ? (result.confirmed - decrease) : 0
                }
                return try Satoshi(balance)
            } catch {
                throw map(error)
            }
        }
        
        public func unspentOutputs(for address: Address) async throws -> [Transaction.Output.Unspent] {
            do {
                let scriptHash = SHA256.hash(address.lockingScript.data).reversedData
                let response = try await fulcrum.submit(
                    method: .blockchain(
                        .scripthash(
                            .listUnspent(scripthash: scriptHash.hexadecimalString, tokenFilter: nil)
                        )
                    ),
                    responseType: Response.Result.Blockchain.ScriptHash.ListUnspent.self
                )
                
                if case .single(_, let result) = response {
                    return try result.items.map { item in
                        let transactionHash = Transaction.Hash(dataFromRPC: try Data(hexString: item.transactionHash))
                        let outputIndex = UInt32(item.transactionPosition)
                        return Transaction.Output.Unspent(
                            value: item.value,
                            lockingScript: address.lockingScript.data,
                            previousTransactionHash: transactionHash,
                            previousTransactionOutputIndex: outputIndex
                        )
                    }
                }
            } catch let error as Fulcrum.Error {
                // fall back to address based lookup for compatibility
                switch error {
                case .rpc, .transport, .client:
                    return try await unspentOutputsViaAddress(for: address)
                case .coding:
                    throw map(error)
                }
            } catch {
                throw map(error)
            }
            
            return try await unspentOutputsViaAddress(for: address)
        }
        
        public func simpleHistory(for address: Address,
                                  fromHeight: UInt?,
                                  toHeight: UInt?,
                                  includeUnconfirmed: Bool) async throws -> [Transaction.Simple]
        {
            do {
                let response = try await fulcrum.submit(
                    method: .blockchain(
                        .address(
                            .getHistory(address: address.string,
                                        fromHeight: fromHeight,
                                        toHeight: toHeight,
                                        includeUnconfirmed: includeUnconfirmed)
                        )
                    ),
                    responseType: Response.Result.Blockchain.Address.GetHistory.self
                )
                guard case .single(_, let result) = response else {
                    throw Network.Wallet.NodeError(reason: .coding(description: "Unexpected response"))
                }
                
                return try result.transactions.map { historyItem in
                    Transaction.Simple(
                        transactionHash: .init(dataFromRPC: try Data(hexString: historyItem.transactionHash)),
                        height: historyItem.height > 0 ? UInt32(historyItem.height) : nil,
                        fee: historyItem.fee.map { UInt64($0) }
                    )
                }
            } catch {
                throw map(error)
            }
        }
        
        public func detailedHistory(for address: Address,
                                    fromHeight: UInt?,
                                    toHeight: UInt?,
                                    includeUnconfirmed: Bool) async throws -> [Transaction.Detailed]
        {
            let simple = try await simpleHistory(for: address,
                                                 fromHeight: fromHeight,
                                                 toHeight: toHeight,
                                                 includeUnconfirmed: includeUnconfirmed)
            if simple.isEmpty { return [] }
            
            return try await withThrowingTaskGroup(of: Transaction.Detailed.self) { group in
                for transaction in simple {
                    group.addTask {
                        let response = try await fulcrum.submit(
                            method: .blockchain(
                                .transaction(
                                    .get(
                                        transactionHash: transaction.transactionHash.externallyUsedFormat.hexadecimalString,
                                        verbose: true
                                    )
                                )
                            ),
                            responseType: Response.Result.Blockchain.Transaction.Get.self
                        )
                        guard case .single(_, let result) = response else {
                            throw Network.Wallet.NodeError(reason: .coding(description: "Unexpected response"))
                        }
                        return try Transaction.Detailed(from: result)
                    }
                }
                
                var detailed: [Transaction.Detailed] = .init()
                detailed.reserveCapacity(simple.count)
                for try await transaction in group { detailed.append(transaction) }
                return detailed
            }
        }
        
        public func subscribe(to address: Address) async throws -> Network.Wallet.SubscriptionStream {
            do {
                let response: Fulcrum.RPCResponse<
                    Response.Result.Blockchain.Address.Subscribe,
                    Response.Result.Blockchain.Address.SubscribeNotification
                > = try await fulcrum.submit(method: .blockchain(.address(.subscribe(address: address.string))))
                
                guard case .stream(let id, let initial, let updates, let cancel) = response else {
                    throw Network.Wallet.NodeError(reason: .coding(description: "Unexpected response"))
                }
                
                let mapped = AsyncThrowingStream<Network.Wallet.SubscriptionStream.Notification, Swift.Error> { continuation in
                    let task = Task {
                        do {
                            for try await notification in updates {
                                continuation.yield(.init(status: notification.status))
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: map(error))
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
                
                return .init(id: id,
                             initialStatus: initial.status ?? "",
                             updates: mapped,
                             cancel: {
                    await cancel()
                })
            } catch {
                throw map(error)
            }
        }
        
        private func unspentOutputsViaAddress(for address: Address) async throws -> [Transaction.Output.Unspent] {
            do {
                let response = try await fulcrum.submit(
                    method: .blockchain(
                        .address(
                            .listUnspent(address: address.string, tokenFilter: nil)
                        )
                    ),
                    responseType: Response.Result.Blockchain.Address.ListUnspent.self
                )
                guard case .single(_, let result) = response else {
                    throw Network.Wallet.NodeError(reason: .coding(description: "Unexpected response"))
                }
                
                var outputs: [Transaction.Output.Unspent] = .init()
                var needsScriptResolution: [(hash: Transaction.Hash, index: UInt32, value: UInt64)] = .init()
                
                for item in result.items {
                    let hashData = try Data(hexString: item.transactionHash)
                    let transactionHash = Transaction.Hash(dataFromRPC: hashData)
                    let outputIndex = UInt32(item.transactionPosition)
                    
                    if address.lockingScript.isDerivableFromAddress {
                        outputs.append(
                            .init(
                                value: item.value,
                                lockingScript: address.lockingScript.data,
                                previousTransactionHash: transactionHash,
                                previousTransactionOutputIndex: outputIndex
                            )
                        )
                    } else {
                        needsScriptResolution.append((transactionHash, outputIndex, item.value))
                    }
                }
                
                if !needsScriptResolution.isEmpty {
                    let gateway = Network.Gateway(client: Adapter.SwiftFulcrum.GatewayClient(fulcrum: fulcrum))
                    await gateway.updateHealth(status: .online, lastHeaderAt: Date())
                    let fetched = try await Transaction.fetchFullTransactionsBatched(
                        for: needsScriptResolution.map(\.hash),
                        using: gateway
                    )
                    for pending in needsScriptResolution {
                        if let detailed = fetched[pending.hash.originalData],
                           Int(pending.index) < detailed.transaction.outputs.count {
                            let script = detailed.transaction.outputs[Int(pending.index)].lockingScript
                            outputs.append(
                                .init(
                                    value: pending.value,
                                    lockingScript: script,
                                    previousTransactionHash: pending.hash,
                                    previousTransactionOutputIndex: pending.index
                                )
                            )
                        }
                    }
                }
                
                return outputs
            } catch {
                throw map(error)
            }
        }
        
        private func map(_ error: Swift.Error) -> Swift.Error {
            if let nodeError = error as? Network.Wallet.NodeError { return nodeError }
            guard let fulcrumError = error as? Fulcrum.Error else { return error }
            switch fulcrumError {
            case .rpc(let server):
                return Network.Wallet.NodeError(reason: .rejected(code: server.code, message: server.message))
            case .transport(let transport):
                return Network.Wallet.NodeError(reason: .transport(description: describe(transport)))
            case .client(let client):
                return Network.Wallet.NodeError(reason: .transport(description: describe(client)))
            case .coding(let coding):
                return Network.Wallet.NodeError(reason: .coding(description: describe(coding)))
            }
        }
        
        private func describe(_ transport: Fulcrum.Error.Transport) -> String {
            switch transport {
            case .setupFailed:
                return "Transport setup failed"
            case .connectionClosed(let code, let reason):
                if let reason, !reason.isEmpty { return "Connection closed (\(code.rawValue)): \(reason)" }
                return "Connection closed (\(code.rawValue))"
            case .network(let networkError):
                switch networkError {
                case .tlsNegotiationFailed(let underlying):
                    return "TLS negotiation failed: \(String(describing: underlying))"
                }
            case .reconnectFailed:
                return "Reconnect failed"
            case .heartbeatTimeout:
                return "Heartbeat timeout"
            }
        }
        
        private func describe(_ client: Fulcrum.Error.Client) -> String {
            switch client {
            case .urlNotFound:
                return "URL not found"
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            case .duplicateHandler:
                return "Duplicate handler detected"
            case .cancelled:
                return "Request cancelled"
            case .timeout(let duration):
                let seconds = seconds(from: duration)
                return "Request timed out after \(seconds) seconds"
            case .emptyResponse(let identifier):
                if let identifier { return "Empty response for request \(identifier.uuidString)" }
                return "Empty response from server"
            case .protocolMismatch(let message):
                let detail = message ?? "unknown mismatch"
                return "Protocol mismatch: \(detail)"
            case .unknown(let underlying):
                return "Unknown client error: \(String(describing: underlying))"
            }
        }
        
        private func describe(_ coding: Fulcrum.Error.Coding) -> String {
            switch coding {
            case .encode(let underlying):
                return "Encoding failure: \(String(describing: underlying))"
            case .decode(let underlying):
                return "Decoding failure: \(String(describing: underlying))"
            }
        }
        
        private func seconds(from duration: Duration) -> Double {
            let components = duration.components
            let fractional = Double(components.attoseconds) / 1_000_000_000_000_000_000
            return Double(components.seconds) + fractional
        }
    }
}

extension Network.Wallet {
    public struct SubscriptionStream: Sendable {
        public struct Notification: Sendable, Equatable {
            public let status: String?
            
            public init(status: String?) {
                self.status = status
            }
        }
        
        public let id: UUID
        public let initialStatus: String
        public let updates: AsyncThrowingStream<Notification, Swift.Error>
        public let cancel: @Sendable () async -> Void
        
        public init(id: UUID,
                    initialStatus: String,
                    updates: AsyncThrowingStream<Notification, Swift.Error>,
                    cancel: @escaping @Sendable () async -> Void) {
            self.id = id
            self.initialStatus = initialStatus
            self.updates = updates
            self.cancel = cancel
        }
    }
}

extension Network.Wallet {
    public struct NodeError: Swift.Error, Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            case rejected(code: Int?, message: String)
            case transport(description: String)
            case coding(description: String)
            case unknown(description: String)
        }
        
        public let reason: Reason
        
        public init(reason: Reason) {
            self.reason = reason
        }
    }
}
