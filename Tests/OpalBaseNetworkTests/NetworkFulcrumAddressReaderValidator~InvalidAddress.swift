// NetworkFulcrumAddressReaderValidator~InvalidAddress.swift

import Testing
@testable import OpalBase

extension NetworkFulcrumAddressReaderValidator {
    @Test("rejects invalid balance addresses before network usage", .timeLimit(.minutes(1)))
    func fetchBalanceRejectsInvalidAddress() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            do {
                _ = try await reader.fetchBalance(for: Self.invalidCashAddr, tokenFilter: .include)
                #expect(Bool(false), "Expected an invalid address to throw a protocol violation failure")
            } catch let failure as OpalBase.Network.Error {
                #expect(failure.reason == .protocolViolation)
                #expect(failure.message?.contains("Invalid address") ?? false)
            }
        }
    }

    @Test("rejects invalid addresses before network usage", .timeLimit(.minutes(1)))
    func fetchUnspentOutputsRejectsInvalidAddress1() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            var thrownError: Error?
            do {
                _ = try await reader.fetchUnspentOutputs(for: "not-an-address", tokenFilter: .include)
            } catch {
                thrownError = error
            }

            let failure = try #require(thrownError as? OpalBase.Network.Error)
            #expect(failure.reason == .protocolViolation)
            if let message = failure.message {
                #expect(message.contains("Invalid address"))
            }
        }
    }

    @Test("rejects invalid addresses before reaching the network", .timeLimit(.minutes(1)))
    func fetchUnspentOutputsRejectsInvalidAddress2() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            do {
                _ = try await reader.fetchUnspentOutputs(for: "invalid-address", tokenFilter: .include)
                #expect(Bool(false), "Expected an invalid address to throw a protocol violation failure")
            } catch let failure as OpalBase.Network.Error {
                #expect(failure.reason == .protocolViolation)
                #expect(failure.message?.contains("Invalid address") ?? false)
            }
        }
    }

    @Test("translates invalid address errors for wallet validation", .timeLimit(.minutes(1)))
    func fetchUnspentOutputsFailsForInvalidAddress() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectTimeout: .seconds(12),
            maximumMessageSize: 8 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 2,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(5),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            var capturedError: (any Error)?
            do {
                let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
                _ = try await reader.fetchUnspentOutputs(for: Self.invalidCashAddr, tokenFilter: .include)
                Issue.record("Expected fetch to throw for invalid address")
            } catch let failure as OpalBase.Network.Error {
                #expect(failure.reason == .protocolViolation)
                if let message = failure.message {
                    #expect(message.contains("Invalid address"))
                }
            } catch {
                capturedError = error
            }

            if let capturedError {
                throw capturedError
            }
        }
    }
}
