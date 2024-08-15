import XCTest
@testable import OpalBase

import Combine
import SwiftFulcrum

final class AddressTests: XCTestCase {
    var fulcrum: Fulcrum!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        fulcrum = try Fulcrum()
    }
    
    override func tearDown() {
        fulcrum = nil
        super.tearDown()
    }
}

extension AddressTests {
    func testAddressInitializationFromCashAddress() throws {
        let originalAddress = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init(data: .init(repeating: 0x01, count: 32))))))
        print(originalAddress)
        
        let cashAddressWithPrefix = "bitcoincash:qpumqqygwcnt999fz3gp5nxjy66ckg6esvls5sszem"
        let addressWithPrefix = try Address(cashAddressWithPrefix)
        XCTAssertEqual(addressWithPrefix.string, cashAddressWithPrefix, "Address string with prefix did not match expected output.")
        XCTAssertEqual(addressWithPrefix.prefix, "bitcoincash", "Address prefix did not match expected value.")

        let cashAddressWithoutPrefix = "qpumqqygwcnt999fz3gp5nxjy66ckg6esvls5sszem"
        let addressWithoutPrefix = try Address(cashAddressWithoutPrefix)
        XCTAssertEqual(addressWithoutPrefix.string, cashAddressWithoutPrefix, "Address string without prefix did not match expected output.")
        XCTAssertEqual(addressWithoutPrefix.prefix, "bitcoincash", "Default address prefix did not match expected value.")

        let invalidCashAddressWithPrefix = "bitcoincash:invalidaddress"
        XCTAssertThrowsError(try Address(invalidCashAddressWithPrefix), "Expected an error for invalid Cash Address format") { error in
            guard let addressError = error as? Base32.Error else { return XCTFail("Unexpected error type: \(error)") }
            XCTAssertEqual(addressError, Base32.Error.invalidCharacterFound, "Expected .invalidCashAddressFormat error.")
        }
        
        let invalidCashAddressWithoutPrefix = "invalidaddress"
        XCTAssertThrowsError(try Address(invalidCashAddressWithoutPrefix), "Expected an error for invalid Cash Address format") { error in
            guard let addressError = error as? Base32.Error else { return XCTFail("Unexpected error type: \(error)") }
            XCTAssertEqual(addressError, Base32.Error.invalidCharacterFound, "Expected .invalidCashAddressFormat error.")
        }
    }
    
    func testFetchBalance() async throws {
        let expectation = self.expectation(description: "Fetching balance should succeed")
        
        let generatedAddress = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init()))))
        let generatedAddressBalance = try await generatedAddress.fetchBalance(using: fulcrum)
        let stringAddress = "bitcoincash:qrsrz5mzve6kyr6ne6lgsvlgxvs3hqm6huxhd8gqwj"
        let stringAddressBalance = try await Address.fetchBalance(for: stringAddress, using: fulcrum)
        
        print("The balance of the address \(generatedAddress.string) is: \(generatedAddressBalance).")
        print("The balance of the address \(stringAddress) is: \(stringAddressBalance).")
        
        XCTAssertEqual(generatedAddressBalance, try Satoshi(0), "The balance for the generated address is incorrect.")
        XCTAssertEqual(stringAddressBalance, try Satoshi(223915), "The balance for the \(stringAddress) is incorrect.")
        
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 10.0)
    }
    
    func testFetchTransactionHistory() async throws {
        let expectation = self.expectation(description: "Fetching transaction history should succeed")
        
        let address = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init(wif: "Ky613uSeVQDEM89amKquEr6rZ1Xb7Mr3YDbbmyBT2zyppGChS9nU")))))
        let history = try await address.fetchTransactionHistory(fulcrum: fulcrum)
        
        XCTAssertEqual(address.string, "bitcoincash:qqe89pk7gjzxqedcsykmaa5wc8dt8zp57q5nuylgjw")
        XCTAssertEqual(history.count, 9)
        
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 10.0)
    }
    
    func testSubscribe() async throws {
        let expectation = XCTestExpectation(description: "Subscribe to address activities should succeed")
        
        let address = try Address(script: .p2pkh(hash: .init(publicKey: .init(privateKey: .init()))))
        let (id, publisher) = try await address.subscribe(fulcrum: &fulcrum)
        
        XCTAssertNotNil(id, "Subscription ID should not be nil")
        
        let subscription = publisher
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        XCTFail("Subscription should not finish")
                    case .failure(let error):
                        XCTFail("Subscription failed with error: \(error)")
                    }
                },
                receiveValue: { response in
                    if let response = response {
                        switch response {
                        case .status(let status):
                            print("This is an initial response: \(status) for \(address.string)")
                        case .addressAndStatus(let addressAndStatus):
                            guard let respondedAddress = addressAndStatus.first else { fatalError() }
                            guard let respondedStatus = addressAndStatus.last else { fatalError() }
                            
                            guard respondedAddress == address.string else { fatalError() }
                            
                            print("Status of \(respondedAddress) is changed: \(respondedStatus)")
                            
                            expectation.fulfill()
                        }
                    }
                }
            )
        
        fulcrum.subscriptionHub.add(subscription, for: id)
        
        await fulfillment(of: [expectation], timeout: (1.0 * 60) * 15)
    }
}
