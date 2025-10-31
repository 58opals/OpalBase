import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession", .tags(.network))
struct NetworkFulcrumSessionTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let alternativeServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
}
