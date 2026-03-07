// ECDSAModel+SignatureFormat.swift

import Foundation

extension ECDSAModel {
    public enum SignatureFormat: Sendable {
        /// Signature wire-format used by signing and verification.
        /// - Note:
        ///   - **OP_CHECKSIG + ECDSAModel requires DER**. Using `.raw` or `.compact` with CHECKSIG is invalid at consensus.
        ///   - SchnorrModel is allowed for CHECKSIG as per BCH consensus.
        case ecdsa(ECDSA)
        case schnorr // Bitcoin Cash SchnorrModel (May 2019+).
        
        public enum ECDSA: Sendable {
            case raw
            case compact
            case der
        }
    }
}
