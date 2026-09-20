// AccountMosaicPrivateAlphaDiscoveryInboxValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic discovery inbox facade", .tags(.unit, .wallet), .timeLimit(.minutes(1)))
struct AccountMosaicPrivateAlphaDiscoveryInboxValidator {
    private typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

    @Test("Base projects one canonical event from three sources and redacts source loss")
    func receiveAndSourceLoss() async throws {
        let (inbox, connections, preparation) = try makeInbox()
        let stream = try await inbox.start()
        let bytes = try beacon(preparation: preparation)
        for connection in connections { try await connection.deliver(bytes) }
        var iterator = stream.makeAsyncIterator()
        let value = try #require(try await iterator.next())
        #expect(value.payloadKind == 0)
        #expect(value.event.canonicalEventBytes == bytes)
        #expect(value.event.acceptedAtUnixSeconds == 1_800_000_002)
        await connections[0].close()
        var duplicateCount = 0
        await #expect(throws: Runtime.Failure.runtimeOperationFailed) {
            while try await iterator.next() != nil { duplicateCount += 1 }
        }
        #expect(duplicateCount == 0)
        await inbox.stop()
        for connection in connections { #expect(await connection.closeCount == 1) }
    }

    @Test("Canceling the Base consumer and stopping joins all three routes")
    func cancellationClosesRoutes() async throws {
        let (inbox, connections, preparation) = try makeInbox()
        let stream = try await inbox.start()
        let (receipts, receipt) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let consumer = Task {
            for try await _ in stream { receipt.yield(()) }
        }
        try await connections[0].deliver(beacon(preparation: preparation))
        var received = receipts.makeAsyncIterator()
        _ = await received.next()
        consumer.cancel()
        await inbox.stop()
        _ = await consumer.result
        receipt.finish()
        for connection in connections { #expect(await connection.closeCount == 1) }
    }

    @Test("Base preserves route isolation rejection before startup")
    func rejectsReusedIsolation() async throws {
        let (inbox, connections, _) = try makeInbox(sharedIsolation: UUID())
        await #expect(throws: Runtime.Failure.runtimeOperationFailed) {
            _ = try await inbox.start()
        }
        for connection in connections {
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
        }
    }

    @Test("Base preserves the inbox's finite event bounds", arguments: [0, 1_025])
    func rejectsInvalidBounds(maximum: Int) throws {
        #expect(throws: Runtime.Failure.runtimeOperationFailed) {
            _ = try makeInbox(maximum: maximum)
        }
    }

    private func makeInbox(maximum: Int = 32, sharedIsolation: UUID? = nil) throws
        -> (Runtime.PrivateDeploymentInbox, [MosaicDiscoveryInboxConnectionProbe], Runtime.DiscoveryPreparation) {
        let preparation = try Runtime.DiscoveryPreparation(
            epochStartUnixSeconds: 1_800_000_000,
            appGeneratedOpaquePoolIdentifier: Data(repeating: 0x31, count: 32),
            relays: (1 ... 3).map { .init(endpoint: "wss://relay-\($0).example/", reviewedOperatorLabel: "fixture operator \($0)") })
        let connections = (0 ..< 3).map { _ in MosaicDiscoveryInboxConnectionProbe() }
        let routes = zip(preparation.relayEndpointIdentifiers, connections).map {
            Runtime.PostManifestProvisionedRoute(relayEndpointIdentifier: $0, connection: $1,
                                                isolationIdentifier: sharedIsolation ?? UUID())
        }
        let binding = try #require(Runtime.Binding(attemptIdentifier: Data(repeating: 1, count: 32),
            generationIdentifier: Data(repeating: 2, count: 32), materialIdentifier: Data(repeating: 3, count: 32)))
        let inbox = try preparation.makeInbox(binding: binding, capabilities: .init(provisionRoutes: { _ in routes }),
            maximumEventCount: maximum, currentUnixSeconds: { 1_800_000_002 })
        return (inbox, connections, preparation)
    }

    private func beacon(preparation: Runtime.DiscoveryPreparation) throws -> Data {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        let key = try OpalCrypto.Secp256k1.SigningKey(rawRepresentation: Data(repeating: 0, count: 31) + Data([1]))
        let core = try Alpha.AvailabilityBeaconCoreDocument(discoveryEpochStartUnixSeconds: 1_800_000_000,
            opaquePoolIdentifier: [UInt8](repeating: 0x31, count: 32), discoveryIdentity: key.bip340VerificationKey,
            relaySetDigest: [UInt8](preparation.relaySetDigest), proofOfWorkNonce: 988_699, expiryUnixSeconds: 1_800_000_060)
        let work = try Alpha.AvailabilityBeaconDocument.validateWork(for: core)
        let digest = Alpha.AvailabilityBeaconDocument.deriveSignatureDigest(core: core, claimedWorkBitCount: work)
        let randomness = try OpalCrypto.Signature.BIP340.AuxiliaryRandomness(rawRepresentation: Data(repeating: 0, count: 32))
        let signature = try key.signBIP340(digest: .init(rawRepresentation: Data(digest)), auxiliaryRandomness: randomness)
        let beacon = try Alpha.AvailabilityBeaconDocument(core: core, claimedWorkBitCount: work,
                                                         signature: [UInt8](signature.rawRepresentation))
        return try OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent.makeLocal(
            payload: .makeAvailabilityBeacon(beacon), createdAtUnixSeconds: 1_800_000_001,
            signing: .init(signingKey: key, documentAuxiliaryRandomness: randomness,
                           eventAuxiliaryRandomness: randomness)).canonicalEventBytes
    }
}

private actor MosaicDiscoveryInboxConnectionProbe: OpalBase.Account.MosaicPrivateAlphaRuntime.TorWebSocketConnection {
    typealias MessageStream = OpalBase.Account.MosaicPrivateAlphaRuntime.TorWebSocketConnection.MessageStream
    private var continuation: MessageStream.Continuation?
    private var subscription: String?
    private var closed = false
    private(set) var openCount = 0
    private(set) var closeCount = 0

    func open(maximumIncomingMessageByteCount: Int) async throws -> MessageStream {
        openCount += 1
        let pair = MessageStream.makeStream(bufferingPolicy: .bufferingOldest(8))
        continuation = pair.continuation
        return pair.stream
    }

    func send(text: String) async throws {
        let frame = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any])
        if frame.first as? String == "REQ" { subscription = try #require(frame[1] as? String) }
    }

    func deliver(_ bytes: Data) throws {
        let subscription = try #require(subscription)
        let prefix = try JSONSerialization.data(withJSONObject: ["EVENT", subscription])
        continuation?.yield(.text(Data(prefix.dropLast()) + Data(",".utf8) + bytes + Data("]".utf8)))
    }

    func close() async {
        guard !closed else { return }
        closed = true
        closeCount += 1
        continuation?.finish()
        continuation = nil
    }
}
#endif
