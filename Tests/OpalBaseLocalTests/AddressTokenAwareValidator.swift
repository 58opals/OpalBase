// AddressTokenAwareValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Token-aware CashAddr", .tags(.unit, .address, .cashTokens))
struct AddressTokenAwareValidator {
    private func makeKnownP2PKHScript() throws -> OpalBase.Script {
        try OpalBase.Address("qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a").lockingScript
    }

    @Test("token-aware P2PKH CashAddr decodes")
    func decodeTokenAwarePublicKeyHashAddress() throws {
        let tokenAwareAddress = "bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"
        let expectedPayload = "zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"
        let address = try OpalBase.Address(string: tokenAwareAddress)
        #expect(address.isTokenAware)
        #expect(address.format == .tokenAware)
        #expect(address.string == expectedPayload)
        #expect(address.tokenAwareString == expectedPayload)
        #expect(address.generateString(withPrefix: true) == tokenAwareAddress)

        guard case .p2pkh_OPCHECKSIG(let hash) = address.lockingScript else {
            Issue.record("Expected P2PKH locking script")
            return
        }
        #expect(hash.data.count == 20)
    }

    @Test("token-aware P2SH CashAddr decodes")
    func decodeTokenAwareScriptHashAddress() throws {
        let tokenAwareAddress = "bitcoincash:rqgjyv6y24n80zyeqz4thnxaamlsqyfzxve4yxax2l"
        let expectedPayload = "rqgjyv6y24n80zyeqz4thnxaamlsqyfzxve4yxax2l"
        let address = try OpalBase.Address(string: tokenAwareAddress)
        #expect(address.isTokenAware)
        #expect(address.format == .tokenAware)
        #expect(address.string == expectedPayload)
        #expect(address.generateString(withPrefix: true) == tokenAwareAddress)

        guard case .p2sh(let scriptHash) = address.lockingScript else {
            Issue.record("Expected P2SH locking script")
            return
        }
        #expect(scriptHash.count == 20)
    }

    @Test("token-aware string is derived from standard CashAddr")
    func tokenAwareStringForStandardAddress() throws {
        let standardAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let expectedTokenAwarePayload = "zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"
        let address = try OpalBase.Address(string: standardAddress)
        #expect(address.isTokenAware == false)
        #expect(address.tokenAwareString == expectedTokenAwarePayload)
    }

    @Test("base58 address parses as standard CashAddr")
    func decodeLegacyBase58Address() throws {
        let legacyAddress = "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu"
        let expectedPayload = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try OpalBase.Address(string: legacyAddress)
        #expect(address.isTokenAware == false)
        #expect(address.string == expectedPayload)
        #expect(address.generateString(withPrefix: true) == "bitcoincash:\(expectedPayload)")
    }

    @Test("token-aware string preserves address network")
    func tokenAwareStringPreservesAddressNetwork() throws {
        let script = try makeKnownP2PKHScript()
        let mainnetAddress = try OpalBase.Address(script: script, network: .mainnet)
        let testnetAddress = try OpalBase.Address(script: script, network: .testnet)
        let chipnetAddress = try OpalBase.Address(script: script, network: .chipnet)

        let parsedTestnetTokenAware = try OpalBase.Address(
            string: testnetAddress.tokenAwareString,
            network: .testnet
        )
        let parsedChipnetTokenAware = try OpalBase.Address(
            string: chipnetAddress.tokenAwareString,
            network: .chipnet
        )

        #expect(mainnetAddress.tokenAwareString != testnetAddress.tokenAwareString)
        #expect(testnetAddress.tokenAwareString == chipnetAddress.tokenAwareString)
        #expect(parsedTestnetTokenAware.format == .tokenAware)
        #expect(parsedChipnetTokenAware.format == .tokenAware)
        #expect(parsedTestnetTokenAware.network == .testnet)
        #expect(parsedChipnetTokenAware.network == .chipnet)
        #expect(parsedTestnetTokenAware.generateString(withPrefix: true).hasPrefix("bchtest:"))
        #expect(parsedChipnetTokenAware.generateString(withPrefix: true).hasPrefix("bchtest:"))
        #expect(throws: OpalBase.Address.Error.invalidCashAddrFormat) {
            _ = try OpalBase.Address(string: testnetAddress.tokenAwareString)
        }
    }

    @Test("converted(to:) preserves script and network")
    func convertedFormatPreservesScriptAndNetwork() throws {
        let script = try makeKnownP2PKHScript()
        let mainnetAddress = try OpalBase.Address(script: script, network: .mainnet)
        let testnetAddress = try OpalBase.Address(script: script, network: .testnet)
        let chipnetAddress = try OpalBase.Address(script: script, network: .chipnet)

        let mainnetTokenAware = try mainnetAddress.converted(to: .tokenAware)
        let testnetTokenAware = try testnetAddress.converted(to: .tokenAware)
        let chipnetTokenAware = try chipnetAddress.converted(to: .tokenAware)
        let standardAgain = try mainnetTokenAware.converted(to: .standard)

        #expect(mainnetTokenAware.lockingScript == mainnetAddress.lockingScript)
        #expect(testnetTokenAware.lockingScript == testnetAddress.lockingScript)
        #expect(chipnetTokenAware.lockingScript == chipnetAddress.lockingScript)
        #expect(mainnetTokenAware.network == .mainnet)
        #expect(testnetTokenAware.network == .testnet)
        #expect(chipnetTokenAware.network == .chipnet)
        #expect(mainnetTokenAware.format == .tokenAware)
        #expect(testnetTokenAware.format == .tokenAware)
        #expect(chipnetTokenAware.format == .tokenAware)
        #expect(mainnetTokenAware.generateString(withPrefix: true).hasPrefix("bitcoincash:"))
        #expect(testnetTokenAware.generateString(withPrefix: true).hasPrefix("bchtest:"))
        #expect(chipnetTokenAware.generateString(withPrefix: true).hasPrefix("bchtest:"))
        #expect(standardAgain.format == .standard)
        #expect(standardAgain.lockingScript == mainnetAddress.lockingScript)
        #expect(standardAgain.network == .mainnet)
    }
}
