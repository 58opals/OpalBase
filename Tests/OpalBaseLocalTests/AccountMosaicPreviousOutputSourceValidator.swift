// AccountMosaicPreviousOutputSourceValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
import OpalFusion
import Testing
@testable import OpalBase

@Suite(
    "OpalBase.Network Mosaic previous-output source",
    .tags(.unit, .network, .transaction)
)
struct AccountMosaicPreviousOutputSourceValidator {
    typealias Failure = OpalBase.Network.TransactionReader
        .MosaicPreviousOutputResolutionFailure
    typealias Fixture = MosaicProfileTransactionPolicyFixture

    private actor ReaderProbe {
        enum ProbeError: Swift.Error {
            case unavailable
        }

        private let rawTransactions: [OpalBase.Transaction.Hash: Data]
        private let suspension: MosaicOperationSuspensionProbeActor?
        private(set) var requestedHashes: [OpalBase.Transaction.Hash] = []

        init(
            rawTransactions: [OpalBase.Transaction.Hash: Data],
            suspension: MosaicOperationSuspensionProbeActor? = nil
        ) {
            self.rawTransactions = rawTransactions
            self.suspension = suspension
        }

        func fetch(_ transactionHash: OpalBase.Transaction.Hash) async throws
            -> Data
        {
            requestedHashes.append(transactionHash)
            await suspension?.suspend()
            guard let rawTransaction = rawTransactions[transactionHash]
            else {
                throw ProbeError.unavailable
            }
            return rawTransaction
        }
    }

    enum InvalidTransactionPayload: CaseIterable, Sendable {
        case malformed
        case trailing
        case noncanonical
    }

