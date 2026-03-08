// OpalBase+Cryptography+SignatureFormat.swift

import Foundation

extension _OpalBase.Cryptography {
    public enum SignatureFormat: Sendable {
        /// Signature wire-format used by signing and verification.
        /// - Note:
        ///   - **OP_CHECKSIG + OpalBase.Cryptography.ECDSA requires DER**. Using `.raw` or `.compact` with CHECKSIG is invalid at consensus.
        ///   - OpalBase.Cryptography.Schnorr is allowed for CHECKSIG as per BCH consensus.
        case ecdsa(ECDSA)
        case schnorr // Bitcoin Cash OpalBase.Cryptography.Schnorr (May 2019+).
        
        public enum ECDSA: Sendable {
            case raw
            case compact
            case der
        }
    }
}
