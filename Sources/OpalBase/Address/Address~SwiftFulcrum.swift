// Address~SwiftFulcrum.swift

import Foundation
import BigInt
import SwiftFulcrum

extension Address {
    func fetchBalance(includeUnconfirmed: Bool = true, using service: Network.FulcrumService) async throws -> Satoshi {
        try await service.balance(for: self, includeUnconfirmed: includeUnconfirmed)
    }
    
    func fetchUnspentTransactionOutputs(using service: Network.FulcrumService) async throws -> [Transaction.Output.Unspent] {
        try await service.unspentOutputs(for: self)
    }
    
    func fetchSimpleTransactionHistory(fromHeight: UInt? = nil,
                                       toHeight: UInt? = nil,
                                       includeUnconfirmed: Bool = true,
                                       using service: Network.FulcrumService) async throws -> [Transaction.Simple] {
        try await service.simpleHistory(for: self,
                                        fromHeight: fromHeight,
                                        toHeight: toHeight,
                                        includeUnconfirmed: includeUnconfirmed)
    }
    
    func fetchSimpleTransactionHistoryPage(fromHeight: UInt? = nil,
                                           window: UInt,
                                           includeUnconfirmed: Bool = true,
                                           using service: Network.FulcrumService) async throws -> Address.Book.Page<Transaction.Simple> {
        let startHeight = fromHeight ?? 0
        let endHeight = window == 0 ? nil : ((startHeight &+ window) &- 1)
        let transactions = try await fetchSimpleTransactionHistory(fromHeight: startHeight,
                                                                   toHeight: endHeight,
                                                                   includeUnconfirmed: includeUnconfirmed,
                                                                   using: service)
        let nextHeight = endHeight.map { $0 &+ 1 }
        
        return .init(transactions: transactions, nextFromHeight: nextHeight)
    }
    
    func fetchFullTransactionHistory(fromHeight: UInt? = nil,
                                     toHeight: UInt? = nil,
                                     includeUnconfirmed: Bool = true,
                                     using service: Network.FulcrumService) async throws -> [Transaction.Detailed] {
        try await service.detailedHistory(for: self,
                                          fromHeight: fromHeight,
                                          toHeight: toHeight,
                                          includeUnconfirmed: includeUnconfirmed)
    }
    
    func fetchFullTransactionHistoryPage(fromHeight: UInt? = nil,
                                         window: UInt,
                                         includeUnconfirmed: Bool = true,
                                         using service: Network.FulcrumService) async throws -> Address.Book.Page<Transaction.Detailed> {
        let startHeight = fromHeight ?? 0
        let endHeight = window == 0 ? nil : ((startHeight &+ window) &- 1)
        let transactions = try await fetchFullTransactionHistory(fromHeight: startHeight,
                                                                 toHeight: endHeight,
                                                                 includeUnconfirmed: includeUnconfirmed,
                                                                 using: service)
        let nextHeight = endHeight.map { $0 &+ 1 }
        
        return .init(transactions: transactions, nextFromHeight: nextHeight)
    }
    
    func subscribe(using service: Network.FulcrumService) async throws -> Network.Wallet.SubscriptionStream {
        try await service.subscribe(to: self)
    }
}

//extension Transaction.Detailed {
//    init(from result: Response.Result.Blockchain.Transaction.Get) throws {
//        let transactionDetails = result
//        
//        let versionFromResult = UInt32(transactionDetails.version)
//        let inputsFromResult = try transactionDetails.inputs.map { input in
//            let previousTransactionHashData = try Data(hexString: input.transactionID)
//            let previousTransactionHash = Transaction.Hash(dataFromRPC: previousTransactionHashData)
//            let previousTransactionOutputIndex = UInt32(input.indexNumberOfPreviousTransactionOutput)
//            let unlockingScript = try Data(hexString: input.scriptSig.hex)
//            let sequence = UInt32(input.sequence)
//            
//            return Transaction.Input(previousTransactionHash: previousTransactionHash,
//                                     previousTransactionOutputIndex: previousTransactionOutputIndex,
//                                     unlockingScript: unlockingScript,
//                                     sequence: sequence)
//        }
//        let outputsFromResult = try transactionDetails.outputs.map { output in
//            let value = try Satoshi(bch: output.value).uint64
//            let lockingScript = try Data(hexString: output.scriptPubKey.hex)
//            
//            return Transaction.Output(value: value,
//                                      lockingScript: lockingScript)
//        }
//        let locktimeFromResult = UInt32(transactionDetails.locktime)
//        let transactionFromResult = Transaction(version: versionFromResult,
//                                                inputs: inputsFromResult,
//                                                outputs: outputsFromResult,
//                                                lockTime: locktimeFromResult)
//        let blockHashFromResult: Data? = {
//            do {
//                let data = try Data(hexString: transactionDetails.blockHash)
//                return data
//            } catch {
//                return nil
//            }
//        }()
//        let blockTimeFromResult = UInt32(transactionDetails.blocktime)
//        let confirmationsFromResult = UInt32(transactionDetails.confirmations)
//        let hashFromResult = try Data(hexString: transactionDetails.hash)
//        let hexFromResult = try Data(hexString: transactionDetails.hex)
//        let sizeFromResult = UInt32(transactionDetails.size)
//        let timeFromResult = UInt32(transactionDetails.time)
//        
//        self.init(transaction: transactionFromResult,
//                  blockHash: blockHashFromResult,
//                  blockTime: blockTimeFromResult,
//                  confirmations: confirmationsFromResult,
//                  hash: .init(dataFromRPC: hashFromResult),
//                  raw: hexFromResult,
//                  size: sizeFromResult,
//                  time: timeFromResult)
//    }
//}
