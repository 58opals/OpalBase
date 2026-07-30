// OpalBase+ReusablePaymentAddress+Payment.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// A Cash Code v1 payment destination derived for one sender input.
    public struct Payment: Sendable, Hashable {
        /// The fixed non-hardened child index used by Cash Code v1.
        public let childIndex: UInt32

        /// The compressed public key controlling the payment output.
        public let receivingPublicKey: OpalBase.Key.PublicKey

        /// The exact P2PKH locking bytecode for the payment output.
        public let lockingScript: Data

        init(receivingPublicKey: OpalBase.Key.PublicKey) {
            self.childIndex = CashCodeDerivation.childIndex
            self.receivingPublicKey = receivingPublicKey
            self.lockingScript = CashCodeDerivation.makeLockingScript(
                for: receivingPublicKey
            )
        }
    }
}

extension _OpalBase.ReusablePaymentAddress {
    /// Derives the Cash Code v1 payment destination designated by a sender
    /// input.
    ///
    /// The input signing key and outpoint must belong to the same transaction
    /// input. OpalBase cannot establish that correspondence without the
    /// sender's transaction-building context.
    public func derivePayment(
        from senderInputSigningKey: OpalBase.Key.SigningKey,
        spending outpoint: OpalBase.Transaction.Outpoint
    ) throws -> Payment {
        guard profile == .cashCodeV1 else {
            throw Error.unsupportedProfile(profile)
        }

        do {
            let sharedPointDigest = try CashCodeDerivation
                .makeSharedPointDigest(
                    signingKey: senderInputSigningKey,
                    publicKey: scanPublicKey
                )
            let receivingPublicKey = try CashCodeDerivation.derivePublicKey(
                from: spendPublicKey,
                sharedPointDigest: sharedPointDigest,
                outpoint: outpoint
            )
            return Payment(receivingPublicKey: receivingPublicKey)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.childKeyDerivationFailed
        }
    }
}
