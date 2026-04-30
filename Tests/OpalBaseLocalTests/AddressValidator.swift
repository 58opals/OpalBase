// AddressValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("CashAddr", .tags(.unit, .address))
struct AddressValidator {
    private func makeKnownP2PKHScript() throws -> OpalBase.Script {
        try OpalBase.Address("qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a").lockingScript
    }

    @Test("known private key derives stable wallet and address artifacts")
    func deriveStableWalletAndAddressArtifacts() throws {
        let privateKey = Data(repeating: 0x00, count: 31) + Data([0x01])
        let walletImportFormat = try OpalCrypto.Key.WIF(privateKey: privateKey).serialize()
        let publicKey = try OpalBase.Key.PublicKey(privateKeyData: privateKey)
        let hash = OpalBase.Key.PublicKey.Hash(publicKey: publicKey)
        let script = OpalBase.Script.p2pkh_OPCHECKSIG(hash: hash)
        let legacyAddress = try OpalBase.Address.Legacy(script)
        let address = try OpalBase.Address(script: script)

        #expect(walletImportFormat == "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn")
        #expect(legacyAddress.string == "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH")
        #expect(address.lockingScript.data == script.data)
        #expect(try OpalBase.Address(address.string).lockingScript.data == script.data)
    }

    @Test("CashAddr prefixes map to OpalBase networks")
    func cashAddrPrefixesMapToNetworks() {
        #expect(OpalBase.Address.cashAddrPrefix(for: .mainnet) == "bitcoincash")
        #expect(OpalBase.Address.cashAddrPrefix(for: .testnet) == "bchtest")
        #expect(OpalBase.Address.cashAddrPrefix(for: .chipnet) == "bchtest")
    }

    @Test("CashAddr generation uses the address network")
    func generateCashAddrWithNetworkPrefix() throws {
        let script = try makeKnownP2PKHScript()
        let mainnetAddress = try OpalBase.Address(script: script, network: .mainnet)
        let testnetAddress = try OpalBase.Address(script: script, network: .testnet)
        let chipnetAddress = try OpalBase.Address(script: script, network: .chipnet)

        #expect(mainnetAddress.network == .mainnet)
        #expect(testnetAddress.network == .testnet)
        #expect(chipnetAddress.network == .chipnet)
        #expect(mainnetAddress.generateString(withPrefix: true).hasPrefix("bitcoincash:"))
        #expect(testnetAddress.generateString(withPrefix: true).hasPrefix("bchtest:"))
        #expect(chipnetAddress.generateString(withPrefix: true).hasPrefix("bchtest:"))
        #expect(mainnetAddress.string != testnetAddress.string)
        #expect(testnetAddress.string == chipnetAddress.string)
    }

    @Test("explicit network parses bchtest prefix and prefixless payloads")
    func parseBchtestWithExplicitNetwork() throws {
        let script = try makeKnownP2PKHScript()
        let testnetAddress = try OpalBase.Address(script: script, network: .testnet)
        let chipnetAddress = try OpalBase.Address(script: script, network: .chipnet)

        let prefixfulTestnet = try OpalBase.Address(
            string: testnetAddress.generateString(withPrefix: true),
            network: .testnet
        )
        let prefixlessTestnet = try OpalBase.Address(
            string: testnetAddress.string,
            network: .testnet
        )
        let prefixfulChipnet = try OpalBase.Address(
            string: chipnetAddress.generateString(withPrefix: true),
            network: .chipnet
        )
        let prefixlessChipnet = try OpalBase.Address(
            string: chipnetAddress.string,
            network: .chipnet
        )

        #expect(prefixfulTestnet == testnetAddress)
        #expect(prefixlessTestnet == testnetAddress)
        #expect(prefixfulChipnet == chipnetAddress)
        #expect(prefixlessChipnet == chipnetAddress)
        #expect(prefixfulTestnet.network == .testnet)
        #expect(prefixfulChipnet.network == .chipnet)
    }

