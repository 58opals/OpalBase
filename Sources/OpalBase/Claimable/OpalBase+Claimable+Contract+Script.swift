// OpalBase+Claimable+Contract+Script.swift

import Foundation

extension _OpalBase.Claimable.Contract {
    public var redeemScriptData: Data {
        var redeemScriptData = Data()
        redeemScriptData.append(ScriptOperationCode._IF.data)
        redeemScriptData.append(OpalBase.Script.p2pkh_OPCHECKSIG(hash: .init(claimPublicKeyHash)).data)
        redeemScriptData.append(ScriptOperationCode._ELSE.data)
        redeemScriptData.append(ClaimablePrimitiveOperation.makeScriptNumberOperationData(for: expiryBlockHeight))
        redeemScriptData.append(ScriptOperationCode._CHECKLOCKTIMEVERIFY.data)
        redeemScriptData.append(ScriptOperationCode._DROP.data)
        redeemScriptData.append(OpalBase.Script.p2pkh_OPCHECKSIG(hash: .init(refundPublicKeyHash)).data)
        redeemScriptData.append(ScriptOperationCode._ENDIF.data)
        return redeemScriptData
    }

    public var fundingScriptHashData: Data {
        OpalCryptoAdapter.hash160(redeemScriptData)
    }

    public var fundingLockingScriptData: Data {
        OpalBase.Script.p2sh(scriptHash: fundingScriptHashData).data
    }
}
