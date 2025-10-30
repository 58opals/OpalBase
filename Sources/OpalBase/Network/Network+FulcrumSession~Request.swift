// Network+FulcrumSession~Request.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func submit<RegularResponseResult: JSONRPCConvertible>(
        method: SwiftFulcrum.Method,
        responseType: RegularResponseResult.Type = RegularResponseResult.self,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Fulcrum.RPCResponse<RegularResponseResult, Never> {
        try ensureSessionReady()
        guard let fulcrum else { throw Error.sessionNotStarted }
        
        return try await fulcrum.submit(method: method,
                                        responseType: responseType,
                                        options: options)
    }
    
    public func submit<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        method: SwiftFulcrum.Method,
        initialType: Initial.Type = Initial.self,
        notificationType: Notification.Type = Notification.self,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Fulcrum.RPCResponse<Initial, Notification> {
        try ensureSessionReady()
        guard let fulcrum else { throw Error.sessionNotStarted }
        
        return try await fulcrum.submit(method: method,
                                        initialType: initialType,
                                        notificationType: notificationType,
                                        options: options)
    }
}

extension Network.FulcrumSession {
    public func fetchHeaderTip(
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip {
        let response = try await submit(
            method: .blockchain(.headers(.getTip)),
            responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self,
            options: options
        )
        
        guard case .single(_, let tip) = response else {
            throw Error.unexpectedResponse(.blockchain(.headers(.getTip)))
        }
        
        return tip
    }
    
    public func fetchScriptHashBalance(
        _ scriptHash: String,
        tokenFilter: SwiftFulcrum.Method.Blockchain.CashTokens.TokenFilter? = nil,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Response.Result.Blockchain.ScriptHash.GetBalance {
        let response = try await submit(
            method: .blockchain(.scripthash(.getBalance(scripthash: scriptHash, tokenFilter: tokenFilter))),
            responseType: SwiftFulcrum.Response.Result.Blockchain.ScriptHash.GetBalance.self,
            options: options
        )
        
        guard case .single(_, let balance) = response else {
            throw Error.unexpectedResponse(.blockchain(.scripthash(.getBalance(scripthash: scriptHash, tokenFilter: tokenFilter))))
        }
        
        return balance
    }
    
    public func fetchAddressBalance(
        _ address: String,
        tokenFilter: SwiftFulcrum.Method.Blockchain.CashTokens.TokenFilter? = nil,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance {
        let response = try await submit(
            method: .blockchain(.address(.getBalance(address: address, tokenFilter: tokenFilter))),
            responseType: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance.self,
            options: options
        )
        
        guard case .single(_, let balance) = response else {
            throw Error.unexpectedResponse(.blockchain(.address(.getBalance(address: address, tokenFilter: tokenFilter))))
        }
        
        return balance
    }
    
    public func fetchScriptHashUnspent(
        _ scriptHash: String,
        tokenFilter: SwiftFulcrum.Method.Blockchain.CashTokens.TokenFilter? = nil,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Response.Result.Blockchain.ScriptHash.ListUnspent {
        let response = try await submit(
            method: .blockchain(.scripthash(.listUnspent(scripthash: scriptHash, tokenFilter: tokenFilter))),
            responseType: SwiftFulcrum.Response.Result.Blockchain.ScriptHash.ListUnspent.self,
            options: options
        )
        
        guard case .single(_, let unspent) = response else {
            throw Error.unexpectedResponse(.blockchain(.scripthash(.listUnspent(scripthash: scriptHash, tokenFilter: tokenFilter))))
        }
        
        return unspent
    }
    
    public func fetchScriptHashHistory(
        _ scriptHash: String,
        fromHeight: UInt? = nil,
        toHeight: UInt? = nil,
        includeUnconfirmed: Bool = true,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Response.Result.Blockchain.ScriptHash.GetHistory {
        let response = try await submit(
            method: .blockchain(.scripthash(.getHistory(scripthash: scriptHash,
                                                        fromHeight: fromHeight,
                                                        toHeight: toHeight,
                                                        includeUnconfirmed: includeUnconfirmed))),
            responseType: SwiftFulcrum.Response.Result.Blockchain.ScriptHash.GetHistory.self,
            options: options
        )
        
        guard case .single(_, let history) = response else {
            throw Error.unexpectedResponse(.blockchain(.scripthash(.getHistory(scripthash: scriptHash,
                                                                               fromHeight: fromHeight,
                                                                               toHeight: toHeight,
                                                                               includeUnconfirmed: includeUnconfirmed))))
        }
        
        return history
    }
    
    public func fetchTransactionMerkleProof(
        forTransactionHash transactionHash: String,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Response.Result.Blockchain.Transaction.GetMerkle {
        let response = try await submit(
            method: .blockchain(.transaction(.getMerkle(transactionHash: transactionHash))),
            responseType: SwiftFulcrum.Response.Result.Blockchain.Transaction.GetMerkle.self,
            options: options
        )
        
        guard case .single(_, let merkle) = response else {
            throw Error.unexpectedResponse(.blockchain(.transaction(.getMerkle(transactionHash: transactionHash))))
        }
        
        return merkle
    }
    
    public func broadcastTransaction(
        _ rawTransaction: String,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> SwiftFulcrum.Response.Result.Blockchain.Transaction.Broadcast {
        let response = try await submit(
            method: .blockchain(.transaction(.broadcast(rawTransaction: rawTransaction))),
            responseType: SwiftFulcrum.Response.Result.Blockchain.Transaction.Broadcast.self,
            options: options
        )
        
        guard case .single(_, let broadcast) = response else {
            throw Error.unexpectedResponse(.blockchain(.transaction(.broadcast(rawTransaction: rawTransaction))))
        }
        
        return broadcast
    }
}
