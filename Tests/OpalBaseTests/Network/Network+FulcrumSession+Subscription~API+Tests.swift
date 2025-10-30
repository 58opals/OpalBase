import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Subscription API", .tags(.network, .integration))
struct NetworkFulcrumSessionSubscriptionAPITests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("subscribeToAddress delivers usable lifecycle affordances", .timeLimit(.minutes(1)))
    func testSubscribeToAddressLifecycle() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let subscription = try await session.subscribeToAddress(Self.sampleAddress)
        let initialStatus = await subscription.fetchLatestInitialResponse()
        
        #expect(initialStatus.status != nil, "Expected address subscription to return a status hash")
        if let status = initialStatus.status?.lowercased() {
            let allowedHexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
            let statusCharacters = CharacterSet(charactersIn: status)
            #expect(status.count == 64, "Expected Electrum status hash to have 64 hexadecimal characters")
            #expect(allowedHexCharacters.isSuperset(of: statusCharacters), "Expected status to be lowercase hexadecimal")
        }
        
        #expect(await subscription.checkIsActive())
        
        let resubscribedStatus = try await subscription.resubscribe()
        #expect(resubscribedStatus.status == initialStatus.status)
        #expect(await subscription.checkIsActive())
        
        await subscription.cancel()
        try await Task.sleep(for: .seconds(5))
        
        #expect(!(await subscription.checkIsActive()))
    }
    
    @Test("subscribeToScriptHash mirrors address semantics across reconnect", .timeLimit(.minutes(1)))
    func testSubscribeToScriptHashMatchesAddressStatusAfterReconnect() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let addressSubscription = try await session.subscribeToAddress(Self.sampleAddress)
        let scriptHashLookup = try await session.submit(
            method: .blockchain(.address(.getScriptHash(address: Self.sampleAddress))),
            responseType: SwiftFulcrum.Response.Result.Blockchain.Address.GetScriptHash.self
        )
        
        let scriptHash: String
        switch scriptHashLookup {
        case .single(_, let response):
            scriptHash = response.scriptHash
        default:
            #expect(Bool(false), "Expected single response when resolving script hash")
            return
        }
        
        let scriptHashSubscription = try await session.subscribeToScriptHash(scriptHash)
        
        let addressInitialStatus = await addressSubscription.fetchLatestInitialResponse()
        let scriptHashInitialStatus = await scriptHashSubscription.fetchLatestInitialResponse()
        
        #expect(addressInitialStatus.status == scriptHashInitialStatus.status)
        #expect(await addressSubscription.checkIsActive())
        #expect(await scriptHashSubscription.checkIsActive())
        
        let identifierBeforeReconnect = scriptHashSubscription.identifier
        
        try await session.reconnect()
        try await Task.sleep(for: .seconds(10))
        
        let refreshedStatus = await scriptHashSubscription.fetchLatestInitialResponse()
        #expect(refreshedStatus.status == scriptHashInitialStatus.status)
        #expect(await scriptHashSubscription.checkIsActive())
        #expect(scriptHashSubscription.identifier == identifierBeforeReconnect)
    }
    
    @Test("resubscribe surfaces sessionNotStarted after stop", .timeLimit(.minutes(1)))
    func testResubscribeAfterStopThrowsSessionNotStarted() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let subscription = try await session.subscribeToAddress(Self.sampleAddress)
        try await session.stop()
        
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await subscription.resubscribe()
        }
        
        #expect(!(await subscription.checkIsActive()))
    }
}
