import Testing
import Foundation
import SwiftFulcrum
@testable import OpalBase

@Suite("Address Tests")
struct AddressTests {
    let fulcrum: Fulcrum
    
    init() async throws {
        self.fulcrum = try .init()
        
        try await self.fulcrum.start()
    }
}

//extension AddressTests {
//    @Test func testExtendedPrivateKeyAddress() throws {
//        let depth = UInt8(2)
//        let parentFingerprint = Data([0x1c, 0xf6, 0x12, 0x59])
//        let childNumber = UInt32(8)
//        let chainCode = Data([0xaf, 0xfd, 0x74, 0xe3, 0xc7, 0x74, 0xd1, 0x7e, 0x2c, 0x3c, 0x61, 0x58, 0x7c, 0xe3, 0xbe, 0x19, 0xee, 0x29, 0xe8, 0x33, 0xdf, 0x11, 0x0e, 0x24, 0xd3, 0x6f, 0x3a, 0x27, 0x59, 0x97, 0x2e, 0x56])
//        let privateKey = try PrivateKey(data: .init([0x4b, 0xfd, 0xe4, 0x06, 0xfa, 0xeb, 0xd6, 0x1a, 0x20, 0xe7, 0xec, 0xdf, 0xa0, 0x60, 0x1e, 0x3a, 0x95, 0x17, 0x23, 0x6b, 0xb1, 0xcd, 0x9b, 0x43, 0x49, 0x14, 0x97, 0x33, 0xb8, 0x8d, 0x1d, 0xbd])).rawData
//        try #require(privateKey.count == 32, "The private key should be 32 bytes.")
//        
//        let extendedPrivateKey = PrivateKey.Extended(privateKey: privateKey,
//                                                     chainCode: chainCode,
//                                                     depth: depth,
//                                                     parentFingerprint: parentFingerprint,
//                                                     childNumber: childNumber)
//        
//        let serialized = extendedPrivateKey.xprvSerialize()
//        let expectedSerialized = Data([0x04, 0x88, 0xad, 0xe4, 0x02, 0x1c, 0xf6, 0x12, 0x59, 0x00, 0x00, 0x00, 0x08, 0xaf, 0xfd, 0x74, 0xe3, 0xc7, 0x74, 0xd1, 0x7e, 0x2c, 0x3c, 0x61, 0x58, 0x7c, 0xe3, 0xbe, 0x19, 0xee, 0x29, 0xe8, 0x33, 0xdf, 0x11, 0x0e, 0x24, 0xd3, 0x6f, 0x3a, 0x27, 0x59, 0x97, 0x2e, 0x56, 0x00, 0x4b, 0xfd, 0xe4, 0x06, 0xfa, 0xeb, 0xd6, 0x1a, 0x20, 0xe7, 0xec, 0xdf, 0xa0, 0x60, 0x1e, 0x3a, 0x95, 0x17, 0x23, 0x6b, 0xb1, 0xcd, 0x9b, 0x43, 0x49, 0x14, 0x97, 0x33, 0xb8, 0x8d, 0x1d, 0xbd, 0xb0, 0x3f, 0x26, 0x53])
//        let expectedSerializedDataInString = try Data(hexString: "0488ade4021cf6125900000008affd74e3c774d17e2c3c61587ce3be19ee29e833df110e24d36f3a2759972e56004bfde406faebd61a20e7ecdfa0601e3a9517236bb1cd9b4349149733b88d1dbdb03f2653")
//        try #require(expectedSerialized == expectedSerializedDataInString)
//        #expect(serialized == expectedSerialized, "Serialized extended private key did not match expected output.")
//        let xprvAddress = extendedPrivateKey.xprvAddress
//        #expect(xprvAddress == "xprv9vzdNx8Jf4yvWMqjyP5isUxg1uUQYs7Q66va8bxuAGoLwvySthu2b2VLGQo8kjRwpndPFweeSA92vmMuy5io5z7LXx4FG6FuDqqn7bKb3ni", "The address did not match expected output.")
//    }
//}

