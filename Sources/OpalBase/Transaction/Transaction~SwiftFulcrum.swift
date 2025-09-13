// Transaction~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Transaction.Detailed {
    init(from result: Response.Result.Blockchain.Transaction.Get) throws {
        let transactionDetails = result
        
        let versionFromResult = UInt32(transactionDetails.version)
        let inputsFromResult = try transactionDetails.inputs.map { input in
            let previousTransactionHashData = try Data(hexString: input.transactionID)
            let previousTransactionHash = Transaction.Hash(dataFromRPC: previousTransactionHashData)
            let previousTransactionOutputIndex = UInt32(input.indexNumberOfPreviousTransactionOutput)
            let unlockingScript = try Data(hexString: input.scriptSig.hex)
            let sequence = UInt32(input.sequence)
            
            return Transaction.Input(previousTransactionHash: previousTransactionHash,
                                     previousTransactionOutputIndex: previousTransactionOutputIndex,
                                     unlockingScript: unlockingScript,
                                     sequence: sequence)
        }
        let outputsFromResult = try transactionDetails.outputs.map { output in
            let value = try Satoshi(bch: output.value).uint64
            let lockingScript = try Data(hexString: output.scriptPubKey.hex)
            
            return Transaction.Output(value: value,
                                      lockingScript: lockingScript)
        }
        let locktimeFromResult = UInt32(transactionDetails.locktime)
        let transactionFromResult = Transaction(version: versionFromResult,
                                                inputs: inputsFromResult,
                                                outputs: outputsFromResult,
                                                lockTime: locktimeFromResult)
        let blockHashFromResult: Data? = {
            do {
                let data = try Data(hexString: transactionDetails.blockHash)
                return data
            } catch {
                return nil
            }
        }()
        let blockTimeFromResult = UInt32(transactionDetails.blocktime)
        let confirmationsFromResult = UInt32(transactionDetails.confirmations)
        let hashFromResult = try Data(hexString: transactionDetails.hash)
        let hexFromResult = try Data(hexString: transactionDetails.hex)
        let sizeFromResult = UInt32(transactionDetails.size)
        let timeFromResult = UInt32(transactionDetails.time)
        
        self.init(transaction: transactionFromResult,
                  blockHash: blockHashFromResult,
                  blockTime: blockTimeFromResult,
                  confirmations: confirmationsFromResult,
                  hash: .init(dataFromRPC: hashFromResult),
                  raw: hexFromResult,
                  size: sizeFromResult,
                  time: timeFromResult)
    }
}

extension Transaction {
    func broadcast(using fulcrum: Fulcrum) async throws -> Transaction.Hash {
        let response = try await fulcrum.submit(method: .blockchain(.transaction(.broadcast(rawTransaction: self.encode().hexadecimalString))),
                                                responseType: Response.Result.Blockchain.Transaction.Broadcast.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let broadcasted = result
        
        return .init(dataFromRPC: broadcasted.transactionHash)
    }
}

extension Transaction {
    static func estimateFee(numberOfBlocks: Int, using fulcrum: Fulcrum) async throws -> Satoshi {
        let response = try await fulcrum.submit(method: .blockchain(.estimateFee(numberOfBlocks: numberOfBlocks)),
                                                responseType: Response.Result.Blockchain.EstimateFee.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let satoshi = try Satoshi(bch: result.fee)
        
        return satoshi
    }
    
    static func relayFee(using fulcrum: Fulcrum) async throws -> Satoshi {
        let response = try await fulcrum.submit(method: .blockchain(.relayFee),
                                                responseType: Response.Result.Blockchain.RelayFee.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let satoshi = try Satoshi(bch: result.fee)
        
        return satoshi
    }
}

extension Transaction {
    static func fetchRawData(for transactionHash: Transaction.Hash, using fulcrum: Fulcrum) async throws -> Data {
        let response = try await fulcrum.submit(method: .blockchain(.transaction(.get(transactionHash: transactionHash.externallyUsedFormat.hexadecimalString, verbose: true))),
                                                responseType: Response.Result.Blockchain.Transaction.Get.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let rawHex = result.hex
        
        return try Data(hexString: rawHex)
    }
    
    static func fetchTransaction(for transactionHash: Transaction.Hash, using fulcrum: Fulcrum) async throws -> Transaction {
        let response = try await fulcrum.submit(
            method: .blockchain(.transaction(.get(transactionHash: transactionHash.externallyUsedFormat.hexadecimalString, verbose: true))),
            responseType: Response.Result.Blockchain.Transaction.Get.self
        )
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        return try Transaction.Detailed(from: result).transaction
    }
    
    static func fetchFullTransaction(for transactionHash: Transaction.Hash, using fulcrum: Fulcrum) async throws -> Transaction.Detailed {
        let cacheKey = transactionHash
        if let cached = await Cache.shared.get(at: cacheKey) { return cached }
        let response = try await fulcrum.submit(
            method: .blockchain(.transaction(.get(transactionHash: transactionHash.externallyUsedFormat.hexadecimalString, verbose: true))),
            responseType: Response.Result.Blockchain.Transaction.Get.self
        )
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil)) }
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        let detailed = try Transaction.Detailed(from: result)
        await Cache.shared.put(detailed, at: cacheKey)
        return detailed
    }
    
    static func fetchFullTransactionsBatched(for hashes: [Transaction.Hash], using fulcrum: Fulcrum) async throws -> [Data: Transaction.Detailed] {
        var result: [Data: Transaction.Detailed] = .init()
        var hashesToFetch: [Transaction.Hash] = .init()
        var hashesAlreadySeen: Set<Transaction.Hash> = .init()
        
        for hash in hashes where hashesAlreadySeen.insert(hash).inserted {
            if let cached = await Cache.shared.get(at: hash) {
                result[hash.naturalOrder] = cached
            } else {
                hashesToFetch.append(hash)
            }
        }
        
        if !hashesToFetch.isEmpty {
            try await withThrowingTaskGroup(of: (Transaction.Hash, Transaction.Detailed).self) { group in
                for hash in hashesToFetch {
                    group.addTask {
                        let detailed = try await fetchFullTransaction(for: hash, using: fulcrum)
                        return (hash, detailed)
                    }
                }
                
                for try await (hash, detailed) in group {
                    result[hash.naturalOrder] = detailed
                    await Cache.shared.put(detailed, at: hash)
                }
            }
        }
        
        return result
    }
}
