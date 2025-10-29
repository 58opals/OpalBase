import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Connection", .tags(.network, .integration))
struct NetworkFulcrumSessionConnectionTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
}
