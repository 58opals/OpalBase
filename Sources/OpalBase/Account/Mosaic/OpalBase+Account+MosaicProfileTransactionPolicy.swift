// OpalBase+Account+MosaicProfileTransactionPolicy.swift

#if os(macOS)
import Foundation
import OpalCrypto
import OpalFusion

extension _OpalBase.Account {
    /// Fail-closed validation shared by the two explicitly supported Mosaic profiles.
    struct MosaicProfileTransactionPolicy: Sendable {
        enum Failure: Swift.Error, Sendable, Equatable {
            case unsupportedProfileNetworkPair
            case incompatibleProfile
            case invalidTranscriptBinding
            case invalidTransactionProfile
            case invalidFeeTerms
            case invalidVersion
            case invalidLockTime
            case invalidInputCount
            case invalidInput(index: Int)
            case invalidInputSequence(index: Int)
            case invalidInputOrdering
            case invalidOutput(index: Int)
            case invalidOutputOrdering
            case previousTransactionUnavailable(index: Int)
            case previousTransactionHashMismatch(index: Int)
            case invalidPreviousTransaction(index: Int)
            case previousOutputUnavailable(index: Int)
            case previousOutputMismatch(index: Int)
            case feeMismatch(expected: UInt64, actual: UInt64)
        }

        private let profile: OpalFusion.Mosaic.Profile
        private let contributionPolicy: MosaicProfileContributionPolicy
        private let transactionReader: OpalBase.Network.TransactionReader

        init(
            profile: OpalFusion.Mosaic.Profile,
            network: OpalBase.Network.Environment,
            transactionReader: OpalBase.Network.TransactionReader
        ) throws {
            guard network.supportsMosaicProfile(profile),
                  let contributionPolicy = MosaicProfileContributionPolicy(
                    profile: profile
                  ) else {
                throw Failure.unsupportedProfileNetworkPair
            }
            self.profile = profile
            self.contributionPolicy = contributionPolicy
            self.transactionReader = transactionReader
        }

        func validate(
            transaction: OpalBase.Transaction,
            request: OpalFusion.Host.MosaicTransactionSigningRequest,
            feeSatoshis: UInt64
        ) async throws {
            try validateBinding(transaction: transaction, request: request)
            try validateTransactionShape(transaction, request: request)
            try await validatePreviousOutputs(transaction, request: request)
            try validateFee(transaction: transaction, actualFeeSatoshis: feeSatoshis)
        }

        private func validateBinding(
            transaction: OpalBase.Transaction,
            request: OpalFusion.Host.MosaicTransactionSigningRequest
        ) throws {
            guard request.transcriptBinding.profile == profile else {
                throw Failure.incompatibleProfile
            }
            guard request.transcriptBinding.matches(
                unsignedTransactionBytes: request.unsignedTransactionBytes
            ),
                (try? transaction.encode()) == Data(request.unsignedTransactionBytes) else {
                throw Failure.invalidTranscriptBinding
            }
            guard request.transactionProfileIdentifier
                    == profile.transactionProfileIdentifier else {
                throw Failure.invalidTransactionProfile
            }
            guard contributionPolicy.accepts(
                feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: request.minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: request.maximumExcessFeeSatoshis,
                requiredExcessFeeSatoshis: request.requiredExcessFeeSatoshis
            ) else {
                throw Failure.invalidFeeTerms
            }
        }

