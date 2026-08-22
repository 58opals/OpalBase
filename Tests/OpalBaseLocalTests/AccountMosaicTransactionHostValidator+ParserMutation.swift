// AccountMosaicTransactionHostValidator+ParserMutation.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test(
        "Deterministic mutations cover every Mosaic BCH transaction root",
        .timeLimit(.minutes(1))
    )
    func mutateMosaicTransactionRoots() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy
        )
        let lease = try await fixture.reserve()
        let signingRequest = try fixture.makeSigningRequest(lease: lease)
        let finalized = try await fixture.host.finalizeMosaicTransaction(
            for: signingRequest
        )
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "OpalBase Mosaic unsigned proposal",
                seedBytes: Data(signingRequest.unsignedTransactionBytes)
            ) { bytes in
                let request = try replacingUnsignedTransactionBytes(
                    in: signingRequest,
                    with: bytes
                )
                let transaction = try OpalBase.Account
                    .MosaicCompleteTransactionValidator
                    .validateProposal(request).transaction
                return try transaction.encode() == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "OpalBase Mosaic complete transaction",
                seedBytes: Data(complete.transactionBytes)
            ) { bytes in
                let candidate = try OpalFusion.Host.MosaicCompleteTransaction(
                    transactionBytes: [UInt8](bytes)
                )
                let transaction = try OpalBase.Account
                    .MosaicCompleteTransactionValidator.validateComplete(
                        candidate,
                        signingRequest: signingRequest
                    )
                return try transaction.encode() == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "OpalBase exact recovered transaction",
                seedBytes: Data(complete.transactionBytes)
            ) { bytes in
                let candidate = try OpalFusion.Host.MosaicCompleteTransaction(
                    transactionBytes: [UInt8](bytes)
                )
                let exact = try OpalBase.Account.MosaicExactTransaction(
                    candidate
                )
                guard exact.bytes == bytes else { return false }
                return try exact.transaction.encode() == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "OpalBase locally signed continuation",
                seedBytes: Data(finalized.signedFusionTransactionBytes)
            ) { bytes in
                let candidate = OpalFusion.Host.FinalizedTransaction(
                    signedFusionTransactionBytes: [UInt8](bytes)
                )
                try OpalBase.Account.MosaicExactTransaction
                    .validateLocallySignedContinuation(
                        complete,
                        from: candidate,
                        signingRequest: signingRequest
                )
                let decoded = try OpalBase.Transaction.decode(from: bytes)
                guard decoded.bytesRead == bytes.count else { return false }
                return try decoded.transaction.encode() == bytes
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0xBB67_AE85_84CA_A73B,
            seededMutationCount: 32
        )
    }

    private func replacingUnsignedTransactionBytes(
        in request: OpalFusion.Host.MosaicTransactionSigningRequest,
        with bytes: Data
    ) throws -> OpalFusion.Host.MosaicTransactionSigningRequest {
        let original = request.transcriptBinding
        let transactionBytes = [UInt8](bytes)
        let root = try OpalFusion.Host.MosaicTranscriptBinding.transcriptRoot(
            profile: original.profile,
            manifestDigest: original.manifestDigest,
            commitmentSetDigest: original.commitmentSetDigest,
            componentSetDigest: original.componentSetDigest,
            unsignedTransactionBytes: transactionBytes
        )
        let binding = try OpalFusion.Host.MosaicTranscriptBinding(
            profile: original.profile,
            manifestDigest: original.manifestDigest,
            commitmentSetDigest: original.commitmentSetDigest,
            componentSetDigest: original.componentSetDigest,
            unsignedTransactionBytes: transactionBytes,
            acknowledgedTranscriptRoot: root
        )
        return try .init(
            reservationReference: request.reservationReference,
            roundIdentifier: request.roundIdentifier,
            transcriptBinding: binding,
            unsignedTransactionBytes: transactionBytes,
            spentInputs: request.spentInputs,
            localInputIndices: request.localInputIndices,
            expectedLocalOutputs: request.expectedLocalOutputs,
            feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: request.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: request.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: request.requiredExcessFeeSatoshis,
            transactionProfileIdentifier:
                request.transactionProfileIdentifier
        )
    }
}
#endif

