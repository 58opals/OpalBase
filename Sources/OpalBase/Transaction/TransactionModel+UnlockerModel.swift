// TransactionModel+UnlockerModel.swift

import Foundation
import OpalCrypto

extension TransactionModel {
    public enum UnlockerModel: Sendable {
        case p2pkh_CheckSig(hashType: TransactionModel.HashTypeModel = .makeAll(anyoneCanPay: false))
        case p2pkh_CheckDataSig(message: Data)
    }
}

extension TransactionModel.UnlockerModel {
    func makePlaceholderUnlockingScript(signatureFormat: EllipticCurveDigitalSignatureAlgorithmModel.SignatureFormatModel) -> Data {
        switch signatureFormat {
        case .ecdsa(.raw), .ecdsa(.compact):
            assertionFailure("OP_CHECKSIG or OP_CHECKDATASIG requires DERModel-encoded EllipticCurveDigitalSignatureAlgorithmModel. Use .ecdsa(.distinguishedEncodingRules) or .schnorr (BCH).")
        default:
            break
        }
        
        let publicKeyLength: Int = 33
        let coreSignatureLength: Int = {
            switch signatureFormat {
            case .ecdsa(.distinguishedEncodingRules):
                return 72
            case .schnorr:
                return 64
            case .ecdsa(.raw), .ecdsa(.compact):
                assertionFailure("Unsupported EllipticCurveDigitalSignatureAlgorithmModel format. Use .ecdsa(.distinguishedEncodingRules) or .schnorr (BCH).")
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
