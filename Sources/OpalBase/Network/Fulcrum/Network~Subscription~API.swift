// Network~Subscription~API.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func subscribeToScriptHash(
        _ scriptHash: String,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Subscription<SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe, SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification> {
        try await makeSubscription(
            method: .blockchain(.scripthash(.subscribe(scripthash: scriptHash))),
            initialType: SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe.self,
            notificationType: SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification.self,
            options: options
        )
    }
    
    public func subscribeToAddress(
        _ address: String,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Subscription<SwiftFulcrum.Response.Result.Blockchain.Address.Subscribe, SwiftFulcrum.Response.Result.Blockchain.Address.SubscribeNotification> {
        try await makeSubscription(
            method: .blockchain(.address(.subscribe(address: address))),
            initialType: SwiftFulcrum.Response.Result.Blockchain.Address.Subscribe.self,
            notificationType: SwiftFulcrum.Response.Result.Blockchain.Address.SubscribeNotification.self,
            options: options
        )
    }
    
    public func subscribeToChainHeaders(
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Subscription<SwiftFulcrum.Response.Result.Blockchain.Headers.Subscribe, SwiftFulcrum.Response.Result.Blockchain.Headers.SubscribeNotification> {
        try await makeSubscription(
            method: .blockchain(.headers(.subscribe)),
            initialType: SwiftFulcrum.Response.Result.Blockchain.Headers.Subscribe.self,
            notificationType: SwiftFulcrum.Response.Result.Blockchain.Headers.SubscribeNotification.self,
            options: options
        )
    }
}
