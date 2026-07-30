// OpalBase+ReusablePaymentAddress+Match.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// A Cash Code v1 output match and the opaque capability required to spend
    /// it.
    ///
    /// The retained output is the original decoded transaction output. Its
    /// value and CashToken data are not reconstructed or discarded. A match is
    /// not an unspent transaction output until unspent status is established
    /// separately.
    public struct Match: Sendable {
        /// The hash of the transaction containing the matching output.
        public let transactionHash: OpalBase.Transaction.Hash

        /// The qualifying transaction-input position used for derivation.
        public let qualifyingInputIndex: UInt32

        /// The fixed non-hardened child index used by Cash Code v1.
        public let childIndex: UInt32

        /// The position of the matching transaction output.
        public let outputIndex: UInt32

        /// The original decoded output, including any CashToken data.
        public let output: OpalBase.Transaction.Output

        /// The compressed public key controlling the matching output.
        public let receivingPublicKey: OpalBase.Key.PublicKey

        /// The opaque signing capability controlling the matching output.
        public let receivingSigningKey: OpalBase.Key.SigningKey

        init(
            transactionHash: OpalBase.Transaction.Hash,
            qualifyingInputIndex: UInt32,
            outputIndex: UInt32,
            output: OpalBase.Transaction.Output,
            receivingSigningKey: OpalBase.Key.SigningKey
        ) {
            self.transactionHash = transactionHash
            self.qualifyingInputIndex = qualifyingInputIndex
            self.childIndex = CashCodeDerivation.childIndex
            self.outputIndex = outputIndex
            self.output = output
            self.receivingPublicKey = receivingSigningKey.publicKey
            self.receivingSigningKey = receivingSigningKey
        }
    }
}
