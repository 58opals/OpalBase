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

    @Test("public key wrappers normalize sliced data")
    func publicKeyWrappersNormalizeSlicedData() throws {
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        let privateKey = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKeyData)
        let compressedPublicKeyData = try OpalCrypto.Secp256k1.derivePublicKey(
            from: privateKey
        ).compressedRepresentation
        let publicKeyHashData = Data(repeating: 0x02, count: 20)
        let slicedCompressedPublicKeyData = Self.makeSlicedData(from: compressedPublicKeyData)
        let slicedPublicKeyHashData = Self.makeSlicedData(from: publicKeyHashData)

        let publicKey = try OpalBase.Key.PublicKey(compressedData: slicedCompressedPublicKeyData)
        let publicKeyHash = OpalBase.Key.PublicKey.Hash(slicedPublicKeyHashData)

        #expect(slicedCompressedPublicKeyData.startIndex != 0)
        #expect(slicedPublicKeyHashData.startIndex != 0)
        #expect(publicKey.compressedData == compressedPublicKeyData)
        #expect(publicKey.compressedData.startIndex == 0)
        #expect(publicKeyHash.data == publicKeyHashData)
        #expect(publicKeyHash.data.startIndex == 0)
    }

    @Test("public key wrappers reject invalid compressed public keys")
    func publicKeyWrappersRejectInvalidCompressedPublicKeys() {
        #expect(throws: OpalBase.Key.PublicKey.Error.invalidFormat) {
            _ = try OpalBase.Key.PublicKey(
                compressedData: Data([0x01]) + Data(repeating: 0x00, count: 32)
            )
        }
        #expect(throws: OpalBase.Key.PublicKey.Error.invalidFormat) {
            _ = try OpalBase.Key.PublicKey(
                compressedData: Data([0x02]) + Data(repeating: 0xFF, count: 32)
            )
        }
    }

    @Test("address book usage derivation cache normalizes sliced data")
    func addressBookUsageDerivationCacheNormalizesSlicedData() throws {
        let baseExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        let compressedPublicKeyData = Data([0x02]) + Data(repeating: 0x03, count: 32)
        let fingerprintData = Data(repeating: 0x04, count: 4)
        let slicedCompressedPublicKeyData = Self.makeSlicedData(from: compressedPublicKeyData)
        let slicedFingerprintData = Self.makeSlicedData(from: fingerprintData)

        let cache = OpalBase.Address.Book.UsageDerivationCache(
            baseExtendedPrivateKey: baseExtendedPrivateKey,
            baseCompressedPublicKey: slicedCompressedPublicKeyData,
            baseFingerprint: slicedFingerprintData
        )

        #expect(slicedCompressedPublicKeyData.startIndex != 0)
        #expect(slicedFingerprintData.startIndex != 0)
        #expect(cache.baseCompressedPublicKey == compressedPublicKeyData)
        #expect(cache.baseCompressedPublicKey.startIndex == 0)
        #expect(cache.baseFingerprint == fingerprintData)
        #expect(cache.baseFingerprint.startIndex == 0)
    }

    @Test("known private key derives stable wallet and address artifacts")
    func deriveStableWalletAndAddressArtifacts() throws {
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        let privateKey = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKeyData)
        let walletImportFormat = try OpalCrypto.Key.WIF(privateKey: privateKey).serialize()
        let publicKey = try OpalBase.Key.PublicKey(privateKeyData: privateKeyData)
        let hash = OpalBase.Key.PublicKey.Hash(publicKey: publicKey)
        let script = OpalBase.Script.p2pkh_OPCHECKSIG(hash: hash)
        let legacyAddress = try OpalBase.Address.Legacy(script)
        let address = try OpalBase.Address(script: script)

        #expect(walletImportFormat == "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn")
        #expect(legacyAddress.string == "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH")
        #expect(address.lockingScript.data == script.data)
        #expect(try OpalBase.Address(address.string).lockingScript.data == script.data)
    }

    @Test("CashAddr prefixes map to OpalBase networks", arguments: cashAddrPrefixCases)
    func cashAddrPrefixesMapToNetworks(_ prefixCase: (network: OpalBase.Network.Environment, prefix: String)) {
        #expect(OpalBase.Address.cashAddrPrefix(for: prefixCase.network) == prefixCase.prefix)
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

    @Test(
        "explicit network parses bchtest prefix and prefixless payloads",
        arguments: bchtestExplicitNetworkCases
    )
    func parseBchtestWithExplicitNetwork(_ network: OpalBase.Network.Environment) throws {
        let script = try makeKnownP2PKHScript()
        let address = try OpalBase.Address(script: script, network: network)

        let prefixfulAddress = try OpalBase.Address(
            string: address.generateString(withPrefix: true),
            network: network
        )
        let prefixlessAddress = try OpalBase.Address(
            string: address.string,
            network: network
        )

        #expect(prefixfulAddress == address)
        #expect(prefixlessAddress == address)
        #expect(prefixfulAddress.network == network)
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

        let hash = try Self.requirePayToPublicKeyHash(from: address.lockingScript)
        #expect(hash.data.count == 20)
    }

    @Test("address derivation rejects P2PKH CHECKDATASIG scripts")
    func rejectCheckDataSigScriptAddressDerivation() {
        let hash = OpalBase.Key.PublicKey.Hash(Data(repeating: 0x42, count: 20))
        let script = OpalBase.Script.p2pkh_OPCHECKDATASIG(hash: hash)

        #expect(script.isDerivableFromAddress == false)
        #expect(throws: OpalBase.Address.Legacy.Error.self) {
            _ = try OpalBase.Address(script: script)
        }
        #expect(throws: OpalBase.Address.Legacy.Error.self) {
            _ = try OpalBase.Address.Legacy(script)
        }
    }

    @Test("legacy Base58 encodes P2SH scripts")
    func legacyBase58EncodesP2SHScripts() throws {
        let script = OpalBase.Script.p2sh(scriptHash: Data(repeating: 0x42, count: 20))
        let legacyAddress = try OpalBase.Address.Legacy(script)
        let parsedAddress = try OpalBase.Address(legacyAddress.string)

        #expect(parsedAddress.lockingScript == script)
        #expect(parsedAddress.format == .standard)
        #expect(parsedAddress.network == .mainnet)
    }

    @Test("address derivation rejects malformed P2PKH hash length")
    func rejectMalformedP2PKHHashLengthAddressDerivation() {
        let script = OpalBase.Script.p2pkh_OPCHECKSIG(
            hash: .init(Data(repeating: 0x42, count: 19))
        )

        #expect(throws: OpalBase.Address.Legacy.Error.self) {
            _ = try OpalBase.Address(script: script)
        }
        #expect(throws: OpalBase.Address.Legacy.Error.self) {
            _ = try OpalBase.Address.Legacy(script)
        }
    }

    @Test("CashAddr accepts uppercase payload")
    func decodeCashAddrWithUppercasePayload() throws {
        let cashAddr = "QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let address = try OpalBase.Address(cashAddr)
        #expect(address.string == cashAddr.lowercased())
        #expect(address.generateString(withPrefix: true) == "bitcoincash:\(cashAddr.lowercased())")
        #expect(try OpalBase.Address(address.generateString(withPrefix: true)) == address)

        let hash = try Self.requirePayToPublicKeyHash(from: address.lockingScript)
        #expect(hash.data.count == 20)
    }

    @Test("mixed-case CashAddr values are rejected", arguments: mixedCaseCashAddrCases)
    func rejectMixedCaseCashAddrValues(_ cashAddr: String) {
        #expect(throws: OpalBase.Address.Error.invalidCashAddrFormat) {
            _ = try OpalBase.Address(cashAddr)
        }
    }

    @Test(
        "CashAddr rejects empty separator components",
        arguments: cashAddrEmptySeparatorCases
    )
    func rejectCashAddrEmptySeparatorComponents(_ cashAddr: String) {
        #expect(throws: OpalBase.Address.Error.invalidCashAddrFormat) {
            _ = try OpalBase.Address(cashAddr)
        }
    }

    @Test("CashAddr accepts uppercase prefix")
    func decodeCashAddrWithUppercasePrefix() throws {
        let payload = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let cashAddr = "BITCOINCASH:\(payload.uppercased())"
        let address = try OpalBase.Address(cashAddr)
        #expect(address.string == payload)
        #expect(address.generateString(withPrefix: true) == "bitcoincash:\(payload)")
        #expect(try OpalBase.Address(address.generateString(withPrefix: true)) == address)
        #expect(address.network == .mainnet)

        let hash = try Self.requirePayToPublicKeyHash(from: address.lockingScript)
        #expect(hash.data.count == 20)
    }

    @Test("filter removes invalid characters")
    func filterRemovesInvalidCharacters() {
        let noisy = "BITCOINCASH:QPM2-QSZN HK S23Z7629MMS6S4CWEF74VCWVY22GDX6A"
        let filtered = OpalBase.Address.filterBase32(from: noisy)
        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }

    @Test("filter strips prefix after surrounding whitespace")
    func filterStripsPrefixAfterSurroundingWhitespace() {
        let noisy = " \nBITCOINCASH:QPM2-QSZN HK S23Z7629MMS6S4CWEF74VCWVY22GDX6A\t"
        let filtered = OpalBase.Address.filterBase32(from: noisy)

        #expect(filtered == "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
    }

    @Test(
        "filter normalizes uppercase base32 payloads",
        arguments: uppercaseBase32FilterCases
    )
    func filterBase32LowercasesUppercaseCharacters(_ filterCase: Base32FilterCase) {
        let filtered = if let network = filterCase.network {
            OpalBase.Address.filterBase32(from: filterCase.input, network: network)
        } else {
            OpalBase.Address.filterBase32(from: filterCase.input)
        }

        #expect(filtered == filterCase.expected)
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

    @Test("address book derives signing keys for tracked UTXO locking scripts")
    func addressBookDerivesSigningKeysForTrackedUTXOLockingScripts() async throws {
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
        let receivingEntry = try #require(
            await book.listEntries(for: OpalBase.Key.DerivationPath.Usage.receiving).first
        )
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 25_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x4A),
            previousTransactionOutputIndex: 0
        )

        let signingKeys = try await book.deriveSigningKeys(for: [unspentOutput])
        let signingKey = try #require(signingKeys[unspentOutput])
        let signingAddress = try OpalBase.Address(
            script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: signingKey.publicKey))
        )

        #expect(signingAddress == receivingEntry.address)
    }

    @Test("address book rejects non-positive gap limits", arguments: [0, -1])
    func addressBookRejectsNonPositiveGapLimits(_ gapLimit: Int) async throws {
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        let account = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: 0)

        await #expect(throws: OpalBase.Address.Book.Error.indexOutOfBounds) {
            _ = try await OpalBase.Address.Book(
                rootExtendedPrivateKey: rootExtendedPrivateKey,
                purpose: .bip44,
                coinType: .bitcoinCash,
                account: account,
                gapLimit: gapLimit
            )
        }
    }

    @Test("address book derivation rejects hardened address indexes")
    func addressBookDerivationRejectsHardenedAddressIndexes() async throws {
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

        let highestUnhardenedAddress = try await book.generateAddress(
            at: HardenedIndex.maxUnhardenedValue,
            for: .receiving
        )

        #expect(highestUnhardenedAddress.lockingScript.data.isEmpty == false)
        await #expect(throws: OpalBase.Key.DerivationPath.Error.indexOverflow) {
            _ = try await book.generateAddress(at: HardenedIndex.bit, for: .receiving)
        }
        await #expect(throws: OpalBase.Key.DerivationPath.Error.indexOverflow) {
            _ = try await book.generatePrivateKey(at: HardenedIndex.bit, for: .receiving)
        }
    }

    @Test("address usage scan does not query beyond the remaining gap")
    func addressUsageScanDoesNotQueryBeyondRemainingGap() async throws {
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
        let reader = WalletAddressReaderTestActor()

        let scan = try await book.scanForUsedAddresses(
            using: reader,
            usage: .receiving,
            includeUnconfirmed: true
        )

        let requests = await reader.readHistoryRequests()
        #expect(requests.count == 1)
        #expect(scan.totalScannedPerUsage[.receiving] == 1)
    }

    private static func requirePayToPublicKeyHash(
        from script: OpalBase.Script
    ) throws -> OpalBase.Key.PublicKey.Hash {
        guard case .p2pkh_OPCHECKSIG(let hash) = script else {
            throw AddressScriptExpectationFailure.expectedPayToPublicKeyHash
        }
        return hash
    }

    private static let cashAddrPrefixCases = [
        (network: OpalBase.Network.Environment.mainnet, prefix: "bitcoincash"),
        (network: OpalBase.Network.Environment.testnet, prefix: "bchtest"),
        (network: OpalBase.Network.Environment.chipnet, prefix: "bchtest")
    ]

    private static let cashAddrEmptySeparatorCases = [
        "bitcoincash::qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a",
        "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a:"
    ]

    private static let mixedCaseCashAddrCases = [
        "qpm2qsznHks23z7629mms6s4cwef74vcwvy22gdx6a",
        "bitcoincash:QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A"
    ]

    private static let bchtestExplicitNetworkCases = [
        OpalBase.Network.Environment.testnet,
        OpalBase.Network.Environment.chipnet
    ]

    private static let uppercaseBase32FilterCases = [
        Base32FilterCase(input: "BITCOINCASH:QPY0", network: nil, expected: "qpy0"),
        Base32FilterCase(input: "BITCOINCASH:QPZA", network: nil, expected: "qpza"),
        Base32FilterCase(input: "BCHTEST:QPZA", network: .testnet, expected: "qpza"),
        Base32FilterCase(input: "BCHTEST:QPZA", network: .chipnet, expected: "qpza"),
        Base32FilterCase(
            input: "BITCOINCASH:QPM2QSZNHKS23Z7629MMS6S4CWEF74VCWVY22GDX6A",
            network: nil,
            expected: "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        )
    ]

    private static func makeSlicedData(from data: Data) -> Data {
        let paddedData = Data([0x00]) + data
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }

    struct Base32FilterCase: Sendable {
        let input: String
        let network: OpalBase.Network.Environment?
        let expected: String
    }

    enum AddressScriptExpectationFailure: Swift.Error {
        case expectedPayToPublicKeyHash
    }
}