    @Test("default initializer rejects ambiguous bchtest addresses")
    func rejectBchtestWithoutExplicitNetwork() throws {
        let script = try makeKnownP2PKHScript()
        let bchtestAddress = try OpalBase.Address(
            script: script,
            network: .testnet
        ).generateString(withPrefix: true)

        #expect(throws: OpalBase.Address.Error.invalidCashAddrFormat) {
            _ = try OpalBase.Address(string: bchtestAddress)
        }
    }

    @Test("address identity includes network but not presentation format")
    func addressIdentityIncludesNetwork() throws {
        let script = try makeKnownP2PKHScript()
        let mainnetAddress = try OpalBase.Address(script: script, network: .mainnet)
        let mainnetTokenAwareAddress = try OpalBase.Address(
            script: script,
            format: .tokenAware,
            network: .mainnet
        )
        let testnetAddress = try OpalBase.Address(script: script, network: .testnet)
        let chipnetAddress = try OpalBase.Address(script: script, network: .chipnet)
        let addressSet: Set<OpalBase.Address> = [
            mainnetAddress,
            mainnetTokenAwareAddress,
            testnetAddress,
            chipnetAddress
        ]

        #expect(mainnetAddress == mainnetTokenAwareAddress)
        #expect(mainnetAddress != testnetAddress)
        #expect(testnetAddress != chipnetAddress)
        #expect(addressSet.count == 3)
    }

    @Test("CashAddr decodes to P2PKH script")
    func decodeCashAddrToP2PKHScript() throws {
        let cashAddr = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try OpalBase.Address(cashAddr)
        #expect(address.string == cashAddr)
        #expect(address.network == .mainnet)

        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
    }

    @Test("CashAddr accepts uppercase payload")
    func decodeCashAddrWithUppercasePayload() throws {
        let cashAddr = "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let address = try OpalBase.Address(cashAddr)
        #expect(address.string == cashAddr)

        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
    }

    @Test("mixed-case CashAddr payload is rejected")
    func rejectMixedCaseCashAddrPayload() {
        let mixedCasePayload = "qpm2qsznHks23z7629mms6s4cwef74vcwvy22gdx6a"

        #expect(throws: OpalBase.Address.Error.invalidCashAddrFormat) {
            _ = try OpalBase.Address(mixedCasePayload)
        }
    }

    @Test("CashAddr rejects empty separator components")
    func rejectCashAddrEmptySeparatorComponents() {
        let payload = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"

        #expect(throws: OpalBase.Address.Error.invalidCashAddrFormat) {
            _ = try OpalBase.Address("bitcoincash::\(payload)")
        }
        #expect(throws: OpalBase.Address.Error.invalidCashAddrFormat) {
            _ = try OpalBase.Address("bitcoincash:\(payload):")
        }
    }

    @Test("CashAddr accepts uppercase prefix")
    func decodeCashAddrWithUppercasePrefix() throws {
        let payload = "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let cashAddr = "BITCOINCASH:\(payload)"
        let address = try OpalBase.Address(cashAddr)
        #expect(address.string == payload)
        #expect(address.network == .mainnet)

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
        #expect(OpalBase.Address.filterBase32(from: "BCHTEST:QPZA", network: .testnet) == "qpza")
        #expect(OpalBase.Address.filterBase32(from: "BCHTEST:QPZA", network: .chipnet) == "qpza")
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
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        let account = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: 0)
        let gapLimit = 5
        let book = try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            gapLimit: gapLimit
        )

        let initialTotal = await book.countEntries(for: OpalBase.Key.DerivationPath.Usage.receiving)
        #expect(initialTotal == gapLimit)

        let entries = await book.listEntries(for: OpalBase.Key.DerivationPath.Usage.receiving)
        let firstEntry = try #require(entries.first)
        try await book.mark(address: firstEntry.address, isUsed: true)

        let updatedTotal = await book.countEntries(for: OpalBase.Key.DerivationPath.Usage.receiving)
        let updatedUnused = await book.countUnusedEntries(for: OpalBase.Key.DerivationPath.Usage.receiving)

        #expect(updatedTotal == initialTotal + 1)
        #expect(updatedUnused == gapLimit)
    }

    @Test("address book uses distinct receiving and change addresses")
    func addressBookUsesDistinctReceivingAndChangeAddresses() async throws {
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        let account = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: 0)
        let book = try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            gapLimit: 1
        )

        let receivingEntry = try #require(await book.listEntries(for: OpalBase.Key.DerivationPath.Usage.receiving).first)
        let changeEntry = try #require(await book.listEntries(for: OpalBase.Key.DerivationPath.Usage.change).first)

        #expect(receivingEntry.address != changeEntry.address)
    }
}
