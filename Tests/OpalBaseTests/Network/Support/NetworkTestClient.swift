import Foundation
@testable import OpalBase

enum NetworkTestClient {
    static var isLiveNetworkEnabled: Bool {
        parseFlag(named: "OPAL_RUN_LIVE_NETWORK_TESTS")
    }

    static var isExtendedLiveNetworkEnabled: Bool {
        parseFlag(named: "OPAL_RUN_EXTENDED_LIVE_NETWORK_TESTS")
    }

    static func withClient<T>(
        configuration: NetworkModel.Configuration,
        _ body: (NetworkModel.FulcrumClient) async throws -> T
    ) async throws -> T {
        let client = try await NetworkModel.FulcrumClient(configuration: configuration)
        do {
            let result = try await body(client)
            await client.stop()
            return result
        } catch {
            await client.stop()
            throw error
        }
    }

    private static func parseFlag(named key: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }
}
