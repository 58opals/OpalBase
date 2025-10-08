import Foundation
import Testing
@testable import OpalBase

extension Tag {
    @Tag static var unit: Self
    @Tag static var integration: Self
    @Tag static var fulcrum: Self
    @Tag static var slow: Self
    @Tag static var flaky: Self
    @Tag static var crypto: Self
    @Tag static var policy: Self
    @Tag static var serialization: Self
    @Tag static var script: Self
    @Tag static var address: Self
    @Tag static var transaction: Self
    @Tag static var wallet: Self
    @Tag static var key: Self
    @Tag static var network: Self
    @Tag static var core: Self
}

enum Environment {
    static let network = ProcessInfo.processInfo.environment["OPAL_NETWORK_TESTS"] == "1"
    static let fulcrumURL = ProcessInfo.processInfo.environment["OPAL_FULCRUM_URL"]
    static let fixtureDirectory = ProcessInfo.processInfo.environment["OPAL_FIXTURE_DIRECTORY"] ?? "Tests/Fixtures"
    static let walletWIF = ProcessInfo.processInfo.environment["OPAL_WALLET_WIF"]
    static let transactionRecipient = ProcessInfo.processInfo.environment["OPAL_TX_RECIPIENT"]
    static let transactionSatoshis: UInt64? = ProcessInfo.processInfo.environment["OPAL_TX_SATOSHIS"].flatMap(UInt64.init)
    static let transactionFeePerByte: UInt64? = ProcessInfo.processInfo.environment["OPAL_TX_FEE_PER_BYTE"].flatMap(UInt64.init)
    static let sendAddress: Address? = parseSendAddress()
    static let sendAmount: Satoshi? = parseSendAmount()
    static let testBalanceAccountIndex: Int = getTestBalanceAccountIndex()
    
    static func getTestBalanceAccountIndex(default defaultIndex: Int = 0) -> Int {
        guard let value = ProcessInfo.processInfo.environment["OPAL_TEST_BALANCE_ACCOUNT"],
              let parsed = Int(value)
        else { return defaultIndex }
        
        return parsed
    }
    
    static func parseSendAddress() -> Address? {
        guard let value = ProcessInfo.processInfo.environment["OPAL_TEST_SEND_ADDRESS"], !value.isEmpty else { return nil }
        
        do { return try Address(value) }
        catch { return nil }
    }
    
    static func parseSendAmount() -> Satoshi? {
        guard let value = ProcessInfo.processInfo.environment["OPAL_TEST_SEND_AMOUNT_SATS"],
              let parsed = UInt64(value)
        else { return nil }
        
        return try? Satoshi(parsed)
    }
}

extension TimeInterval {
    static let fast: TimeInterval = 2      // unit
    static let io: TimeInterval = 15       // integration I/O
    static let network: TimeInterval = 30  // live network
}
