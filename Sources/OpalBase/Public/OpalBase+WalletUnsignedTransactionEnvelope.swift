// OpalBase+WalletUnsignedTransactionEnvelope.swift

public extension OpalBase {
    /// Unsigned Bitcoin Cash transaction material needed by an external signing review boundary.
    struct WalletUnsignedTransactionEnvelope: Sendable {
        public enum Error: Swift.Error, Equatable, Sendable {
            case unsignedTransactionHasNoInputs
            case unsignedTransactionHasDuplicateInputs
            case unsignedTransactionHasNoOutputs
            case spentOutputCountMismatch(expected: Int, actual: Int)
            case signedInputCountMismatch(expected: Int, actual: Int)
            case signedTransactionDoesNotMatchEnvelope
            case missingSignedUnlockingScript(inputIndex: Int)
            case unchangedSignedUnlockingScript(inputIndex: Int)
            case unsupportedSignatureFormat
        }

        public let unsignedTransaction: OpalBase.Transaction
        public let spentOutputs: [OpalBase.Transaction.Output]
        public let signatureFormat: OpalBase.Transaction.SignatureFormat

        public init(
            unsignedTransaction: OpalBase.Transaction,
            spentOutputs: [OpalBase.Transaction.Output],
            signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr
        ) {
            self.unsignedTransaction = unsignedTransaction
            self.spentOutputs = spentOutputs
            self.signatureFormat = signatureFormat
        }

        public var hasMatchingInputAndSpentOutputCounts: Bool {
            unsignedTransaction.inputs.count == spentOutputs.count
        }

        /// Validates that a candidate signed transaction structurally matches this envelope.
        ///
        /// This check confirms the transaction shape, outpoints, non-empty output set, lock time, and
        /// non-empty changed unlocking scripts. It does not execute Bitcoin Cash script or cryptographically
        /// verify signatures.
        public func validateSignedTransactionStructure(_ signedTransaction: OpalBase.Transaction) throws {
            guard signatureFormat.isSupportedForTransactionSigning else {
                throw Error.unsupportedSignatureFormat
            }
            guard unsignedTransaction.inputs.isEmpty == false else {
                throw Error.unsignedTransactionHasNoInputs
            }
            guard Self.hasUniqueInputOutpoints(unsignedTransaction.inputs) else {
                throw Error.unsignedTransactionHasDuplicateInputs
            }
            guard unsignedTransaction.outputs.isEmpty == false else {
                throw Error.unsignedTransactionHasNoOutputs
            }
            guard hasMatchingInputAndSpentOutputCounts else {
                throw Error.spentOutputCountMismatch(
                    expected: unsignedTransaction.inputs.count,
                    actual: spentOutputs.count
                )
            }
            guard signedTransaction.inputs.count == unsignedTransaction.inputs.count else {
                throw Error.signedInputCountMismatch(
                    expected: unsignedTransaction.inputs.count,
                    actual: signedTransaction.inputs.count
                )
            }
            guard signedTransaction.version == unsignedTransaction.version,
                  signedTransaction.outputs == unsignedTransaction.outputs,
                  signedTransaction.lockTime == unsignedTransaction.lockTime else {
                throw Error.signedTransactionDoesNotMatchEnvelope
            }

            for index in unsignedTransaction.inputs.indices {
                let unsignedInput = unsignedTransaction.inputs[index]
                let signedInput = signedTransaction.inputs[index]
                guard InputOutpoint(signedInput) == InputOutpoint(unsignedInput),
                      signedInput.sequence == unsignedInput.sequence else {
                    throw Error.signedTransactionDoesNotMatchEnvelope
                }
                guard signedInput.unlockingScript.isEmpty == false else {
                    throw Error.missingSignedUnlockingScript(inputIndex: index)
                }
                guard signedInput.unlockingScript != unsignedInput.unlockingScript else {
                    throw Error.unchangedSignedUnlockingScript(inputIndex: index)
                }
            }
        }

        private static func hasUniqueInputOutpoints(_ inputs: [OpalBase.Transaction.Input]) -> Bool {
            var seenOutpoints = Set<InputOutpoint>()
            for input in inputs {
                guard seenOutpoints.insert(InputOutpoint(input)).inserted else {
                    return false
                }
            }
            return true
        }

        private struct InputOutpoint: Hashable {
            let hash: OpalBase.Transaction.Hash
            let outputIndex: UInt32

            init(_ input: OpalBase.Transaction.Input) {
                self.hash = input.previousTransactionHash
                self.outputIndex = input.previousTransactionOutputIndex
            }
        }
    }
}
