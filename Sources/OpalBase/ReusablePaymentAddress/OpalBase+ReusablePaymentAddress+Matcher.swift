// OpalBase+ReusablePaymentAddress+Matcher.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// Performs deterministic Cash Code v1 matching over one serialized
    /// Bitcoin Cash transaction.
    public struct Matcher: Sendable {
        public init() {}

        /// Returns every output derived from a qualifying, prefix-matching
        /// input among the first 30 transaction inputs.
        ///
        /// The serialized transaction must contain exactly one transaction
        /// with no trailing bytes. The caller must obtain it from accepted
        /// confirmed history or a node mempool; this matcher validates the
        /// local Cash Code input shape but does not execute transaction scripts.
        public func matches(
            in serializedTransaction: Data,
            for reusablePaymentAddress: OpalBase.ReusablePaymentAddress,
            scanSigningKey: OpalBase.Key.SigningKey,
            spendSigningKey: OpalBase.Key.SigningKey
        ) throws -> [Match] {
            guard reusablePaymentAddress.profile == .cashCodeV1 else {
                throw Error.unsupportedProfile(
                    reusablePaymentAddress.profile
                )
            }
            guard scanSigningKey.publicKey
                == reusablePaymentAddress.scanPublicKey
            else {
                throw Error.scanSigningKeyMismatch
            }
            guard spendSigningKey.publicKey
                == reusablePaymentAddress.spendPublicKey
            else {
                throw Error.spendSigningKeyMismatch
            }

            let transaction: OpalBase.Transaction
            let bytesRead: Int
            do {
                let decoded = try OpalBase.Transaction.decode(
                    from: serializedTransaction
                )
                transaction = decoded.transaction
                bytesRead = decoded.bytesRead
            } catch {
                throw Error.invalidSerializedTransaction
            }
            guard bytesRead == serializedTransaction.count else {
                throw Error.invalidSerializedTransaction
            }

            let transactionHash = OpalBase.Transaction.Hash(
                naturalOrder: OpalCryptoAdapter.hash256(serializedTransaction)
            )
            var matches: [Match] = []

            for qualifyingInput in CashCodeQualifyingInput.collect(
                from: transaction
            ) {
                guard reusablePaymentAddress.filterPrefix.matches(
                    qualifyingInput.input
                ) else {
                    continue
                }

                let receivingSigningKey: OpalBase.Key.SigningKey
                do {
                    let sharedPointDigest = try CashCodeDerivation
                        .makeSharedPointDigest(
                            signingKey: scanSigningKey,
                            publicKey: qualifyingInput.publicKey
                        )
                    receivingSigningKey = try CashCodeDerivation
                        .deriveSigningKey(
                            from: spendSigningKey,
                            sharedPointDigest: sharedPointDigest,
                            outpoint: .init(qualifyingInput.input)
                        )
                } catch let error as Error {
                    throw error
                } catch {
                    throw Error.childKeyDerivationFailed
                }

                let expectedLockingScript = CashCodeDerivation
                    .makeLockingScript(
                        for: receivingSigningKey.publicKey
                    )
                let qualifyingInputIndex = UInt32(qualifyingInput.index)

                for (outputIndex, output) in transaction.outputs.enumerated()
                where output.lockingScript == expectedLockingScript {
                    guard let outputIndex = UInt32(exactly: outputIndex) else {
                        throw Error.invalidSerializedTransaction
                    }
                    matches.append(
                        Match(
                            transactionHash: transactionHash,
                            qualifyingInputIndex: qualifyingInputIndex,
                            senderPublicKey: qualifyingInput.publicKey,
                            senderOutpoint: .init(qualifyingInput.input),
                            outputIndex: outputIndex,
                            output: output,
                            receivingSigningKey: receivingSigningKey
                        )
                    )
                }
            }

            return matches
        }
    }
}
