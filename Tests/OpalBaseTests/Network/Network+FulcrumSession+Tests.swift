import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession", .tags(.network))
struct NetworkFulcrumSessionTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let alternativeServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("initializer configures preferred and candidate servers")
    func testInitializeConfiguresCandidateServers() async throws {
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [Self.alternativeServerAddress])
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress,
                                                       configuration: configuration)
        
        #expect(await session.preferredServerAddress == Self.healthyServerAddress)
        #expect(await session.candidateServerAddresses == [Self.healthyServerAddress, Self.alternativeServerAddress])
        #expect(await session.activeServerAddress == nil)
        #expect(await session.state == .stopped)
        #expect(await session.isRunning == false)
        #expect(await session.isOperational == false)
    }
    
    @Test("initializer rejects unsupported server scheme")
    func testInitializeRejectsUnsupportedServerScheme() async throws {
        let unsupportedServer = URL(string: "https://fulcrum.invalid")!
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [Self.healthyServerAddress])
        
        await #expect(throws: Network.FulcrumSession.Error.unsupportedServerAddress) {
            _ = try await Network.FulcrumSession(serverAddress: unsupportedServer,
                                                 configuration: configuration)
        }
    }
    
    @Test("ensureSessionReady validates running and restoring states")
    func testEnsureSessionReadyValidatesStates() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await session.ensureSessionReady()
        }
        
        await session.updateState(.restoring)
        
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await session.ensureSessionReady()
        }
        
        try await session.ensureSessionReady(allowRestoring: true)
        
        await session.updateState(.running)
        try await session.ensureSessionReady()
    }
    
    @Test("makeCandidateServerAddresses filters duplicates and invalid schemes")
    func testMakeCandidateServerAddressesFiltersInvalidServers() {
        let duplicateServer = Self.healthyServerAddress
        let invalidServer = URL(string: "ftp://example.com")!
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [duplicateServer,
                                                                                  invalidServer,
                                                                                  Self.alternativeServerAddress])
        
        let addresses = Network.FulcrumSession.makeCandidateServerAddresses(from: nil,
                                                                            configuration: configuration)
        
        #expect(addresses == [duplicateServer, Self.alternativeServerAddress])
    }
    
    @Test("event stream forwards emitted lifecycle events from live server", .timeLimit(.minutes(1)))
    func testEventStreamForwardsLifecycleEvents() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        var events = await session.makeEventStream().makeAsyncIterator()
        
        try await session.start()
        
        var didReceiveStart = false
        for _ in 0..<8 {
            guard let event = await events.next() else { break }
            switch event {
            case .didStart(let server) where server == Self.healthyServerAddress:
                didReceiveStart = true
                break
            default:
                continue
            }
            
            if didReceiveStart { break }
        }
        
        #expect(didReceiveStart)
        #expect(await session.isOperational)
    }
    
    @Test("event stream termination removes continuation")
    func testEventStreamTerminationRemovesContinuation() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        
        _ = await session.makeEventStream()
        
        #expect(await session.eventContinuations.count == 1)
        
        try await Task.sleep(for: .seconds(5))
        
        #expect(await session.eventContinuations.isEmpty)
    }
    
    @Test("error equatability matches associated values")
    func testErrorEquatabilityMatchesAssociatedValues() {
        let addressMethod = SwiftFulcrum.Method.blockchain(.address(.getBalance(address: Self.sampleAddress, tokenFilter: nil)))
        let scriptHashMethod = SwiftFulcrum.Method.blockchain(.scripthash(.getBalance(scripthash: "", tokenFilter: nil)))
        
        #expect(Network.FulcrumSession.Error.sessionAlreadyStarted == .sessionAlreadyStarted)
        #expect(Network.FulcrumSession.Error.sessionNotStarted == .sessionNotStarted)
        #expect(Network.FulcrumSession.Error.subscriptionNotFound == .subscriptionNotFound)
        #expect(Network.FulcrumSession.Error.unexpectedResponse(addressMethod)
                == Network.FulcrumSession.Error.unexpectedResponse(addressMethod))
        #expect(Network.FulcrumSession.Error.unexpectedResponse(addressMethod)
                != Network.FulcrumSession.Error.unexpectedResponse(scriptHashMethod))
        
        let firstError = NSError(domain: "session.test", code: 1)
        let secondError = NSError(domain: "session.test", code: 2)
        
        #expect(Network.FulcrumSession.Error.failedToRestoreSubscription(firstError)
                == Network.FulcrumSession.Error.failedToRestoreSubscription(firstError))
        #expect(Network.FulcrumSession.Error.failedToRestoreSubscription(firstError)
                != Network.FulcrumSession.Error.failedToRestoreSubscription(secondError))
    }
}
