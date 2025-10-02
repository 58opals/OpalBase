import Foundation
import Testing

extension Tag {
    @Tag static var unit: Self
    @Tag static var integration: Self
    @Tag static var fulcrum: Self
    @Tag static var slow: Self
    @Tag static var flaky: Self
    @Tag static var crypto: Self
    @Tag static var policy: Self
    @Tag static var serialization: Self
    @Tag static var address: Self
    @Tag static var transaction: Self
    @Tag static var key: Self
    @Tag static var network: Self
    @Tag static var core: Self
}

enum Environment {
    static let network = ProcessInfo.processInfo.environment["OPAL_NETWORK_TESTS"] == "1"
    static let fulcrumURL = ProcessInfo.processInfo.environment["OPAL_FULCRUM_URL"]
    static let fixtureDirectory = ProcessInfo.processInfo.environment["OPAL_FIXTURE_DIRECTORY"] ?? "Tests/Fixtures"
}

extension TimeInterval {
    static let fast: TimeInterval = 2      // unit
    static let io: TimeInterval = 15       // integration I/O
    static let network: TimeInterval = 30  // live network
}
