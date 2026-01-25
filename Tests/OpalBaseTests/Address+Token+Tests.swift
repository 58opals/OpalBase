import Testing
@testable import OpalBase

@Suite("Token-aware CashAddr", .tags(.unit, .address, .cashTokens))
struct AddressTokenAwareTests {
    @Test("token-aware P2PKH cash address decodes")
    func testDecodeTokenAwarePublicKeyHashAddress() throws {
        let tokenAwareAddress = "bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"
        let expectedPayload = "zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"
        let address = try Address(string: tokenAwareAddress)
        #expect(address.supportsTokens)
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
    
    @Test("token-aware P2SH cash address decodes")
    func testDecodeTokenAwareScriptHashAddress() throws {
        let tokenAwareAddress = "bitcoincash:rqgjyv6y24n80zyeqz4thnxaamlsqyfzxve4yxax2l"
        let expectedPayload = "rqgjyv6y24n80zyeqz4thnxaamlsqyfzxve4yxax2l"
        let address = try Address(string: tokenAwareAddress)
        #expect(address.supportsTokens)
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
    
    @Test("token-aware string is derived from standard cash address")
    func testTokenAwareStringForStandardAddress() throws {
        let standardAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let expectedTokenAwarePayload = "zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"
        let address = try Address(string: standardAddress)
        #expect(address.supportsTokens == false)
        #expect(address.tokenAwareString == expectedTokenAwarePayload)
    }
    
    @Test("base58 address parses as standard cash address")
    func testDecodeLegacyBase58Address() throws {
        let legacyAddress = "1BpEi6DfDAUFd7GtittLSdBeYJvcoaVggu"
        let expectedPayload = "qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
        let address = try Address(string: legacyAddress)
        #expect(address.supportsTokens == false)
        #expect(address.string == expectedPayload)
        #expect(address.generateString(withPrefix: true) == "bitcoincash:\(expectedPayload)")
    }
}
