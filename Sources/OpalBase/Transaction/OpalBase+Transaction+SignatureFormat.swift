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

extension _OpalBase.Transaction.SignatureFormat {
    var opalCryptoFormat: OpalCrypto.Signature.Format {
        switch self {
        case .ecdsa(.der):
            return .ecdsa(.der)
        case .ecdsa(.raw):
            return .ecdsa(.raw)
        case .schnorr:
            return .schnorr
        }
    }
}
