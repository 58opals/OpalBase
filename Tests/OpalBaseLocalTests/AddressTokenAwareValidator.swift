// AddressTokenAwareValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Token-aware CashAddr", .tags(.unit, .address, .cashTokens))
struct AddressTokenAwareValidator {
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
        
        switch address.lockingScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data.count == 20)
        default:
            #expect(Bool(false), "Expected P2PKH locking script")
        }
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
        
        switch address.lockingScript {
        case .p2sh(let scriptHash):
            #expect(scriptHash.count == 20)
        default:
            #expect(Bool(false), "Expected P2SH locking script")
        }
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
}

