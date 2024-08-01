import Foundation
import BigInt
import SwiftFulcrum

extension Address {
    static func fetchBalance(for address: String, includeUnconfirmed: Bool = true, awaitSeconds: Double? = nil) async throws -> Satoshi {
        var fulcrum = try SwiftFulcrum()
        var balance: Satoshi = try Satoshi(0)
        
        print("Starting request to fetch balance from \(address)")
        
        await fulcrum.submitRequest(
            .blockchain(.address(.getBalance(address, nil))),
            resultType: Response.Result.Blockchain.Address.GetBalance.self
        ) { result in
            print("Request completed, processing result")
            do {
                switch result {
                case .success(let balanceResponse):
                    print("Balance response received: \(balanceResponse)")
                    let calculatedBalance = UInt64(BigInt(balanceResponse.confirmed) + (includeUnconfirmed ? BigInt(balanceResponse.unconfirmed) : 0))
                    balance = try Satoshi(calculatedBalance)
                    print("Calculated balance: \(balance)")
                case .failure(let error):
                    print("Error received: \(error.localizedDescription)")
                    throw error
                }
            } catch {
                print("Caught error: \(error.localizedDescription)")
            }
        }
        
        if let awaitSeconds = awaitSeconds {
            try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * awaitSeconds))
        }
        
        print("Returning balance: \(balance)")
        return balance
    }
    
    func fetchBalance(includeUnconfirmed: Bool = true) async throws -> Satoshi {
        var fulcrum = try SwiftFulcrum()
        var balance: Satoshi = try Satoshi(0)
        
        await fulcrum.submitRequest(
            .blockchain(.address(.getBalance(self.string, nil))),
            resultType: Response.Result.Blockchain.Address.GetBalance.self
        ) { result in
            do {
                switch result {
                case .success(let balanceResponse):
                    let calculatedBalance = UInt64(BigInt(balanceResponse.confirmed) + (includeUnconfirmed ? BigInt(balanceResponse.unconfirmed) : 0))
                    balance = try Satoshi(calculatedBalance)
                case .failure(let error):
                    throw error
                }
            } catch {
                fatalError(error.localizedDescription)
            }
        }
        
        return balance
    }
    
    func fetchTransactionHistory(awaitSeconds: Double? = nil) async throws -> [Data] {
        var fulcrum = try SwiftFulcrum()
        var transactionHashes = [Data]()
        
        await fulcrum.submitRequest(
            .blockchain(.address(.getHistory(self.string, 0, nil, true))),
            resultType: Response.Result.Blockchain.Address.GetHistory.self
        ) { result in
            do {
                switch result {
                case .success(let historyResponse):
                    for transaction in historyResponse.transactions {
                        let hash = Data(hex: transaction.transactionHash)
                        let _ = transaction.height
                        let _ = transaction.fee
                        
                        transactionHashes.append(hash)
                    }
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
        
        return transactionHashes
    }
    
    func subscribeToActivities() async throws {
        var fulcrum = try SwiftFulcrum()
        
        await fulcrum.submitSubscription(
            .blockchain(.address(.subscribe(self.string))),
            notificationType: Response.Result.Blockchain.Address.SubscribeNotification.self
        ) { result in
            do {
                switch result {
                case .success(let notification):
                    print(notification.subscriptionIdentifier)
                    if let status = notification.status {
                        print("New transaction status: \(status)")
                    }
                case .failure(let error):
                    throw error
                }
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
}
