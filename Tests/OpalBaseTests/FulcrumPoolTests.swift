import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("FulcrumPool Reconnection")
struct FulcrumPoolTests {
    @Test func testReconnectBringsOfflineServerOnline() async throws {
        let pool = try await Wallet.Network.FulcrumPool()
        #expect(await pool.currentStatus == .offline)
        
        let stream = await pool.observeStatus()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial == .offline)
        
        let task = Task { try await pool.reconnect() }

        let connecting = await iterator.next()
        _ = try await task.value
        let final = await iterator.next()

        #expect(connecting == .connecting)
        #expect(final == .online)
        #expect(await pool.currentStatus == .online)
    }
}
