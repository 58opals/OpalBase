// OpalBase+Network+TransactionReader~Mosaic.swift

#if os(macOS)
import Foundation
import OpalCrypto
import OpalFusion

extension _OpalBase.Network.TransactionReader {
    enum MosaicPreviousOutputResolutionFailure:
        Swift.Error,
        Sendable,
        Equatable
    {
        case previousTransactionUnavailable(index: Int)
        case previousTransactionHashMismatch(index: Int)
        case invalidPreviousTransaction(index: Int)
        case previousOutputUnavailable(index: Int)
    }
}

extension _OpalBase.Network.TransactionReader:
    OpalFusion.Host.MosaicPreviousOutputSource
{
    public func resolvePreviousOutputs(
        for requests: [OpalFusion.Host.MosaicPreviousOutputRequest]
    ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
        var resolvedOutputs: [OpalFusion.Host.MosaicPreviousOutput] = []
        resolvedOutputs.reserveCapacity(requests.count)

        for (index, request) in requests.enumerated() {
            try Task.checkCancellation()
            let transactionHash = OpalBase.Transaction.Hash(
                reverseOrder: Data(request.transactionHashBytes)
            )
            let rawTransaction: Data
            do {
                rawTransaction = try await fetchRawTransaction(
                    for: transactionHash
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                throw MosaicPreviousOutputResolutionFailure
                    .previousTransactionUnavailable(index: index)
            }
            try Task.checkCancellation()

            guard OpalCrypto.Hashing.hash256(rawTransaction)
                    == transactionHash.naturalOrder else {
                throw MosaicPreviousOutputResolutionFailure
                    .previousTransactionHashMismatch(index: index)
            }

            let decoded: (
                transaction: OpalBase.Transaction,
                bytesRead: Int
            )
            do {
                decoded = try OpalBase.Transaction.decode(
                    from: rawTransaction
                )
            } catch {
                throw MosaicPreviousOutputResolutionFailure
                    .invalidPreviousTransaction(index: index)
            }
            guard decoded.bytesRead == rawTransaction.count,
                  (try? decoded.transaction.encode()) == rawTransaction else {
                throw MosaicPreviousOutputResolutionFailure
                    .invalidPreviousTransaction(index: index)
            }

            let outputIndex = Int(request.outputIndex)
            guard decoded.transaction.outputs.indices.contains(outputIndex)
            else {
                throw MosaicPreviousOutputResolutionFailure
                    .previousOutputUnavailable(index: index)
            }
            let output = decoded.transaction.outputs[outputIndex]
            resolvedOutputs.append(
                try .init(
                    transactionHashBytes: request.transactionHashBytes,
                    outputIndex: request.outputIndex,
                    amountSatoshis: output.value,
                    lockingScriptBytes: [UInt8](output.lockingScript),
                    tokenState: output.tokenData == nil ? .absent : .present
                )
            )
        }

        return resolvedOutputs
    }
}
#endif
