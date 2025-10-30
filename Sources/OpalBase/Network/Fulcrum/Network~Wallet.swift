// Network~Wallet.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func createAccount(
        for wallet: Wallet,
        at unhardenedIndex: UInt32,
        fulcrumServerURLs: [String] = .init()
    ) async throws -> Account {
        try await wallet.addAccount(unhardenedIndex: unhardenedIndex, fulcrumServerURLs: fulcrumServerURLs)
        let account = try await wallet.fetchAccount(at: unhardenedIndex)
        await ensureTelemetryInstalled(for: account)
        return account
    }
    
    public func resumeQueuedWork(for wallet: Wallet) async {
        let numberOfAccounts = await wallet.numberOfAccounts
        guard numberOfAccounts > 0 else { return }
        
        for index in 0..<numberOfAccounts {
            do {
                let account = try await wallet.fetchAccount(at: UInt32(index))
                await ensureTelemetryInstalled(for: account)
                await resumeQueuedWork(for: account)
            } catch {
                continue
            }
        }
    }
    
    public func resumeQueuedWork(for wallet: Wallet, accountIndex: UInt32) async throws {
        let account = try await wallet.fetchAccount(at: accountIndex)
        await ensureTelemetryInstalled(for: account)
        await resumeQueuedWork(for: account)
    }
    
    public func computeCachedBalance(for wallet: Wallet) async throws -> Satoshi {
        let balance = try await wallet.calculateBalance()
        let numberOfAccounts = await wallet.numberOfAccounts
        guard numberOfAccounts > 0 else { return balance }
        
        for index in 0..<numberOfAccounts {
            do {
                let account = try await wallet.fetchAccount(at: UInt32(index))
                await ensureTelemetryInstalled(for: account)
            } catch {
                continue
            }
        }
        
        return balance
    }
    
    public func computeBalance(
        for wallet: Wallet,
        priority: TaskPriority? = nil,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Satoshi {
        let numberOfAccounts = await wallet.numberOfAccounts
        guard numberOfAccounts > 0 else { return Satoshi() }
        
        var accounts: [Account] = .init()
        accounts.reserveCapacity(numberOfAccounts)
        for index in 0..<numberOfAccounts {
            let account = try await wallet.fetchAccount(at: UInt32(index))
            await ensureTelemetryInstalled(for: account)
            accounts.append(account)
        }
        
        return try await withThrowingTaskGroup(of: Satoshi.self) { group in
            for account in accounts {
                group.addTask {
                    try await self.computeBalance(for: account,
                                                  priority: priority,
                                                  options: options)
                }
            }
            
            var aggregate: UInt64 = 0
            for try await partial in group {
                let (updated, didOverflow) = aggregate.addingReportingOverflow(partial.uint64)
                if didOverflow || updated > Satoshi.maximumSatoshi {
                    throw Satoshi.Error.exceedsMaximumAmount
                }
                aggregate = updated
            }
            
            return try Satoshi(aggregate)
        }
    }
}
