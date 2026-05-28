// OpalBase+Transaction+SignatureFormat.swift

import Foundation
import OpalCrypto

extension _OpalBase.Transaction {
    public enum SignatureFormat: Sendable, Equatable {
        public enum ECDSAEncoding: Sendable, Equatable {
            case der
            case raw
        }

        case ecdsa(ECDSAEncoding)
        case schnorr
    }
}

extension _OpalBase.Transaction.SignatureFormat.ECDSAEncoding {
    var opalCryptoFormat: OpalCrypto.Signature.ECDSAFormat {
        switch self {
        case .der:
            return .der
        case .raw:
            return .raw
        }
    }
}
