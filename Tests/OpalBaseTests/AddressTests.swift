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
    
    @Test func testFetchTransactionHistory() async throws {
        let address = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init(wif: "Ky613uSeVQDEM89amKquEr6rZ1Xb7Mr3YDbbmyBT2zyppGChS9nU")))))
        let history = try await address.fetchTransactionHistory(fulcrum: fulcrum)
        
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
