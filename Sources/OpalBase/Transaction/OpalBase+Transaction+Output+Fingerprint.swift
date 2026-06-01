// OpalBase+Transaction+Output+Fingerprint.swift

import Foundation

extension _OpalBase.Transaction.Output {
    struct Fingerprint: Hashable {
        let lockingScript: Data
        let value: UInt64
        let tokenData: OpalBase.CashTokens.TokenData?

        init(
            lockingScript: Data,
            value: UInt64,
            tokenData: OpalBase.CashTokens.TokenData?
        ) {
            self.lockingScript = Data(lockingScript)
            self.value = value
            self.tokenData = tokenData
        }
    }

    struct OrderingFingerprint: Hashable {
        let lockingScript: Data
        let tokenData: OpalBase.CashTokens.TokenData?

        init(
            lockingScript: Data,
            tokenData: OpalBase.CashTokens.TokenData?
        ) {
            self.lockingScript = Data(lockingScript)
            self.tokenData = tokenData
        }
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

extension _OpalBase.Transaction.Output.Fingerprint {
    var orderingFingerprint: OpalBase.Transaction.Output.OrderingFingerprint {
        .init(lockingScript: lockingScript, tokenData: tokenData)
    }
}
