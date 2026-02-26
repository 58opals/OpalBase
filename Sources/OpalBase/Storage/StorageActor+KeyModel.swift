// StorageActor+KeyModel.swift

import Foundation

extension StorageActor {
    public enum KeyModel {
        case walletSnapshot
        case accountSnapshot(Data)
        case addressBookSnapshot(Data)
        case mnemonicCiphertext
        case custom(String)
        
        public var rawValue: String {
            switch self {
            case .walletSnapshot:
                return "wallet.snapshot"
            case .accountSnapshot(let identifier):
                return "account.snapshot." + identifier.base64EncodedString()
            case .addressBookSnapshot(let identifier):
                return "address-book.snapshot." + identifier.base64EncodedString()
            case .mnemonicCiphertext:
                return "mnemonic.enc"
            case .custom(let key):
                return key
            }
        }
    }
}

extension StorageActor.KeyModel: Sendable {}
