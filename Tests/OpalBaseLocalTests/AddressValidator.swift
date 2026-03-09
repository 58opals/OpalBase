// AddressValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("CashAddr", .tags(.unit, .address))
struct AddressValidator {
    @Test("known private key derives stable wallet and address artifacts")
    func deriveStableWalletAndAddressArtifacts() throws {
        let privateKey = try OpalBase.PrivateKey(data: Data(repeating: 0x00, count: 31) + Data([0x01]))
        let walletImportFormat = privateKey.makeWalletImportFormat(
            compression: OpalBase.PrivateKey.WalletImportFormatCompression.compressed
        )
        let publicKey = try OpalBase.PublicKey(privateKey: privateKey)
        let hash = OpalBase.PublicKey.Hash(publicKey: publicKey)
        let script = OpalBase.Script.p2pkh_OPCHECKSIG(hash: hash)
        let legacyAddress = try OpalBase.Address.LegacyModel(script)
        let address = try OpalBase.Address(script: script)

        #expect(walletImportFormat == "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn")
        #expect(legacyAddress.string == "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH")
        #expect(address.lockingScript.data == script.data)
        #expect(try OpalBase.Address(address.string).lockingScript.data == script.data)
    }
    
    @Test("cash address decodes to P2PKH script")
    func decodeCashAddressToP2PKHScript() throws {
        let cashaddr = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try OpalBase.Address(cashaddr)
        #expect(address.string == cashaddr)
        
        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
    }
    
    @Test("cash address accepts uppercase payload")
    func decodeCashAddressWithUppercasePayload() throws {
        let cashaddr = "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let address = try OpalBase.Address(cashaddr)
        #expect(address.string == cashaddr)
        
        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
    }
    
    @Test("mixed-case cash address payload is rejected")
    func rejectMixedCaseCashAddressPayload() {
        let mixedCasePayload = "qpm2qsznHks23z7629mms6s4cwef74vcwvy22gdx6a"
        
        #expect(throws: OpalBase.Address.Error.invalidCashAddressFormat) {
            _ = try OpalBase.Address(mixedCasePayload)
        }
    }
    
    @Test("cash address accepts uppercase prefix")
    func decodeCashAddressWithUppercasePrefix() throws {
        let cashaddr = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try OpalBase.Address(cashaddr)
        #expect(address.string == cashaddr)
        
        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
    }
    
    @Test("filter removes invalid characters")
    func filterRemovesInvalidCharacters() {
        let noisy = "BITCOINCASH:QPM2-QSZN HK S23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let filtered = OpalBase.Address.filterBase32(from: noisy)
        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }
    
    @Test("filter normalizes uppercase base32 payloads", .tags(.unit))
    func filterBase32LowercasesUppercaseCharacters() {
        #expect(OpalBase.Address.filterBase32(from: "BITCOINCASH:QPY0") == "qpy0")
        #expect(OpalBase.Address.filterBase32(from: "BITCOINCASH:QPZA") == "qpza")
        #expect(
            OpalBase.Address.filterBase32(from: "BITCOINCASH:QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A") ==
                "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        )
    }
    
    @Test("invalid checksum is rejected")
    func rejectInvalidChecksum() {
        let invalid = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
        #expect(throws: OpalBase.Address.Error.invalidChecksum) {
            _ = try OpalBase.Address(invalid)
        }
    }
    
    @Test("address book only replenishes the gap deficit")
    func addressBookMaintainsGapLimit() async throws {
        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        let account = try OpalBase.DerivationPath.Account(rawIndexInteger: 0)
        let gapLimit = 5
        let book = try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            gapLimit: gapLimit
        )
        
        let initialTotal = await book.countEntries(for: .receiving)
        #expect(initialTotal == gapLimit)
        
        let entries = await book.listEntries(for: .receiving)
        let firstEntry = try #require(entries.first)
        try await book.mark(address: firstEntry.address, isUsed: true)
        
        let updatedTotal = await book.countEntries(for: .receiving)
        let updatedUnused = await book.countUnusedEntries(for: .receiving)
        
        #expect(updatedTotal == initialTotal + 1)
        #expect(updatedUnused == gapLimit)
    }
    
    @Test("address book uses distinct receiving and change addresses")
    func addressBookUsesDistinctReceivingAndChangeAddresses() async throws {
        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        let account = try OpalBase.DerivationPath.Account(rawIndexInteger: 0)
        let book = try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            gapLimit: 1
        )
        
        let receivingEntry = try #require(await book.listEntries(for: .receiving).first)
        let changeEntry = try #require(await book.listEntries(for: .change).first)
        
        #expect(receivingEntry.address != changeEntry.address)
    }
}
