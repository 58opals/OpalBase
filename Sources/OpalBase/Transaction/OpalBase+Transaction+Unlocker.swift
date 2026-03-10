// OpalBase+Transaction+Unlocker.swift

import Foundation
import OpalCrypto

extension _OpalBase.Transaction {
    public enum Unlocker: Sendable {
        case p2pkh_CheckSig(hashType: OpalBase.Transaction.HashType = .makeAll(anyoneCanPay: false))
        case p2pkh_CheckDataSig(message: Data)
    }
}

extension _OpalBase.Transaction.Unlocker {
    func makePlaceholderUnlockingScript(signatureFormat: OpalCrypto.Signature.Format) -> Data {
        if case .ecdsa(.raw) = signatureFormat {
            assertionFailure("OP_CHECKSIG or OP_CHECKDATASIG requires DER-encoded ECDSA. Use .ecdsa(.der) or .schnorr.")
        }
        
        let publicKeyLength: Int = 33
        let coreSignatureLength: Int = {
            switch signatureFormat {
            case .ecdsa(.der):
                return 72
            case .schnorr:
                return 64
            case .ecdsa(.raw):
                assertionFailure("Unsupported raw ECDSA format. Use .ecdsa(.der) or .schnorr.")
                return 72
            }
        }()
        
        switch self {
        case .p2pkh_CheckSig:
            let signatureWithType = Data(count: coreSignatureLength + 1)
            return Data.push(signatureWithType) + Data.push(Data(count: publicKeyLength))
        case .p2pkh_CheckDataSig(let message):
            return Data.push(Data(count: coreSignatureLength)) + Data.push(Data(count: message.count)) + Data.push(Data(count: publicKeyLength))
        }
    }
}
