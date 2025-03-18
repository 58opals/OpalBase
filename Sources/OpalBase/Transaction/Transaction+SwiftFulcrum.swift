import Foundation
import Combine
import SwiftFulcrum

extension Transaction.Detailed {
    init(from response: Response.JSONRPC.Result.Blockchain.Transaction.Get) throws {
        let transactionDetailsFromRPC = response
        
        let versionFromRPC = UInt32(transactionDetailsFromRPC.version)
        let inputsFromRPC = try transactionDetailsFromRPC.vin.map { input in
            let previousTransactionHashData = try Data(hexString: input.txid)
            let previousTransactionHash = Transaction.Hash(dataFromRPC: previousTransactionHashData)
            let previousTransactionOutputIndex = UInt32(input.vout)
            let unlockingScript = try Data(hexString: input.scriptSig.hex)
            let sequence = UInt32(input.sequence)
            
            return Transaction.Input(previousTransactionHash: previousTransactionHash,
                                     previousTransactionOutputIndex: previousTransactionOutputIndex,
                                     unlockingScript: unlockingScript,
                                     sequence: sequence)
        }
        let outputsFromRPC = try transactionDetailsFromRPC.vout.map { output in
            let value = UInt64((output.value * 100_000_000))
            let lockingScript = try Data(hexString: output.scriptPubKey.hex)
            
            return Transaction.Output(value: value,
                                      lockingScript: lockingScript)
        }
        let locktimeFromRPC = UInt32(transactionDetailsFromRPC.locktime)
        let transactionFromRPC = Transaction(version: versionFromRPC,
                                      inputs: inputsFromRPC,
                                      outputs: outputsFromRPC,
                                      lockTime: locktimeFromRPC)
        
        let blockHashFromRPC: Data? = {
            do {
                guard let string = transactionDetailsFromRPC.blockhash else { return nil }
                let data = try Data(hexString: string)
                return data
            } catch {
                return nil
            }
        }()
        
        let blockTimeFromRPC: UInt32? = {
            guard let uint = transactionDetailsFromRPC.blocktime else { return nil }
            let uint32 = UInt32(uint)
            return uint32
        }()
        
        let confirmationsFromRPC: UInt32? = {
            guard let uint = transactionDetailsFromRPC.confirmations else { return nil }
            let uint32 = UInt32(uint)
            return uint32
        }()
        
        let hashFromRPC = try Data(hexString: transactionDetailsFromRPC.hash)
        
        let hexFromRPC = try Data(hexString: transactionDetailsFromRPC.hex)
        
        let sizeFromRPC = UInt32(transactionDetailsFromRPC.size)
        
        let timeFromRPC: UInt32? = {
            guard let uint = transactionDetailsFromRPC.time else { return nil }
            let uint32 = UInt32(uint)
            return uint32
        }()
        
        self.init(transaction: transactionFromRPC,
                  blockHash: blockHashFromRPC,
                  blockTime: blockTimeFromRPC,
                  confirmations: confirmationsFromRPC,
                  hash: hashFromRPC,
                  raw: hexFromRPC,
                  size: sizeFromRPC,
                  time: timeFromRPC)
    }
}

extension Transaction {
    func broadcast(using fulcrum: Fulcrum) async throws -> Data {
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.transaction(.broadcast(rawTransaction: self.encode().hexadecimalString))),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Broadcast>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let broadcastedTransactionHash = result
        
        return broadcastedTransactionHash
    }
}

extension Transaction {
    static func estimateFee(numberOfBlocks: Int,
                            using fulcrum: Fulcrum) async throws -> Satoshi {
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.estimateFee(numberOfBlocks: numberOfBlocks)),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.EstimateFee>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let fee = result
        let satoshi = try Satoshi(bch: fee)
        
        return satoshi
    }
    
    static func relayFee(using fulcrum: Fulcrum) async throws -> Satoshi {
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.relayFee),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.RelayFee>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let fee = result
        let satoshi = try Satoshi(bch: fee)
        
        return satoshi
    }
}

extension Transaction {
    static func fetchRawData(for transactionHash: Data,
                             using fulcrum: Fulcrum) async throws -> Data {
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.transaction(.get(transactionHash: transactionHash.hexadecimalString, verbose: true))),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Get>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let rawTransaction = try Data(hexString: result.hex)
        
        return rawTransaction
    }
    
    public static func fetchTransaction(for transactionHash: Data,
                                        using fulcrum: Fulcrum) async throws -> Transaction {
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.transaction(.get(transactionHash: transactionHash.hexadecimalString, verbose: true))),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Get>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let transaction = Transaction(version: UInt32(result.version),
                                      inputs: try result.vin.map { Input(previousTransactionHash: .init(dataFromRPC: try Data(hexString: $0.txid)),
                                                                         previousTransactionOutputIndex: UInt32($0.vout),
                                                                         unlockingScript: try Data(hexString: $0.scriptSig.hex),
                                                                         sequence: UInt32($0.sequence)) },
                                      outputs: try result.vout.map { Output(value: try Satoshi(bch: $0.value).uint64,
                                                                            lockingScript: try Data(hexString: $0.scriptPubKey.hex)) },
                                      lockTime: UInt32(result.locktime))
        
        return transaction
    }
    
    public static func fetchFullTransaction(for transactionHash: Data,
                                            using fulcrum: Fulcrum) async throws -> Transaction.Detailed {
        let (id, result) = try await fulcrum.submit(
            method:
                Method
                .blockchain(.transaction(.get(transactionHash: transactionHash.hexadecimalString, verbose: true))),
            responseType:
                Response.JSONRPC.Generic<Response.JSONRPC.Result.Blockchain.Transaction.Get>.self
        )
        
        assert(UUID(uuidString: id.uuidString) != nil, "Invalid UUID: \(id.uuidString)")
        
        let isUnconfirmed = (result.blockhash == nil) && (result.blocktime == nil) && (result.confirmations == nil) && (result.time == nil)
        
        let transaction = Transaction(version: UInt32(result.version),
                                      inputs: try result.vin.map { Input(previousTransactionHash: .init(dataFromRPC: try Data(hexString: $0.txid)),
                                                                         previousTransactionOutputIndex: UInt32($0.vout),
                                                                         unlockingScript: try Data(hexString: $0.scriptSig.hex),
                                                                         sequence: UInt32($0.sequence)) },
                                      outputs: try result.vout.map { Output(value: try Satoshi(bch: $0.value).uint64,
                                                                            lockingScript: try Data(hexString: $0.scriptPubKey.hex)) },
                                      lockTime: UInt32(result.locktime))
        
        let detailedTransaction = Transaction.Detailed(transaction: transaction,
                                                       blockHash: isUnconfirmed ? nil : try Data(hexString: result.blockhash!),
                                                       blockTime: isUnconfirmed ? nil : UInt32(result.blocktime!),
                                                       confirmations: isUnconfirmed ? nil : UInt32(result.confirmations!),
                                                       hash: try Data(hexString: result.hash),
                                                       raw: try Data(hexString: result.hex),
                                                       size: UInt32(result.size),
                                                       time: isUnconfirmed ? nil : UInt32(result.time!))
        
        return detailedTransaction
    }
}
