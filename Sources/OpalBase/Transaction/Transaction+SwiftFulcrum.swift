import Foundation
import SwiftFulcrum

extension Transaction {
    func broadcast(awaitSeconds: Double? = nil) async throws -> Bool {
        var fulcrum = try SwiftFulcrum()
        let rawTransaction = self.encode().hexadecimalString
        var success = Bool()
        
        await fulcrum.submitRequest(
            .blockchain(.transaction(.broadcast(rawTransaction))),
            resultType: Response.Result.Blockchain.Transaction.Broadcast.self
        ) { result in
            do {
                switch result {
                case .success(let broadcastResponse):
                    success = broadcastResponse.success
                case .failure(let error):
                    throw error
                }
            } catch {
                print(error.localizedDescription)
            }
        }
        
        if let awaitSeconds = awaitSeconds {
            try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * awaitSeconds))
        }
        
        return success
    }
    
    static func estimateFee(awaitSeconds: Double? = nil) async throws -> Satoshi {
        var fulcrum = try SwiftFulcrum()
        var satoshi = try Satoshi(0)
        
        await fulcrum.submitRequest(
            .blockchain(.estimateFee(6)),
            resultType: Response.Result.Blockchain.EstimateFee.self
        ) { result in
            do {
                switch result {
                case .success(let feeResponse):
                    satoshi = try Satoshi(bch: feeResponse.fee)
                case .failure(let error):
                    throw error
                }
            } catch {
                fatalError(error.localizedDescription)
            }
        }
        
        if let awaitSeconds = awaitSeconds {
            try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * awaitSeconds))
        }
        
        return satoshi
    }
}

extension Transaction {
    struct Past {
        let transaction: Transaction
        let blockHash: Data
        let blocktime: UInt32
        let confirmations: UInt
        let transactionHash: Data
        let locktime: UInt32
        let size: UInt32
        let time: UInt32
        let transactionID: Data
        let version: UInt32
        let inputs: [Input]
        let outputs: [Output]
    }
    
    static func fetchTransactionDetails(for transactionHash: Data) async throws -> Transaction.Past {
        var fulcrum = try SwiftFulcrum()
        var pastTransaction: Transaction.Past?
        
        await fulcrum.submitRequest(
            .blockchain(.transaction(.get(transactionHash.hexadecimalString, true))),
            resultType: Response.Result.Blockchain.Transaction.Get.self
        ) { result in
            do {
                switch result {
                case .success(let details):
                    let transaction = Transaction(version: .init(details.version),
                                                  inputs: details.inputs.map { Input(previousTransactionHash: Data(hex: $0.transactionID),
                                                                                     previousTransactionIndex: .init($0.indexNumberOfPreviousTransactionOutput),
                                                                                     unlockingScript: Data(hex: $0.scriptSig.hex),
                                                                                     sequence: .init($0.sequence)) },
                                                  outputs: details.outputs.map { Output(value: try! Satoshi(bch: $0.value).value,
                                                                                        lockingScript: .init(hex: $0.scriptPubKey.hex)) },
                                                  lockTime: .init(details.locktime))
                    
                    pastTransaction = Past(transaction: transaction,
                                           blockHash: Data(hex: details.blockHash),
                                           blocktime: .init(details.blocktime),
                                           confirmations: details.confirmations,
                                           transactionHash: Data(hex: details.transactionID),
                                           locktime: transaction.lockTime,
                                           size: .init(details.size),
                                           time: .init(details.time),
                                           transactionID: Data(hex: details.transactionID),
                                           version: transaction.version,
                                           inputs: transaction.inputs,
                                           outputs: transaction.outputs)
                    
                    
                case .failure(let error):
                    throw error
                }
            } catch {
                fatalError(error.localizedDescription)
            }
        }
        
        guard let transaction = pastTransaction else { throw Error.cannotCreateTransaction }
        
        return transaction
    }
}
