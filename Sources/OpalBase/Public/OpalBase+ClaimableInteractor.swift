// OpalBase+ClaimableInteractor.swift

import Foundation

public extension OpalBase {
    /// Claimable lane for records, funding outputs, envelopes, share material, claim/refund transaction authoring, and status resolution.
    struct ClaimableInteractor: Sendable {
        private let statusResolver: OpalBase.Claimable.StatusResolver?

        public init() {
            self.statusResolver = nil
        }

        public init(
            network: OpalBase.Network.Environment,
            scriptHashReader: OpalBase.Network.ScriptHashReader,
            transactionClient: OpalBase.Network.TransactionClient? = nil,
            transactionReader: OpalBase.Network.TransactionReader? = nil
        ) {
            self.statusResolver = OpalBase.Claimable.StatusResolver(
                network: network,
                scriptHashReader: scriptHashReader,
                transactionClient: transactionClient,
                transactionReader: transactionReader
            )
        }

        public func makeDraft(
            network: OpalBase.Network.Environment,
            refundPrivateKey: Data,
            expiryBlockHeight: UInt32
        ) throws -> OpalBase.Claimable.Draft {
            try OpalBase.Claimable.Draft(
                network: network,
                refundPrivateKey: refundPrivateKey,
                expiryBlockHeight: expiryBlockHeight
            )
        }

        public func makeFundingOutput(
            from draft: OpalBase.Claimable.Draft,
            value: UInt64
        ) -> OpalBase.Transaction.Output {
            draft.makeFundingOutput(value: value)
        }

        public func makeEnvelope(
            contract: OpalBase.Claimable.Contract,
            claimPrivateKey: Data,
            fundingTransactionHash: OpalBase.Transaction.Hash,
            fundingOutputIndex: UInt32,
            fundingValue: UInt64
        ) throws -> OpalBase.Claimable.Envelope {
            try OpalBase.Claimable.Envelope(
                contract: contract,
                claimPrivateKey: claimPrivateKey,
                fundingTransactionHash: fundingTransactionHash,
                fundingOutputIndex: fundingOutputIndex,
                fundingValue: fundingValue
            )
        }

        public func encodeEnvelope(_ envelope: OpalBase.Claimable.Envelope) -> Data {
            envelope.encode()
        }

        public func decodeEnvelope(from data: Data) throws -> OpalBase.Claimable.Envelope {
            try OpalBase.Claimable.Envelope.decode(from: data)
        }

        public func decodeEnvelope(
            from data: Data,
            on network: OpalBase.Network.Environment
        ) throws -> OpalBase.Claimable.Envelope {
            try OpalBase.Claimable.Envelope.decode(from: data, on: network)
        }

        public func encodeShareCode(for envelope: OpalBase.Claimable.Envelope) throws -> String {
            try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
        }

        public func decodeShareCode(_ text: String) throws -> OpalBase.Claimable.Envelope {
            try OpalBase.Claimable.ShareCode.decode(text)
        }

        public func decodeShareCodeEnvelopeData(_ text: String) throws -> Data {
            try OpalBase.Claimable.ShareCode.decodeEnvelopeData(text)
        }

        public func makeLocalStatus(
            for envelope: OpalBase.Claimable.Envelope,
            currentBlockHeight: UInt32
        ) -> OpalBase.Claimable.LocalStatus {
            envelope.makeLocalStatus(currentBlockHeight: currentBlockHeight)
        }

        public func resolveStatus(
            for envelope: OpalBase.Claimable.Envelope,
            includeUnconfirmed: Bool,
            currentBlockHeight: UInt32
        ) async throws -> OpalBase.Claimable.NetworkStatus {
            guard let statusResolver else {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Claimable status resolution requires public-chain readers."
                )
            }
            return try await statusResolver.resolve(
                for: envelope,
                includeUnconfirmed: includeUnconfirmed,
                currentBlockHeight: currentBlockHeight
            )
        }

        public func buildClaimTransaction(
            from envelope: OpalBase.Claimable.Envelope,
            destinationLockingScript: Data,
            feePerByte: UInt64 = OpalBase.Transaction.defaultFeeRate,
            currentBlockHeight: UInt32
        ) throws -> OpalBase.Transaction {
            try envelope.buildClaimTransaction(
                destinationLockingScript: destinationLockingScript,
                feePerByte: feePerByte,
                currentBlockHeight: currentBlockHeight
            )
        }

        public func buildRefundTransaction(
            from envelope: OpalBase.Claimable.Envelope,
            refundPrivateKey: Data,
            destinationLockingScript: Data,
            feePerByte: UInt64 = OpalBase.Transaction.defaultFeeRate,
            currentBlockHeight: UInt32
        ) throws -> OpalBase.Transaction {
            try envelope.buildRefundTransaction(
                refundPrivateKey: refundPrivateKey,
                destinationLockingScript: destinationLockingScript,
                feePerByte: feePerByte,
                currentBlockHeight: currentBlockHeight
            )
        }

        public func makeClaimRecoveryMaterial(
            from envelope: OpalBase.Claimable.Envelope
        ) throws -> OpalBase.Claimable.RecoveryMaterial {
            try envelope.makeClaimRecoveryMaterial()
        }

        public func makeRefundRecoveryMaterial(
            from envelope: OpalBase.Claimable.Envelope,
            refundPrivateKey: Data
        ) throws -> OpalBase.Claimable.RecoveryMaterial {
            try envelope.makeRefundRecoveryMaterial(refundPrivateKey: refundPrivateKey)
        }
    }
}
