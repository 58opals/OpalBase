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
        let publicKeyLength: Int = 33
        let coreSignatureLength: Int = {
            switch signatureFormat {
            case .ecdsa(.der):
                return 72
            case .ecdsa(.raw), .ecdsa(.compact), .schnorr:
                return 64
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
