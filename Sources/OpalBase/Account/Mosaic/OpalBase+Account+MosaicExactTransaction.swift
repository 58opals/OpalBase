// OpalBase+Account+MosaicExactTransaction.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Canonically decoded bytes, transaction, and hash for one complete Mosaic transaction.
    struct MosaicExactTransaction: Sendable {
        let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        let bytes: Data
        let transaction: OpalBase.Transaction
        let hash: OpalBase.Transaction.Hash

        init(
            _ completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        ) throws {
            let bytes = Data(completeTransaction.transactionBytes)
            let transaction = try Self.decodeExact(bytes)
            self.completeTransaction = completeTransaction
            self.bytes = bytes
            self.transaction = transaction
            hash = .init(naturalOrder: OpalCryptoAdapter.hash256(bytes))
        }

        static func validateLocallySignedContinuation(
            _ completeTransaction: OpalFusion.Host.MosaicCompleteTransaction,
            from locallySignedTransaction: OpalFusion.Host.FinalizedTransaction,
            signingRequest: OpalFusion.Host.MosaicTransactionSigningRequest
        ) throws {
            let locallySigned = try decodeExact(
                Data(locallySignedTransaction.signedFusionTransactionBytes)
            )
            let complete = try Self(completeTransaction).transaction

            guard locallySigned.version == complete.version,
                  locallySigned.lockTime == complete.lockTime,
                  locallySigned.inputs.count == complete.inputs.count,
                  locallySigned.outputs == complete.outputs,
                  signingRequest.localInputIndices.allSatisfy(
                    locallySigned.inputs.indices.contains
                  ) else {
                throw MosaicHostFailure.invalidCompleteTransaction
            }

            for index in complete.inputs.indices {
                let locallySignedInput = locallySigned.inputs[index]
                let completeInput = complete.inputs[index]
                guard locallySignedInput.previousTransactionHash
                        == completeInput.previousTransactionHash,
                      locallySignedInput.previousTransactionOutputIndex
                        == completeInput.previousTransactionOutputIndex,
                      locallySignedInput.sequence == completeInput.sequence else {
                    throw MosaicHostFailure.invalidCompleteTransaction
                }
            }
            for index in signingRequest.localInputIndices {
                guard !locallySigned.inputs[index].unlockingScript.isEmpty,
                      locallySigned.inputs[index].unlockingScript
                        == complete.inputs[index].unlockingScript else {
                    throw MosaicHostFailure.invalidCompleteTransaction
                }
            }
            _ = try MosaicCompleteTransactionValidator.validateComplete(
                completeTransaction,
                signingRequest: signingRequest
            )
        }

        private static func decodeExact(_ bytes: Data) throws
            -> OpalBase.Transaction {
            do {
                let decoded = try OpalBase.Transaction.decode(from: bytes)
                guard decoded.bytesRead == bytes.count,
                      try decoded.transaction.encode() == bytes else {
                    throw MosaicHostFailure.invalidCompleteTransaction
                }
                return decoded.transaction
            } catch let failure as MosaicHostFailure {
                throw failure
            } catch {
                throw MosaicHostFailure.invalidCompleteTransaction
            }
        }
    }
}
#endif
