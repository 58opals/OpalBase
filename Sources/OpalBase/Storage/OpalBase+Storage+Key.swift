// OpalBase+Storage+Key.swift

import Foundation

extension _OpalBase.Storage {
    public enum Key {
        case walletSnapshot
        case walletSnapshotGeneration(String)
        case walletSnapshotCommittedGeneration
        case accountSnapshot(Data)
        case addressBookSnapshot(Data)
        case mnemonicCiphertext
        case mnemonicCiphertextGeneration(String)
        case custom(String)
        
        public var rawValue: String {
            switch self {
            case .walletSnapshot:
                return "wallet.snapshot"
            case .walletSnapshotGeneration(let generation):
                return "wallet.snapshot." + generation
            case .walletSnapshotCommittedGeneration:
                return "wallet.snapshot.committed"
            case .accountSnapshot(let identifier):
                return "account.snapshot." + identifier.base64EncodedString()
            case .addressBookSnapshot(let identifier):
                return "address-book.snapshot." + identifier.base64EncodedString()
            case .mnemonicCiphertext:
                return "mnemonic.enc"
            case .mnemonicCiphertextGeneration(let generation):
                return "mnemonic.enc." + generation
            case .custom(let key):
                return key
            }
        }
    }
}

extension _OpalBase.Storage.Key: Sendable {}
