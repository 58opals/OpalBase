// OpalBase.swift

import Foundation

public enum OpalBase {
    public static let version = "0.2.0"
}

extension OpalBase {
    public enum Error: Swift.Error {
        case mnemonicFailure(Swift.Error)
        case missingStorageLocation
    }
}

extension OpalBase {
    public static func bootstrap(storage: StorageConfiguration, network: NetworkPolicy) async throws -> any WalletCore {
        if !storage.isMemoryOnly && storage.appGroupContainer == nil { throw Error.missingStorageLocation }
        
        do {
            let mnemonic = try Mnemonic()
            return Wallet(mnemonic: mnemonic)
        } catch {
            throw Error.mnemonicFailure(error)
        }
    }
}
