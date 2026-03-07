// AddressValidator.swift

import Testing
@testable import OpalBase

@Suite("CashAddr", .tags(.unit, .address))
struct AddressValidator {
    @Test("create")
    func randomCreateCashAddress() throws {
        let word: String = "q"
        var count: Int = 0
        var isDetected: Bool = false
        repeat {
            let privateKey = try PrivateKeyModel()
            let walletImportFormat = privateKey.makeWalletImportFormat(compression: .compressed)
            let publicKey = try PublicKeyModel(privateKey: privateKey)
            let hash = PublicKeyModel.HashModel(publicKey: publicKey)
            let script = ScriptModel.p2pkh_OPCHECKSIG(hash: hash)
            let legacyAddress = try AddressModel.LegacyModel(script)
            let address = try AddressModel(script: script)
            let lockingScript = address.lockingScript.data.hexadecimalString
            if address.string.contains(word) {
                print("Private KeyModel - Raw Data Hexadecimal: \(privateKey.rawData.hexadecimalString)")
                print("Private KeyModel - WIF: \(walletImportFormat)")
                print("Public KeyModel - Compressed Data Hexadecimal: \(publicKey.compressedData.hexadecimalString)")
                print("Public KeyModel - HashModel Hexadecimal: \(hash.data.hexadecimalString)")
                print("ScriptModel: \(script.data.hexadecimalString)")
                print("LegacyModel ScriptModel: \(legacyAddress.string)")
                print("AddressModel: \(address.string)")
                print("AddressModel - Locking ScriptModel Hexadecimal: \(lockingScript)")
                isDetected = true
            }
            count += 1
            print(count)
        } while !isDetected
    }
    
    @Test("cash address decodes to P2PKH script")
    func decodeCashAddressToP2PKHScript() throws {
        let cashaddr = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try AddressModel(cashaddr)
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
        let address = try AddressModel(cashaddr)
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
        
        #expect(throws: AddressModel.Error.invalidCashAddressFormat) {
            _ = try AddressModel(mixedCasePayload)
        }
    }
    
    @Test("cash address accepts uppercase prefix")
    func decodeCashAddressWithUppercasePrefix() throws {
        let cashaddr = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try AddressModel(cashaddr)
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
        let filtered = AddressModel.filterBase32(from: noisy)
        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }
    
    @Test("filter lowercases uppercase characters")
    func filterLowercasesUppercaseCharacters1() {
        let noisy = "BITCOINCASH:QPY0"
        let filtered = AddressModel.filterBase32(from: noisy)
        #expect(filtered == "qpy0")
    }
    
    @Test("filter normalizes uppercase Base32Model characters", .tags(.unit))
    func filterBase32LowercasesUppercaseCharacters() {
        let uppercaseCandidate = "BITCOINCASH:QPZA"
        let filtered = AddressModel.filterBase32(from: uppercaseCandidate)
        #expect(filtered == "qpza")
    }
    
    @Test("filter normalizes uppercase characters to lowercase")
    func filterNormalizesUppercaseCharactersToLowercase() {
        let uppercasePayload = "BITCOINCASH:QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let filtered = AddressModel.filterBase32(from: uppercasePayload)
        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }
    
    @Test("filter lowercases uppercase characters")
    func filterLowercasesUppercaseCharacters2() {
        let uppercase = "BITCOINCASH:QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let filtered = AddressModel.filterBase32(from: uppercase)
        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }
    
    @Test("invalid checksum is rejected")
    func rejectInvalidChecksum() {
        let invalid = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
        #expect(throws: AddressModel.Error.invalidChecksum) {
            _ = try AddressModel(invalid)
        }
    }
    
    @Test("address book only replenishes the gap deficit")
    func addressBookMaintainsGapLimit() async throws {
        let mnemonic = try MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        let account = try DerivationPathModel.AccountActor(rawIndexInteger: 0)
        let gapLimit = 5
        let book = try await AddressModel.BookActor(
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
        let mnemonic = try MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        let account = try DerivationPathModel.AccountActor(rawIndexInteger: 0)
        let book = try await AddressModel.BookActor(
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

