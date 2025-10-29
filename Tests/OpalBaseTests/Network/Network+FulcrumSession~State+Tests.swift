import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession State", .tags(.network, .integration))
struct NetworkFulcrumSessionStateTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
}