extension AddressTests {
    @Test func testAddressInitializationFromCashAddress() throws {
        let originalAddress = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init(data: .init(repeating: 0x01, count: 32))))))
        print(originalAddress)
        
        let cashAddressWithPrefix = "bitcoincash:qpumqqygwcnt999fz3gp5nxjy66ckg6esvls5sszem"
        let addressWithPrefix = try Address(cashAddressWithPrefix)
        #expect(addressWithPrefix.string == cashAddressWithPrefix, "Address string with prefix did not match expected output.")
        #expect(Address.prefix == "bitcoincash", "Address prefix did not match expected value.")

        let cashAddressWithoutPrefix = "qpumqqygwcnt999fz3gp5nxjy66ckg6esvls5sszem"
        let addressWithoutPrefix = try Address(cashAddressWithoutPrefix)
        #expect(addressWithoutPrefix.string == cashAddressWithoutPrefix, "Address string without prefix did not match expected output.")
        #expect(Address.prefix == "bitcoincash", "Default address prefix did not match expected value.")

        let invalidCashAddressWithPrefix = "bitcoincash:invalidaddress"
        do {
            _ = try Address(invalidCashAddressWithPrefix)
            #expect(Bool(false), "Expected error for invalid Cash Address format not thrown.")
        } catch Base32.Error.invalidCharacterFound {
            #expect(true, "Expected .invalidCharacterFound error.")
        }

        let invalidCashAddressWithoutPrefix = "invalidaddress"
        do {
            _ = try Address(invalidCashAddressWithoutPrefix)
            #expect(Bool(false), "Expected error for invalid Cash Address format not thrown.")
        } catch Base32.Error.invalidCharacterFound {
            #expect(true, "Expected .invalidCharacterFound error.")
        }
    }
    
    @Test func testFetchBalance() async throws {
        let generatedAddress = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init()))))
        let generatedAddressBalance = try await generatedAddress.fetchBalance(using: fulcrum)
        
        let stringAddress = "bitcoincash:qrsrz5mzve6kyr6ne6lgsvlgxvs3hqm6huxhd8gqwj"
        let stringAddressBalance = try await Address.fetchBalance(for: stringAddress, using: fulcrum)
        
        print("The balance of the address \(generatedAddress.string) is: \(generatedAddressBalance).")
        print("The balance of the address \(stringAddress) is: \(stringAddressBalance).")
        
        #expect(generatedAddressBalance.uint64 == 0, "The balance for the generated address is incorrect.")
        #expect(stringAddressBalance.uint64 == 224480, "The balance for \(stringAddress) is incorrect.")
    }
    
    @Test func testFetchSimpleTransactionHistory() async throws {
        let address = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init(wif: "Ky613uSeVQDEM89amKquEr6rZ1Xb7Mr3YDbbmyBT2zyppGChS9nU")))))
        let history = try await address.fetchSimpleTransactionHistory(fulcrum: fulcrum)
        
        print(history)
        
        #expect(address.string == "bitcoincash:qqe89pk7gjzxqedcsykmaa5wc8dt8zp57q5nuylgjw", "Address string did not match expected.")
        #expect(history.count == 16, "Transaction history count did not match expected.")
    }
    
    @Test func testFetchFullTransactionHistory() async throws {
        let address = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init(wif: "Ky613uSeVQDEM89amKquEr6rZ1Xb7Mr3YDbbmyBT2zyppGChS9nU")))))
        let history = try await address.fetchFullTransactionHistory(fulcrum: fulcrum)
        
        print(history)
        
        #expect(address.string == "bitcoincash:qqe89pk7gjzxqedcsykmaa5wc8dt8zp57q5nuylgjw", "Address string did not match expected.")
        #expect(history.count == 16, "Transaction history count did not match expected.")
    }
    
    @Test func testSubscribe() async {
        do {
            let address = try Address("qqe89pk7gjzxqedcsykmaa5wc8dt8zp57q5nuylgjw")//Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init()))))
            let (id, initialStatus, followingStatus) = try await address.subscribe(fulcrum: fulcrum)
            
            #expect(id.uuidString.count == 36, "Subscription ID did not match expected.")
            print("Initial status of the address \(address.string): \(initialStatus)")
            
            for try await newStatus in followingStatus {
                print("The new status of the address \(address.string): \(newStatus)")
                break
            }
        } catch Fulcrum.Error.resultNotFound(let description) {
            print("It seems like the status of the address is missing. \(description)")
        } catch {
            print(error.localizedDescription)
        }
    }
}
