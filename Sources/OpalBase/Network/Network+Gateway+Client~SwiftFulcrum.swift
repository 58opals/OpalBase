// Network+Gateway+Client~SwiftFulcrum.swift

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
    }
}

extension Adapter.SwiftFulcrum.GatewayClient: Sendable {}
