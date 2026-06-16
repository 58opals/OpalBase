// ClaimablePrimitiveOperation.swift

import Foundation
import OpalCrypto

enum ClaimablePrimitiveOperation {
    static func makeCompressedPublicKey(
        from privateKey: Data,
        invalidError: OpalBase.Claimable.Error
    ) throws -> Data {
        do {
            let typedPrivateKey = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKey)
            return try OpalCrypto.Secp256k1.derivePublicKey(from: typedPrivateKey).rawRepresentation
        } catch {
            throw invalidError
        }
    }

    static func makePublicKeyHash(
        from privateKey: Data,
        invalidError: OpalBase.Claimable.Error
    ) throws -> Data {
        OpalCryptoAdapter.hash160(
            try makeCompressedPublicKey(from: privateKey, invalidError: invalidError)
        )
    }

    static func makeQueryScriptHashHex(from lockingScript: Data) -> String {
        OpalCryptoAdapter.sha256(lockingScript).reversedData.hexadecimalString
    }

    static func makeWalletImportFormat(
        privateKey: Data,
        network: OpalBase.Network.Environment
    ) throws -> String {
        do {
            _ = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKey)
        } catch {
            throw OpalBase.Claimable.Error.invalidClaimPrivateKey
        }

        var payload = Data([makeWalletImportFormatVersion(for: network)])
        payload.append(privateKey)
        payload.append(0x01)
        let checksum = Data(OpalCryptoAdapter.hash256(payload).prefix(4))
        return OpalCryptoAdapter.encodeBase58(payload + checksum)
    }

    static func makeScriptNumberOperationData(for value: UInt32) -> Data {
        switch value {
        case 0:
            return ScriptOperationCode._0.data
        case 1...16:
            let rawValue = UInt8(Int(ScriptOperationCode._1.rawValue) + Int(value) - 1)
            return ScriptOperationCode(rawValue: rawValue)!.data
        default:
            var remainingValue = value
            var scriptNumberData = Data()
            while remainingValue > 0 {
                scriptNumberData.append(UInt8(remainingValue & 0xff))
                remainingValue >>= 8
            }
            if let lastByte = scriptNumberData.last, lastByte & 0x80 != 0 {
                scriptNumberData.append(0)
            }
            return Data.push(scriptNumberData)
        }
    }

    private static func makeWalletImportFormatVersion(
        for network: OpalBase.Network.Environment
    ) -> UInt8 {
        switch network {
        case .mainnet:
            return 0x80
        case .chipnet, .testnet:
            return 0xef
        }
    }
}
