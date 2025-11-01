import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet Fee Policy", .tags(.wallet))
struct WalletFeePolicyTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
}
