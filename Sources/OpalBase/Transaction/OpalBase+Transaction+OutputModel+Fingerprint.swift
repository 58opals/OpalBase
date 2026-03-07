// OpalBase+Transaction+OutputModel+Fingerprint.swift

import Foundation

extension _OpalBase.Transaction.OutputModel {
    struct Fingerprint: Hashable {
        let lockingScript: Data
        let value: UInt64
        let tokenData: OpalBase.CashTokens.TokenData?
    }
}

extension _OpalBase.Transaction.OutputModel {
    var fingerprint: OpalBase.Transaction.OutputModel.Fingerprint {
        .init(lockingScript: lockingScript, value: value, tokenData: tokenData)
    }
}