        private func validateTransactionShape(
            _ transaction: OpalBase.Transaction,
            request: OpalFusion.Host.MosaicTransactionSigningRequest
        ) throws {
            guard transaction.version == 2 else {
                throw Failure.invalidVersion
            }
            guard transaction.lockTime == 0 else {
                throw Failure.invalidLockTime
            }
            guard transaction.inputs.count == request.spentInputs.count else {
                throw Failure.invalidInputCount
            }

            for index in transaction.inputs.indices {
                let input = transaction.inputs[index]
                let spentInput = request.spentInputs[index]
                guard input.unlockingScript.isEmpty,
                      input.previousTransactionHash.reverseOrder
                        == Data(spentInput.outpointTransactionHashBytes),
                      input.previousTransactionOutputIndex == spentInput.outpointIndex,
                      case .p2pkh_OPCHECKSIG(let publicKeyHash) = try? OpalBase.Script.decode(
                        lockingScript: Data(spentInput.lockingScriptBytes)
                      ) else {
                    throw Failure.invalidInput(index: index)
                }
                if let publicKeyBytes = spentInput.publicKey {
                    guard let publicKey = try? OpalBase.Key.PublicKey(
                        compressedData: Data(publicKeyBytes)
                    ), OpalBase.Key.PublicKey.Hash(publicKey: publicKey) == publicKeyHash else {
                        throw Failure.invalidInput(index: index)
                    }
                } else if request.localInputIndices.contains(index) {
                    throw Failure.invalidInput(index: index)
                }
                guard input.sequence == UInt32.max else {
                    throw Failure.invalidInputSequence(index: index)
                }
            }
            guard Self.inputsAreOrdered(transaction.inputs) else {
                throw Failure.invalidInputOrdering
            }

            for (index, output) in transaction.outputs.enumerated() {
                guard output.tokenData == nil,
                      case .p2pkh_OPCHECKSIG = try? OpalBase.Script.decode(
                        lockingScript: output.lockingScript
                      ) else {
                    throw Failure.invalidOutput(index: index)
                }
            }
            guard Self.outputsAreOrdered(transaction.outputs) else {
                throw Failure.invalidOutputOrdering
            }
        }

        private func validatePreviousOutputs(
            _ transaction: OpalBase.Transaction,
            request: OpalFusion.Host.MosaicTransactionSigningRequest
        ) async throws {
            for index in transaction.inputs.indices {
                let input = transaction.inputs[index]
                let rawTransaction: Data
                do {
                    rawTransaction = try await transactionReader.fetchRawTransaction(
                        for: input.previousTransactionHash
                    )
                } catch let cancellation as CancellationError {
                    throw cancellation
                } catch {
                    throw Failure.previousTransactionUnavailable(index: index)
                }

                guard OpalCrypto.Hashing.hash256(rawTransaction)
                        == input.previousTransactionHash.naturalOrder else {
                    throw Failure.previousTransactionHashMismatch(index: index)
                }

                let decoded: (transaction: OpalBase.Transaction, bytesRead: Int)
                do {
                    decoded = try OpalBase.Transaction.decode(from: rawTransaction)
                } catch {
                    throw Failure.invalidPreviousTransaction(index: index)
                }
                guard decoded.bytesRead == rawTransaction.count,
                      (try? decoded.transaction.encode()) == rawTransaction else {
                    throw Failure.invalidPreviousTransaction(index: index)
                }

                let outputIndex = Int(input.previousTransactionOutputIndex)
                guard decoded.transaction.outputs.indices.contains(outputIndex) else {
                    throw Failure.previousOutputUnavailable(index: index)
                }
                let previousOutput = decoded.transaction.outputs[outputIndex]
                let spentInput = request.spentInputs[index]
                guard previousOutput.value == spentInput.amountSatoshis,
                      previousOutput.lockingScript == Data(spentInput.lockingScriptBytes),
                      previousOutput.tokenData == nil else {
                    throw Failure.previousOutputMismatch(index: index)
                }
            }
        }

        private func validateFee(
            transaction: OpalBase.Transaction,
            actualFeeSatoshis: UInt64
        ) throws {
            let expectedFeeSatoshis = try transaction.calculateFee(feePerByte: 1)
            guard actualFeeSatoshis == expectedFeeSatoshis else {
                throw Failure.feeMismatch(
                    expected: expectedFeeSatoshis,
                    actual: actualFeeSatoshis
                )
            }
        }

        private static func inputsAreOrdered(
            _ inputs: [OpalBase.Transaction.Input]
        ) -> Bool {
            zip(inputs, inputs.dropFirst()).allSatisfy { lhs, rhs in
                let lhsHash = lhs.previousTransactionHash.reverseOrder
                let rhsHash = rhs.previousTransactionHash.reverseOrder
                if lhsHash != rhsHash {
                    return lhsHash.lexicographicallyPrecedes(rhsHash)
                }
                return lhs.previousTransactionOutputIndex
                    < rhs.previousTransactionOutputIndex
            }
        }

        private static func outputsAreOrdered(
            _ outputs: [OpalBase.Transaction.Output]
        ) -> Bool {
            zip(outputs, outputs.dropFirst()).allSatisfy { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                return !rhs.lockingScript.lexicographicallyPrecedes(lhs.lockingScript)
            }
        }
    }
}
#endif
