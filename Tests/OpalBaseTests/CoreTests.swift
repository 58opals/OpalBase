import Foundation
import CryptoKit
import Testing
@testable import OpalBase

@Suite("OpalBase Core")
struct OpalBaseCoreTests {
    // Fixture: BIP39 English 12-word
    static let words: [String] = [
        "abandon","abandon","abandon","abandon","abandon","abandon",
        "abandon","abandon","abandon","abandon","abandon","about"
    ]
    
    // MARK: Mnemonic
    
    @Test("Mnemonic → seed determinism and passphrase")
    func mnemonic_seed_determinism() throws {
        let m1 = try Mnemonic(words: Self.words)
        let m2 = try Mnemonic(words: Self.words)
        #expect(m1.seed == m2.seed)
        #expect(m1.seed.count == 64)
        
        let m3 = try Mnemonic(words: Self.words, passphrase: "opal")
        #expect(m1.seed != m3.seed)
    }
    
    // MARK: Derivation Path
    
    @Test("BIP44 BCH derivation path formatting")
    func derivation_path_format() throws {
        let p0 = try DerivationPath(account: .init(rawIndexInteger: 0), usage: .receiving, index: 0)
        #expect(p0.path == "m/44'/145'/0'/0/0")
        
        let p1 = try DerivationPath(account: .init(rawIndexInteger: 0), usage: .change, index: 2)
        #expect(p1.path == "m/44'/145'/0'/1/2")
    }
    
    // MARK: Keys ↔ Address ↔ Script
    
    @Test("Key derivation → P2PKH address → roundtrip parse")
    func address_roundtrip() throws {
        let m = try Mnemonic(words: Self.words)
        let root = PrivateKey.Extended(rootKey: try .init(seed: m.seed))
        
        let path = try DerivationPath(account: .init(rawIndexInteger: 0), usage: .receiving, index: 0)
        let child = try root.deriveChild(at: path)
        let priv = try PrivateKey(data: child.privateKey)
        let pub = try PublicKey(privateKey: priv)
        
        let script = Script.p2pkh_OPCHECKSIG(hash: .init(publicKey: pub))
        let cash = try Address(script: script)
        #expect(cash.string.hasPrefix("bitcoincash:"))
        
        let parsed = try Address(cash.string)
        #expect(parsed.lockingScript == cash.lockingScript)
        
        // Legacy Base58 for P2PKH
        let legacy = try Address.Legacy(script)
        #expect(!legacy.string.isEmpty)
        
        // Script decode and derivability checks
        #expect(try Script.decode(lockingScript: cash.lockingScript.data) == script)
        #expect(script.isDerivableFromAddress == true)
        #expect(Script.p2pk(publicKey: pub).isDerivableFromAddress == false)
    }
    
    // MARK: Formats
    
    @Test("xprv encode/decode and WIF roundtrip")
    func formats_roundtrip() throws {
        let m = try Mnemonic(words: Self.words)
        let root = PrivateKey.Extended(rootKey: try .init(seed: m.seed))
        
        let xprv = root.address
        let decoded = try PrivateKey.Extended(xprv: xprv)
        #expect(decoded == root)
        
        let pk = try PrivateKey(data: root.privateKey)
        let wif = pk.wif
        let pk2 = try PrivateKey(wif: wif)
        #expect(pk2 == pk)
    }
    
    // MARK: Build + Sign P2PKH
    
