import Foundation
@testable import OpalBase

enum NetworkTestSupport {
    static func withClient<T>(
        configuration: Network.Configuration,
        _ body: (Network.FulcrumClient) async throws -> T
    ) async throws -> T {
        let client = try await Network.FulcrumClient(configuration: configuration)
        do {
            let result = try await body(client)
            await client.stop()
            return result
        } catch {
            await client.stop()
            throw error
        }
    }
}
