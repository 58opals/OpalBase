// OpalBase+Transaction+Output+Fingerprint.swift

import Foundation

extension _OpalBase.Transaction.Output {
    struct Fingerprint: Hashable {
        let lockingScript: Data
        let value: UInt64
        let tokenData: OpalBase.CashTokens.TokenData?
    }

    struct OrderingFingerprint: Hashable {
        let lockingScript: Data
        let tokenData: OpalBase.CashTokens.TokenData?
    }
}

extension _OpalBase.Transaction.Output {
    var fingerprint: OpalBase.Transaction.Output.Fingerprint {
        .init(lockingScript: lockingScript, value: value, tokenData: tokenData)
    }

    var orderingFingerprint: OpalBase.Transaction.Output.OrderingFingerprint {
        .init(lockingScript: lockingScript, tokenData: tokenData)
    }
}
