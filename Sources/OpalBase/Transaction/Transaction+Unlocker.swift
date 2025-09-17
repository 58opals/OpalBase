// Transaction+Unlocker.swift

import Foundation

extension Transaction {
    enum Unlocker {
        case p2pkh_CheckSig(hashType: Transaction.HashType = .all(anyoneCanPay: false))
        case p2pkh_CheckDataSig(message: Data)
    }
}

extension Transaction.Unlocker {
    func placeholderUnlockingScript(signatureFormat: ECDSA.SignatureFormat) -> Data {
        switch signatureFormat {
        case .ecdsa(.raw), .ecdsa(.compact):
            assertionFailure("OP_CHECKSIG or OP_CHECKDATASIG requires DER-encoded ECDSA. Use .ecdsa(.der) or .schnorr.")
        default:
            break
        }
        
        let publicKeyLength: Int = 33
        let coreSignatureLength: Int = {
            switch signatureFormat {
            case .ecdsa(.der):
                return 72
            case .schnorr:
                return 64
            case .ecdsa(.raw), .ecdsa(.compact):
                assertionFailure("Unsupported ECDSA format. Use .ecdsa(.der) or .schnorr.")
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
