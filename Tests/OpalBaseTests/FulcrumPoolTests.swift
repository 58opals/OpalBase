import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("FulcrumPool Reconnection")
struct FulcrumPoolTests {
    @Test func testReconnectStatusTransitions() async throws {
        let pool = try await Wallet.Network.FulcrumPool()
        _ = try await pool.getFulcrum()
        #expect(await pool.currentStatus == .online)

        let stream = await pool.observeStatus()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial == .online)

        let task = Task {
            try await pool.reconnect()
        }

        let offline = await iterator.next()
        let connecting = await iterator.next()
        _ = try await task.value
        let final = await iterator.next()

        #expect(offline == .offline)
        #expect(connecting == .connecting)
        #expect(final == .online)
    }
}
