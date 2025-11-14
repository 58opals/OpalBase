import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumTransactionHandlerReader", .tags(.network))
struct NetworkFulcrumTransactionHandlerReaderTests {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    private static let invalidServerAddress = URL(string: "not a url")!
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let invalidCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
    private static let unknownTransactionIdentifier = String(repeating: "0", count: 64)
    private static let invalidRawTransaction = "00"
    
    @Test("fetches confirmation count consistent with live tip", .timeLimit(.minutes(1)))
    func testFetchConfirmationsMatchesTipHeight() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        let client = try await Network.FulcrumClient(configuration: configuration)
        let handler = Network.FulcrumTransactionHandler(client: client)
        
        do {
            let history: SwiftFulcrum.Response.Result.Blockchain.Address.GetHistory = try await client.request(
                method: .blockchain(
                    .address(
                        .getHistory(
                            address: Self.sampleCashAddress,
                            fromHeight: nil,
                            toHeight: nil,
                            includeUnconfirmed: true
                        )
                    )
                )
            )
            
            let confirmedEntry = history.transactions.first { $0.height > 0 }
            #expect(confirmedEntry != nil)
            guard let confirmedEntry else {
                await client.stop()
                return
            }
            
            let tip: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            
            let confirmations = try await handler.fetchConfirmations(
                forTransactionIdentifier: confirmedEntry.transactionHash
            )
            
            let expectedConfirmations = Network.FulcrumTransactionHandler.calculateConfirmationCount(
                transactionHeight: UInt(confirmedEntry.height),
                tipHeight: tip.height
            )
            
            #expect(confirmations == expectedConfirmations)
            #expect(confirmations ?? 0 > 0)
            
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }
    
    @Test("fetches confirmations matching direct height queries", .timeLimit(.minutes(1)))
    func testFetchConfirmationsMatchesServerHeights() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        let client = try await Network.FulcrumClient(configuration: configuration)
        let handler = Network.FulcrumTransactionHandler(client: client)
        let addressReader = Network.FulcrumAddressReader(client: client)
        
        do {
            let confirmedHistory = try await addressReader.fetchHistory(for: Self.sampleCashAddress, includeUnconfirmed: false)
            let confirmedEntry = try #require(confirmedHistory.first(where: { $0.blockHeight > 0 }))
            
            let transactionHeight: SwiftFulcrum.Response.Result.Blockchain.Transaction.GetHeight = try await client.request(
                method: .blockchain(.transaction(.getHeight(transactionHash: confirmedEntry.transactionIdentifier))),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Transaction.GetHeight.self
            )
            #expect(transactionHeight.height == confirmedEntry.blockHeight)
            
            let tipHeight: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            
            let expectedConfirmations = Network.FulcrumTransactionHandler.calculateConfirmationCount(
                transactionHeight: transactionHeight.height,
                tipHeight: tipHeight.height
            )
            
            let confirmations = try await handler.fetchConfirmations(forTransactionIdentifier: confirmedEntry.transactionIdentifier)
            #expect(confirmations == expectedConfirmations)
            let nonOptionalConfirmations = try #require(confirmations)
            #expect(nonOptionalConfirmations >= 1)
            
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }
    
    @Test("propagates server errors for unknown transactions", .timeLimit(.minutes(1)))
    func testFetchConfirmationsPropagatesServerErrors() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        let client = try await Network.FulcrumClient(configuration: configuration)
        let handler = Network.FulcrumTransactionHandler(client: client)
        
        do {
            var thrownError: Error?
            do {
                _ = try await handler.fetchConfirmations(forTransactionIdentifier: Self.unknownTransactionIdentifier)
            } catch {
                thrownError = error
            }
            
            let failure = try #require(thrownError as? Network.Failure)
            switch failure.reason {
            case .server:
                #expect(true)
            default:
                Issue.record("Expected a server failure but received \(failure.reason)")
            }
            #expect(failure.message != nil)
            
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }
    
    @Test("rejects invalid raw transactions", .timeLimit(.minutes(1)))
    func testBroadcastTransactionRejectsInvalidPayload() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        let client = try await Network.FulcrumClient(configuration: configuration)
        let handler = Network.FulcrumTransactionHandler(client: client)
        
        do {
            var thrownError: Error?
            do {
                _ = try await handler.broadcastTransaction(rawTransactionHexadecimal: Self.invalidRawTransaction)
            } catch {
                thrownError = error
            }
            
            let failure = try #require(thrownError as? Network.Failure)
            switch failure.reason {
            case .server, .protocolViolation:
                #expect(true)
            default:
                Issue.record("Expected a server or protocol failure but received \(failure.reason)")
            }
            #expect(failure.message != nil)
            
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }
    
    @Test("rejects malformed transaction broadcast", .timeLimit(.minutes(1)))
    func testBroadcastTransactionTranslatesServerError() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        let client = try await Network.FulcrumClient(configuration: configuration)
        let handler = Network.FulcrumTransactionHandler(client: client)
        
        do {
            _ = try await handler.broadcastTransaction(rawTransactionHexadecimal: "00")
            Issue.record("Broadcast should have failed for malformed payload")
        } catch let failure as Network.Failure {
            #expect(failure.message != nil)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        
        await client.stop()
    }
    
    @Test("calculates confirmation counts across edge conditions")
    func testCalculateConfirmationCountHandlesBoundaries() {
        let direct = Network.FulcrumTransactionHandler.calculateConfirmationCount(
            transactionHeight: 100,
            tipHeight: 100
        )
        #expect(direct == 1)
        
        let advanced = Network.FulcrumTransactionHandler.calculateConfirmationCount(
            transactionHeight: 98,
            tipHeight: 102
        )
        #expect(advanced == 5)
        
        let negativeHeight = Network.FulcrumTransactionHandler.calculateConfirmationCount(
            transactionHeight: -1,
            tipHeight: 10
        )
        #expect(negativeHeight == nil)
        
        let futureTransaction = Network.FulcrumTransactionHandler.calculateConfirmationCount(
            transactionHeight: 150,
            tipHeight: 140
        )
        #expect(futureTransaction == nil)
    }
    
    @Test("calculates confirmation counts for edge cases")
    func testCalculateConfirmationCountEdgeCases() {
        let expectedConfirmations = Network.FulcrumTransactionHandler.calculateConfirmationCount(
            transactionHeight: 100_000,
            tipHeight: 100_010
        )
        #expect(expectedConfirmations == 11)
        
        let futureBlock = Network.FulcrumTransactionHandler.calculateConfirmationCount(
            transactionHeight: 100_011,
            tipHeight: 100_010
        )
        #expect(futureBlock == nil)
        
        let negativeHeight = Network.FulcrumTransactionHandler.calculateConfirmationCount(
            transactionHeight: -1,
            tipHeight: 100_010
        )
        #expect(negativeHeight == nil)
    }
}