    @Test("Resolve multiple requests in caller order using display-order hashes")
    func resolveOrderedRequests() async throws {
        let first = try Fixture.makeInputMaterial(
            seed: 1,
            amountSatoshis: 10_000
        )
        let second = try Fixture.makeInputMaterial(
            seed: 2,
            amountSatoshis: 20_000
        )
        let probe = ReaderProbe(
            rawTransactions: [
                first.transactionHash: first.rawPreviousTransaction,
                second.transactionHash: second.rawPreviousTransaction,
            ]
        )
        let reader = makeReader(probe)
        let requests: [OpalFusion.Host.MosaicPreviousOutputRequest] = try [
            second,
            first,
        ].map { try makeRequest(for: $0) }

        let outputs: [OpalFusion.Host.MosaicPreviousOutput] = try await reader
            .resolvePreviousOutputs(for: requests)

        #expect(
            await probe.requestedHashes
                == [second.transactionHash, first.transactionHash]
        )
        #expect(outputs.map(\.transactionHashBytes) == requests.map(\.transactionHashBytes))
        #expect(outputs.map(\.amountSatoshis) == [20_000, 10_000])
        #expect(outputs.allSatisfy { $0.tokenState == .absent })
    }

    @Test("Return source facts without applying transcript or P2PKH policy")
    func returnActualOutputFacts() async throws {
        let script = Data([0x51])
        let material = try Fixture.makeInputMaterial(
            amountSatoshis: 25_000,
            previousOutputLockingScript: script
        )
        let probe = ReaderProbe(
            rawTransactions: [
                material.transactionHash: material.rawPreviousTransaction,
            ]
        )
        let request = try makeRequest(
            for: material,
            expectedAmountSatoshis: 30_000
        )

        let output = try #require(
            await makeReader(probe).resolvePreviousOutputs(for: [request])
                .first
        )

        #expect(output.amountSatoshis == 25_000)
        #expect(output.lockingScriptBytes == [0x51])
        #expect(output.tokenState == .absent)
    }

    @Test("Report CashToken presence without accepting or hiding it")
    func reportTokenPresence() async throws {
        let material = try Fixture.makeInputMaterial(
            previousOutputTokenData: CashFusionTestSupport.makeTokenData()
        )
        let probe = ReaderProbe(
            rawTransactions: [
                material.transactionHash: material.rawPreviousTransaction,
            ]
        )

        let output = try #require(
            await makeReader(probe).resolvePreviousOutputs(
                for: [makeRequest(for: material)]
            ).first
        )

        #expect(output.tokenState == .present)
    }

    @Test("Resolve repeated requests for distinct outputs of one transaction")
    func resolveRepeatedTransaction() async throws {
        let firstScript = Data([0x51])
        let secondScript = Data([0x52])
        let transaction = makePreviousTransaction(
            outputs: [
                .init(value: 11_000, lockingScript: firstScript),
                .init(value: 22_000, lockingScript: secondScript),
            ]
        )
        let rawTransaction = try transaction.encode()
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCrypto.Hashing.hash256(rawTransaction)
        )
        let probe = ReaderProbe(
            rawTransactions: [transactionHash: rawTransaction]
        )
        let requests = try [
            makeRequest(
                transactionHash: transactionHash,
                outputIndex: 1,
                expectedAmountSatoshis: 22_000
            ),
            makeRequest(
                transactionHash: transactionHash,
                outputIndex: 0,
                expectedAmountSatoshis: 11_000
            ),
        ]

        let outputs = try await makeReader(probe).resolvePreviousOutputs(
            for: requests
        )

        #expect(outputs.map(\.outputIndex) == [1, 0])
        #expect(outputs.map(\.amountSatoshis) == [22_000, 11_000])
        #expect(outputs.map(\.lockingScriptBytes) == [[0x52], [0x51]])
    }

    @Test("An empty request vector performs no reader I/O")
    func resolveEmptyRequestVector() async throws {
        let probe = ReaderProbe(rawTransactions: [:])

        let outputs = try await makeReader(probe).resolvePreviousOutputs(
            for: []
        )

        #expect(outputs.isEmpty)
        #expect(await probe.requestedHashes.isEmpty)
    }

    @Test("Reject unavailable and hash-substituted previous transactions")
    func rejectUnavailableAndSubstitutedTransactions() async throws {
        let material = try Fixture.makeInputMaterial(seed: 3)
        let request = try makeRequest(for: material)
        await #expect(
            throws: Failure.previousTransactionUnavailable(index: 0)
        ) {
            _ = try await makeReader(
                ReaderProbe(rawTransactions: [:])
            ).resolvePreviousOutputs(for: [request])
        }

        let substitute = try Fixture.makeInputMaterial(seed: 4)
        let probe = ReaderProbe(
            rawTransactions: [
                material.transactionHash: substitute.rawPreviousTransaction,
            ]
        )
        await #expect(
            throws: Failure.previousTransactionHashMismatch(index: 0)
        ) {
            _ = try await makeReader(probe).resolvePreviousOutputs(
                for: [request]
            )
        }
    }

    @Test(
        "Reject malformed, trailing, and noncanonical transaction bytes",
        arguments: InvalidTransactionPayload.allCases
    )
    func rejectInvalidTransactionBytes(
        _ payload: InvalidTransactionPayload
    ) async throws {
        let valid = try Fixture.makeInputMaterial(seed: 5)
            .rawPreviousTransaction
        let rawTransaction: Data
        switch payload {
        case .malformed:
            rawTransaction = Data([0x00])
        case .trailing:
            var bytes = valid
            bytes.append(0x00)
            rawTransaction = bytes
        case .noncanonical:
            var bytes = Data(valid.prefix(4))
            bytes.append(contentsOf: [0xFD, 0x01, 0x00])
            bytes.append(valid.dropFirst(5))
            rawTransaction = bytes
        }
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCrypto.Hashing.hash256(rawTransaction)
        )
        let probe = ReaderProbe(
            rawTransactions: [transactionHash: rawTransaction]
        )
        let request = try makeRequest(
            transactionHash: transactionHash,
            outputIndex: 0,
            expectedAmountSatoshis: 1
        )

        await #expect(
            throws: Failure.invalidPreviousTransaction(index: 0)
        ) {
            _ = try await makeReader(probe).resolvePreviousOutputs(
                for: [request]
            )
        }
    }

    @Test("Reject an unavailable previous output index")
    func rejectUnavailableOutput() async throws {
        let material = try Fixture.makeInputMaterial(seed: 6)
        let request = try makeRequest(
            transactionHash: material.transactionHash,
            outputIndex: 1,
            expectedAmountSatoshis: 1
        )
        let probe = ReaderProbe(
            rawTransactions: [
                material.transactionHash: material.rawPreviousTransaction,
            ]
        )

        await #expect(throws: Failure.previousOutputUnavailable(index: 0)) {
            _ = try await makeReader(probe).resolvePreviousOutputs(
                for: [request]
            )
        }
    }

    @Test("Preserve resolved-output structural failures")
    func rejectStructurallyInvalidOutput() async throws {
        let zeroValue = try Fixture.makeInputMaterial(
            seed: 7,
            amountSatoshis: 0,
            previousOutputLockingScript: Data([0x51])
        )
        await #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .zeroResolvedPreviousOutputAmount
        ) {
            _ = try await makeReader(
                ReaderProbe(
                    rawTransactions: [
                        zeroValue.transactionHash:
                            zeroValue.rawPreviousTransaction,
                    ]
                )
            ).resolvePreviousOutputs(
                for: [
                    makeRequest(
                        for: zeroValue,
                        expectedAmountSatoshis: 1
                    ),
                ]
            )
        }

        let emptyScript = try Fixture.makeInputMaterial(
            seed: 8,
            previousOutputLockingScript: Data()
        )
        await #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .emptyResolvedPreviousOutputLockingScript
        ) {
            _ = try await makeReader(
                ReaderProbe(
                    rawTransactions: [
                        emptyScript.transactionHash:
                            emptyScript.rawPreviousTransaction,
                    ]
                )
            ).resolvePreviousOutputs(
                for: [makeRequest(for: emptyScript)]
            )
        }
    }

    @Test(
        "Preserve cancellation across reader I/O and reader errors",
        .timeLimit(.minutes(1))
    )
    func preserveCancellation() async throws {
        let material = try Fixture.makeInputMaterial(seed: 9)
        let request = try makeRequest(for: material)
        let suspension = MosaicOperationSuspensionProbeActor()
        let probe = ReaderProbe(
            rawTransactions: [:],
            suspension: suspension
        )
        let task = Task {
            try await makeReader(probe).resolvePreviousOutputs(for: [request])
        }
        await suspension.waitUntilSuspended()
        task.cancel()
        await suspension.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await probe.requestedHashes == [material.transactionHash])

        let cancellingReader = OpalBase.Network.TransactionReader { _ in
            throw CancellationError()
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancellingReader.resolvePreviousOutputs(
                for: [request]
            )
        }
    }

    private func makeReader(
        _ probe: ReaderProbe
    ) -> OpalBase.Network.TransactionReader {
        .init { transactionHash in
            try await probe.fetch(transactionHash)
        }
    }

    private func makeRequest(
        for material: Fixture.InputMaterial,
        expectedAmountSatoshis: UInt64? = nil
    ) throws -> OpalFusion.Host.MosaicPreviousOutputRequest {
        try makeRequest(
            transactionHash: material.transactionHash,
            outputIndex: material.participantInput.outpointIndex,
            expectedAmountSatoshis: expectedAmountSatoshis
                ?? material.participantInput.amountSatoshis
        )
    }

    private func makeRequest(
        transactionHash: OpalBase.Transaction.Hash,
        outputIndex: UInt32,
        expectedAmountSatoshis: UInt64
    ) throws -> OpalFusion.Host.MosaicPreviousOutputRequest {
        try .init(
            transactionHashBytes: [UInt8](transactionHash.reverseOrder),
            outputIndex: outputIndex,
            expectedAmountSatoshis: expectedAmountSatoshis
        )
    }

    private func makePreviousTransaction(
        outputs: [OpalBase.Transaction.Output]
    ) -> OpalBase.Transaction {
        .init(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(
                        naturalOrder: Data(repeating: 0xA5, count: 32)
                    ),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data([0x51])
                ),
            ],
            outputs: outputs,
            lockTime: 0
        )
    }
}
#endif
