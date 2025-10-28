// Storage+Mnemonic.swift

import Foundation

extension Storage {
    public struct MnemonicStore: Sendable {
        private struct Payload: Codable {
            var words: [String]
            var passphrase: String
        }
        
        private let secureStore: SecureStore
        private let accountName: String
        
        public init(secureStore: SecureStore, accountName: String = "wallet-mnemonic.v1") {
            self.secureStore = secureStore
            self.accountName = accountName
        }
        
        public func saveMnemonic(_ mnemonic: Mnemonic) throws {
            let payload = Payload(words: mnemonic.words, passphrase: mnemonic.passphrase)
            let data = try JSONEncoder().encode(payload)
            try secureStore.saveValue(data, forAccount: accountName)
        }
        
        public func loadMnemonic() throws -> Mnemonic? {
            guard let data = try secureStore.loadValue(forAccount: accountName) else { return nil }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return try Mnemonic(words: payload.words, passphrase: payload.passphrase)
        }
        
        public func removeMnemonic() throws {
            try secureStore.removeValue(forAccount: accountName)
        }
        
        public func hasMnemonic() throws -> Bool {
            try secureStore.hasValue(forAccount: accountName)
        }
    }
}
