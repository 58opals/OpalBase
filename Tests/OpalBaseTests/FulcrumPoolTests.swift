import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("FulcrumPool Reconnection")
struct FulcrumPoolTests {
    @Test func testReconnectBringsOfflineServerOnline() async throws {
        let pool = try await Network.Wallet.FulcrumPool()
        #expect(await pool.currentStatus == .offline)
        
        let stream = await pool.observeStatus()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial == .offline)
        
        async let reconnection = pool.reconnect()

        let connecting = await iterator.next()
        _ = try await reconnection
        let final = await iterator.next()

        #expect(connecting == .connecting)
        #expect(final == .online)
        #expect(await pool.currentStatus == .online)
    }
    
    @Test func testPoolThrowsWhenNoServerResponds() async throws {
        let pool = try await Network.Wallet.FulcrumPool(urls: ["wss://invalid.example.invalid:50004"])
        
        await #expect(throws: Network.Wallet.Error.noHealthyServer) {
            _ = try await pool.acquireFulcrum()
        }
    }
}
