// AccountMosaicPrivateAlphaApplicationFacadeValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic application facade", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaApplicationFacadeValidator {
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

    @Test("App-only import creates the exact fresh owner and retains its binding")
    func createFreshOwnerWithoutImportingFusion() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            usage: .change,
            hashByte: 0xd1
        )
        let journalProbe = MosaicAttemptJournalProbeActor()
        let journalAttempt = OpalBase.Account.MosaicPrivateAlphaJournal
            .FreshAttempt(try await journalProbe.makeFreshAttempt())
        let binding = try #require(Runtime.Binding(
            attemptIdentifier: Data(repeating: 0x11, count: 32),
            generationIdentifier: Data(repeating: 0x22, count: 32),
            materialIdentifier: Data(repeating: 0x33, count: 32)
        ))
        let walletIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-0000000000d1")
        )

        let host = try await Runtime.createFreshApplicationHost(
            account: account,
            binding: binding,
            discoveryEpochStartUnixSeconds: 1_800_000_000,
            walletReservationIdentifier: walletIdentifier,
            walletGeneration: 42,
            selectedInputs: [selectedInput],
            outputAmountsSatoshis: [99_823],
            transactionReader: .init(
                fetchRawTransaction: { _ in Data() }
            ),
            journalAttempt: journalAttempt
        )

        #expect(host.binding == binding)
        #expect(host.makePostManifestOwner().binding == binding)
        guard case let .attemptBinding(recorded) =
            await journalProbe.readRecords().first else {
            Issue.record("Expected one durable Base binding")
            return
        }
        #expect(recorded.attemptIdentifier == binding.attemptIdentifier)
        #expect(
            recorded.generationIdentifier == binding.generationIdentifier
        )
        #expect(recorded.materialIdentifier == binding.materialIdentifier)
        #expect(
            recorded.walletReservationReference.identifier
                == walletIdentifier
        )
        #expect(recorded.walletReservationReference.generation == 42)
    }

    @Test("App-owned capability surface contains no raw Fusion type")
    func constructPostManifestCapabilitiesFromBaseTypes() throws {
        let binding = try #require(Runtime.Binding(
            attemptIdentifier: Data(repeating: 0x41, count: 32),
            generationIdentifier: Data(repeating: 0x42, count: 32),
            materialIdentifier: Data(repeating: 0x43, count: 32)
        ))
        let journals = Runtime.PostManifestJournalPersistence(
            load: { _, observed in
                #expect(observed == binding)
                return nil
            },
            compareAndSwap: { _, observed, _, replacement in
                #expect(observed == binding)
                return replacement
            }
        )
        let relays = Runtime.PostManifestRelayCapabilities(
            provisionRoutes: { _ in [] },
            makeSubscriptionIdentifier: { _, _ in "subscription" },
            maximumSubscriptionIdentifierByteCount: 64
        )
        let timing = Runtime.PostManifestTimingCapabilities(
            currentUnixSeconds: { 1_800_000_000 },
            makeLayerTimestamps: { request in
                .init(
                    phaseStartUnixSeconds: 1_800_000_000,
                    currentUnixSeconds: 1_800_000_001,
                    sealCreatedAt: request.expiryUnixSeconds - 2,
                    giftWrapCreatedAt: request.expiryUnixSeconds - 1
                )
            }
        )
        _ = Runtime.PostManifestRuntimeCapabilities(
            relays: relays,
            timing: timing,
            journals: journals
        )
        #expect(
            Runtime.Binding(
                attemptIdentifier: Data(repeating: 0, count: 31),
                generationIdentifier: binding.generationIdentifier,
                materialIdentifier: binding.materialIdentifier
            ) == nil
        )
    }
}
#endif
