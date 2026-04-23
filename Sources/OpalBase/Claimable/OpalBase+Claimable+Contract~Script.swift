// OpalBase+Claimable+Contract~Script.swift

import Foundation

extension _OpalBase.Claimable.Contract {
    public var redeemScriptData: Data {
        var redeemScriptData = Data()
        redeemScriptData.append(ScriptOperationCode._IF.data)
        redeemScriptData.append(makeClaimableP2PKHScriptData(publicKeyHash: claimPublicKeyHash))
        redeemScriptData.append(ScriptOperationCode._ELSE.data)
        redeemScriptData.append(makeClaimableScriptNumberOperationData(for: expiryBlockHeight))
        redeemScriptData.append(ScriptOperationCode._CHECKLOCKTIMEVERIFY.data)
        redeemScriptData.append(ScriptOperationCode._DROP.data)
        redeemScriptData.append(makeClaimableP2PKHScriptData(publicKeyHash: refundPublicKeyHash))
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

private func makeClaimableP2PKHScriptData(publicKeyHash: Data) -> Data {
    var lockingScriptData = Data()
    lockingScriptData.append(ScriptOperationCode._DUP.data)
    lockingScriptData.append(ScriptOperationCode._HASH160.data)
    lockingScriptData.append(ScriptOperationCode._PUSHBYTES_20.data)
    lockingScriptData.append(publicKeyHash)
    lockingScriptData.append(ScriptOperationCode._EQUALVERIFY.data)
    lockingScriptData.append(ScriptOperationCode._CHECKSIG.data)
    return lockingScriptData
}
