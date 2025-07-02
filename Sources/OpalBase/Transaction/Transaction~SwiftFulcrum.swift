// Transaction~SwiftFulcrum.swift

import Foundation
import Combine
import SwiftFulcrum

extension Transaction.Detailed {
    init(from result: Response.Result.Blockchain.Transaction.Get) throws {
        //let transactionDetailsFromRPC = response
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
                  hash: hashFromResult,
                  raw: hexFromResult,
                  size: sizeFromResult,
                  time: timeFromResult)
    }
}

extension Transaction {
    func broadcast(using fulcrum: Fulcrum) async throws -> Data {
        let response = try await fulcrum.submit(method: .blockchain(.transaction(.broadcast(rawTransaction: self.encode().hexadecimalString))),
                                                responseType: Response.Result.Blockchain.Transaction.Broadcast.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let broadcasted = result
        
        return broadcasted.transactionHash
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
    static func fetchRawData(for transactionHash: Data, using fulcrum: Fulcrum) async throws -> Data {
        let response = try await fulcrum.submit(method: .blockchain(.transaction(.get(transactionHash: transactionHash.hexadecimalString, verbose: false))),
                                                responseType: Response.Result.Blockchain.Transaction.Get.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let rawHex = result.hex
        
        return try Data(hexString: rawHex)
    }
    
    public static func fetchTransaction(for transactionHash: Data, using fulcrum: Fulcrum) async throws -> Transaction {
        let response = try await fulcrum.submit(method: .blockchain(.transaction(.get(transactionHash: transactionHash.hexadecimalString, verbose: true))),
                                                responseType: Response.Result.Blockchain.Transaction.Get.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        return try Transaction.Detailed(from: result).transaction
    }
    
    public static func fetchFullTransaction(for transactionHash: Data, using fulcrum: Fulcrum) async throws -> Transaction.Detailed {
        let response = try await fulcrum.submit(method: .blockchain(.transaction(.get(transactionHash: transactionHash.hexadecimalString, verbose: false))),
                                                responseType: Response.Result.Blockchain.Transaction.Get.self)
        guard case .single(let id, let result) = response else { throw Fulcrum.Error.coding(.decode(nil))  }
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        return try Transaction.Detailed(from: result)
    }
}
