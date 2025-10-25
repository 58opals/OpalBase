// Transaction~SwiftFulcrum.swift

import Foundation

extension Transaction {
    public func broadcast(using service: Network.FulcrumService) async throws -> Transaction.Hash {
            try await service.broadcast(self)
    }
}

extension Transaction {
    public static func getEstimateFee(numberOfBlocks: Int, using service: Network.FulcrumService) async throws -> Satoshi {
            try await service.getEstimateFee(targetBlocks: numberOfBlocks)
    }
    
    public static func getRelayFee(using service: Network.FulcrumService) async throws -> Satoshi {
            try await service.getRelayFee()
    }
}

extension Transaction {
    public static func fetchRawData(for transactionHash: Transaction.Hash, using service: Network.FulcrumService) async throws -> Data {
            try await service.getRawTransaction(for: transactionHash)
    }
    
    public static func fetchTransaction(for transactionHash: Transaction.Hash, using service: Network.FulcrumService) async throws -> Transaction {
            guard let transaction = try await service.getTransaction(for: transactionHash) else {
            throw Transaction.Error.transactionNotFound
        }
        return transaction
    }
    
    public static func fetchFullTransaction(for transactionHash: Transaction.Hash, using service: Network.FulcrumService) async throws -> Transaction.Detailed {
        let cacheKey = transactionHash
        if let cached = await Cache.shared.get(at: cacheKey) { return cached }
        let detailed = try await service.getDetailedTransaction(for: transactionHash)
        await Cache.shared.put(detailed, at: cacheKey)
        return detailed
    }
    
    public static func fetchFullTransactionsBatched(for hashes: [Transaction.Hash], using service: Network.FulcrumService) async throws -> [Data: Transaction.Detailed] {
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
                        let detailed = try await fetchFullTransaction(for: hash, using: service)
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