    @Test("Build and sign single-input P2PKH tx")
    func build_and_sign_p2pkh() throws {
        let m = try Mnemonic(words: Self.words)
        let root = PrivateKey.Extended(rootKey: try .init(seed: m.seed))
        
        // From address (m/44'/145'/0'/0/0)
        let fromPath = try DerivationPath(account: .init(rawIndexInteger: 0), usage: .receiving, index: 0)
        let fromChild = try root.deriveChild(at: fromPath)
        let fromPriv = try PrivateKey(data: fromChild.privateKey)
        let fromPub = try PublicKey(privateKey: fromPriv)
        let fromScript = Script.p2pkh_OPCHECKSIG(hash: .init(publicKey: fromPub))
        let fromAddr = try Address(script: fromScript)
        
        // UTXO locked to fromAddr
        let utxo = Transaction.Output.Unspent(
            value: 200_000,
            lockingScript: fromAddr.lockingScript.data,
            previousTransactionHash: .init(naturalOrder: Data(repeating: 1, count: 32)),
            previousTransactionOutputIndex: 0
        )
        
        // Recipient (m/44'/145'/0'/0/1)
        let toPath = try DerivationPath(account: .init(rawIndexInteger: 0), usage: .receiving, index: 1)
        let toChild = try root.deriveChild(at: toPath)
        let toPriv = try PrivateKey(data: toChild.privateKey)
        let toPub = try PublicKey(privateKey: toPriv)
        let toAddr = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: toPub)))
        
        // Change (m/44'/145'/0'/1/0)
        let chPath = try DerivationPath(account: .init(rawIndexInteger: 0), usage: .change, index: 0)
        let chChild = try root.deriveChild(at: chPath)
        let chPriv = try PrivateKey(data: chChild.privateKey)
        let chPub = try PublicKey(privateKey: chPriv)
        let chAddr = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: chPub)))
        
        let outputs = [Transaction.Output(value: 60_000, address: toAddr)]
        let change = Transaction.Output(value: 140_000, address: chAddr)
        
        let tx = try Transaction.build(
            utxoPrivateKeyPairs: [utxo: fromPriv],
            recipientOutputs: outputs,
            changeOutput: change,
            signatureFormat: .ecdsa(.der),
            feePerByte: 1
        )
        
        #expect(!tx.inputs.isEmpty)
        
        // Unlocking script structure: <sig+type> <33-byte pubkey>
        let unlocking = tx.inputs[0].unlockingScript
        try #require(!unlocking.isEmpty)
        
        let sigLen = Int(unlocking[0])
        #expect(sigLen >= 70 && sigLen <= 73)
        let sigWithType = unlocking[1 ..< 1 + sigLen]
        #expect(sigWithType.last == 0x41) // SIGHASH_ALL | FORKID
        
        let pubOff = 1 + sigLen
        let pubLen = Int(unlocking[pubOff])
        #expect(pubLen == 33)
        let pubKeyPushed = unlocking[(pubOff + 1) ..< (pubOff + 1 + pubLen)]
        #expect(pubKeyPushed.count == 33)
    }
    
    // MARK: Satoshi math
    
    @Test("Satoshi arithmetic and guards")
    func satoshi_math() throws {
        let a = try Satoshi(1_000)
        let b = try Satoshi(2_000)
        #expect(try (a + b).uint64 == 3_000)
        #expect(try (b - a).uint64 == 1_000)
        #expect(throws: Satoshi.Error.negativeResult) { _ = try a - b }
    }
    
    // MARK: Wallet snapshot I/O
    
    @Test("Wallet snapshot save/load, plain and encrypted")
    func wallet_snapshot_io() async throws {
        let m = try Mnemonic(words: Self.words)
        let wallet = Wallet(mnemonic: m)
        
        // Plain
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let plain = dir.appendingPathComponent("opal_wallet_plain.json")
        try? FileManager.default.removeItem(at: plain)
        try await wallet.saveSnapshot(to: plain, using: nil)
        
        let w1 = Wallet(mnemonic: m)
        try await w1.loadSnapshot(from: plain, using: nil)
        #expect(await w1.accounts.isEmpty)
        
        // Encrypted
        let key = SymmetricKey(size: .bits256)
        let enc = dir.appendingPathComponent("opal_wallet_enc.bin")
        try? FileManager.default.removeItem(at: enc)
        try await wallet.saveSnapshot(to: enc, using: key)
        
        let w2 = Wallet(mnemonic: m)
        try await w2.loadSnapshot(from: enc, using: key)
        #expect(await w2.accounts.isEmpty)
    }
    
    // MARK: Address book gap logic
    
    @Test("Address.Book gap extension when marking used")
    func address_book_gap_extension() async throws {
        let m = try Mnemonic(words: Self.words)
        let root = PrivateKey.Extended(rootKey: try .init(seed: m.seed))
        
        let book = try await Address.Book(
            rootExtendedPrivateKey: root,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0)
        )
        
        let initialCount = await book.listEntries(for: .receiving).count
        #expect(initialCount > 0)
        
        let next = try await book.selectNextEntry(for: .receiving)
        let gap = await book.gapLimit
        try await book.mark(address: next.address, isUsed: true)
        
        let afterCount = await book.listEntries(for: .receiving).count
        #expect(afterCount == initialCount + gap)
    }
}
