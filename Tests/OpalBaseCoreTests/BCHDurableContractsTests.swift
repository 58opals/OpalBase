import Foundation
import Synchronization
import Testing
@testable import OpalBaseCore

@Suite("Durable BCH contracts")
struct BCHDurableContractsTests {
    @Test("Fresh confirmed scan bounds issuance independently of local flags and branches")
    func boundedIssuance() async throws {
        let account = try await makeAccount()
        let chain = makeChain()
        let frontier = try await account.refreshConfirmedAddressFrontier(network: .mainnet, using: chain)
        for index in UInt32(0)...19 {
            _ = try await account.boundedReceivingAddress(at: index, frontier: frontier)
            _ = try await account.reserveNextReceivingDerivedAddress()
        }
        await #expect(throws: OpalBase.BCHSubmissionError.addressAllocationBlocked) {
            _ = try await account.boundedReceivingAddress(at: 20, frontier: frontier)
        }
        let fresh = try await makeAccount()
        let freshFrontier = try await fresh.refreshConfirmedAddressFrontier(network: .mainnet, using: chain)
        #expect(freshFrontier.receivingHighestIndex == -1)
        #expect(freshFrontier.changeHighestIndex == -1)
    }

    @Test("Confirmed history extends only its branch; refresh invalidates prior frontier")
    func historyFrontier() async throws {
        let account = try await makeAccount()
        let entries = await account.listDerivedAddresses(for: .receiving)
        let address = try #require(entries.first { $0.derivationPath.index == 19 })
        let hash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 9, count: 32))
        let history = OpalBase.Network.TransactionHistoryEntry(transactionIdentifier: hash.reverseOrder.hexadecimalString, blockHeight: 5, fee: nil)
        let frontier = try await account.refreshConfirmedAddressFrontier(network: .mainnet,
            using: makeChain(history: [address.address.string: [history]]))
        #expect(frontier.receivingHighestIndex == 19)
        #expect(frontier.changeHighestIndex == -1)
        _ = try await account.boundedReceivingAddress(at: 39, frontier: frontier)
        await #expect(throws: OpalBase.BCHSubmissionError.addressAllocationBlocked) {
            _ = try await account.boundedReceivingAddress(at: 40, frontier: frontier)
        }
        let removed = try await account.refreshConfirmedAddressFrontier(network: .mainnet, using: makeChain())
        #expect(removed.receivingHighestIndex == -1)
        await #expect(throws: OpalBase.BCHSubmissionError.staleFrontier) {
            _ = try await account.boundedReceivingAddress(at: 39, frontier: frontier)
        }
        let mempool = OpalBase.Network.TransactionHistoryEntry(transactionIdentifier: history.transactionIdentifier, blockHeight: 0, fee: nil)
        let unconfirmed = try await account.refreshConfirmedAddressFrontier(network: .mainnet,
            using: makeChain(history: [address.address.string: [mempool]]))
        #expect(unconfirmed.receivingHighestIndex == -1)
    }

    @Test("Review is unsigned, stable, and finalized bytes preserve its exact fee and ordering")
    func reviewAndFinalization() async throws {
        let (_, plan, _) = try await makePlan()
        let review = try await plan.review(network: .mainnet)
        let replay = try await plan.review(network: .mainnet)
        #expect(review.templateDigest == replay.templateDigest)
        let finalized = try await plan.finalize(network: .mainnet)
        let repeated = try await plan.finalize(network: .mainnet)
        #expect(finalized.rawBytes == repeated.rawBytes)
        #expect(finalized.fee == review.fee)
        #expect(finalized.transaction.outputs == review.envelope.unsignedTransaction.outputs)
        #expect(finalized.transaction.inputs.map(\.unlockingScript) != review.envelope.unsignedTransaction.inputs.map(\.unlockingScript))
        try review.envelope.validateSignedTransactionStructure(finalized.transaction)
        #expect(finalized.rawBytes.count == (try review.envelope.unsignedTransaction.encode().count))
        #expect(throws: (any Error).self) {
            _ = try OpalBase.FinalizedBCHTransaction(rawBytes: finalized.rawBytes + Data([0]), network: .mainnet, inputs: finalized.inputs)
        }
        try await plan.cancelReservation()
        await #expect(throws: (any Error).self) { _ = try await plan.finalize(network: .mainnet) }
    }

    @Test("Exact payload changes and removed inputs deny first handoff", arguments: [false, true])
    func staleInput(replacePayload: Bool) async throws {
        let (account, plan, selected) = try await makePlan()
        let finalized = try await plan.finalize(network: .mainnet)
        if replacePayload {
            let changed = OpalBase.Transaction.Output.Unspent(value: selected.value + 1, lockingScript: selected.lockingScript,
                previousTransactionHash: selected.previousTransactionHash, previousTransactionOutputIndex: selected.previousTransactionOutputIndex)
            await account.addressBook.addUTXOs([changed])
        } else { await account.addressBook.removeUTXO(selected) }
        let calls = Mutex(0)
        let relay = OpalBase.TransactionRelay(network: .mainnet) { value in
            calls.withLock { $0 += 1 }
            return .init { value.hash }
        }
        await #expect(throws: (any Error).self) {
            _ = try await plan.claimAndHandoff(finalized, using: relay, admission: { try $0() })
        }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("Admission owns actual claim and transport handoff under the synchronous middleware")
    func orderedHandoff() async throws {
        let (_, plan, _) = try await makePlan()
        let finalized = try await plan.finalize(network: .mainnet)
        let events = Mutex<[String]>([])
        let relay = OpalBase.TransactionRelay(network: .mainnet) { value in
            events.withLock { $0.append("handoff") }
            return .init { value.hash }
        }
        enum Denied: Error { case revoked }
        await #expect(throws: Denied.revoked) {
            _ = try await plan.claimAndHandoff(finalized, using: relay, admission: { _ in throw Denied.revoked })
        }
        try await plan.requireActiveReservation()
        #expect(events.withLock { $0.isEmpty })
        let invocation = try await plan.claimAndHandoff(finalized, using: relay) { handoff in
            events.withLock { $0.append("check") }
            let invocation = try handoff()
            events.withLock { $0.append("finish") }
            return invocation
        }
        let outcome = try await invocation.value()
        #expect(outcome.hash == finalized.hash)
        #expect(outcome.reservationCompletionError == nil)
        #expect(events.withLock { $0 } == ["check", "handoff", "finish"])
        await #expect(throws: (any Error).self) {
            _ = try await plan.claimAndHandoff(finalized, using: relay, admission: { try $0() })
        }
        #expect(events.withLock { $0.count } == 3)
    }

    @Test("Accepted relay remains accepted when current inventory makes cleanup fail")
    func acceptedCleanupFailure() async throws {
        let (account, plan, selected) = try await makePlan()
        let finalized = try await plan.finalize(network: .mainnet)
        let book = await account.addressBook
        let relay = OpalBase.TransactionRelay(network: .mainnet) { value in
            .init {
                await book.removeUTXO(selected)
                return value.hash
            }
        }
        let attempt = try await plan.claimAndHandoff(finalized, using: relay, admission: { try $0() })
        let outcome = try await attempt.value()
        #expect(outcome.hash == finalized.hash)
        #expect(outcome.reservationCompletionError != nil)
        await #expect(throws: (any Error).self) { try await plan.cancelReservation() }
        await #expect(throws: OpalBase.BCHSubmissionError.inactiveReservation) {
            try await plan.completeClaimedReservationAfterReconciliation()
        }
    }

    @Test("Reconciled unknown claims end their invocation and preserve refreshed unspent inputs", arguments: [false, true])
    func reconciledClaimDisposal(stillActive: Bool) async throws {
        let account = try await makeAccount()
        let first = try await addInput(to: account, byte: 0x41)
        let second = try await addInput(to: account, byte: 0x42)
        let plan = try await account.prepareSpend(payment(amount: 30_000))
        await #expect(throws: OpalBase.BCHSubmissionError.inactiveReservation) {
            try await plan.completeClaimedReservationAfterReconciliation()
        }
        let finalized = try await plan.finalize(network: .mainnet)
        let ended = Mutex(false)
        let relay = OpalBase.TransactionRelay(network: .mainnet) { _ in .init {
            defer { ended.withLock { $0 = true } }
            if stillActive { try await Task.sleep(for: .seconds(60)) }
            throw CancellationError()
        } }
        let attempt = try await plan.claimAndHandoff(finalized, using: relay, admission: { try $0() })
        if !stillActive { await #expect(throws: (any Error).self) { _ = try await attempt.value() } }
        // A confirmed conflict consumed only one input; the other remains authoritative.
        await account.addressBook.removeUTXO(first)
        let before = await account.addressBook.listUTXOs()
        #expect(before == [second])
        try await plan.completeClaimedReservationAfterReconciliation()
        #expect(ended.withLock { $0 })
        #expect(await account.addressBook.listUTXOs() == before)
        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await account.addressBook.utxoStore.reservedUTXOs.isEmpty)
        await #expect(throws: OpalBase.BCHSubmissionError.inactiveReservation) {
            try await plan.completeClaimedReservationAfterReconciliation()
        }
    }

    @Test("Bounded change stays at its branch frontier through cancellation and no-change completion")
    func reusableChange() async throws {
        let account = try await makeAccount()
        _ = try await addInput(to: account)
        let frontier = try await account.refreshConfirmedAddressFrontier(network: .mainnet, using: makeChain())
        let first = try await account.prepareBoundedSpend(payment(amount: 19_500), frontier: frontier)
        #expect(first.reservationHandle.changeEntry.derivationPath.index == 0)
        try await first.cancelReservation()
        let second = try await account.prepareBoundedSpend(payment(amount: 19_500), frontier: frontier)
        let finalized = try await second.finalize(network: .mainnet)
        #expect(finalized.change == nil)
        let relay = OpalBase.TransactionRelay(network: .mainnet) { value in .init { value.hash } }
        let attempt = try await second.claimAndHandoff(finalized, using: relay, admission: { try $0() })
        _ = try await attempt.value()
        _ = try await addInput(to: account, byte: 0x42)
        let third = try await account.prepareBoundedSpend(payment(amount: 10_000), frontier: frontier)
        #expect(third.reservationHandle.changeEntry.derivationPath.index == 0)
        try await third.cancelReservation()
    }

    @Test("A new coherent chain mutation invalidates a bounded preparation")
    func invalidatedFrontier() async throws {
        let account = try await makeAccount()
        _ = try await addInput(to: account)
        let frontier = try await account.refreshConfirmedAddressFrontier(network: .mainnet, using: makeChain())
        let plan = try await account.prepareBoundedSpend(payment(amount: 10_000), frontier: frontier)
        let current = try await account.refreshConfirmedAddressFrontier(network: .mainnet, using: makeChain())
        #expect(current.revision == frontier.revision)
        _ = try await plan.review(network: .mainnet)
        await account.invalidateConfirmedAddressFrontier()
        await #expect(throws: OpalBase.BCHSubmissionError.staleFrontier) {
            _ = try await plan.review(network: .mainnet)
        }
        try await plan.cancelReservation()
    }

    @Test("Expired leases deny finalization; mismatched relay hashes remain failures")
    func expiryAndRelayHash() async throws {
        let (account, plan, _) = try await makePlan()
        _ = try await account.addressBook.releaseExpiredSpendReservations(olderThan: 0)
        await #expect(throws: (any Error).self) { _ = try await plan.finalize(network: .mainnet) }
        let (_, next, _) = try await makePlan()
        let finalized = try await next.finalize(network: .mainnet)
        let relay = OpalBase.TransactionRelay(network: .mainnet) { _ in
            .init { .init(naturalOrder: Data(repeating: 0xFF, count: 32)) }
        }
        let invocation = try await next.claimAndHandoff(finalized, using: relay, admission: { try $0() })
        await #expect(throws: OpalBase.BCHSubmissionError.invalidTransaction) { _ = try await invocation.value() }
        await #expect(throws: (any Error).self) { try await next.cancelReservation() }
    }

    private func makeAccount() async throws -> OpalBase.Account {
        let words = Array(repeating: "abandon", count: 11) + ["about"]
        let wallet = try OpalBase.Wallet(mnemonic: OpalBase.Key.Mnemonic(phrase: words.joined(separator: " ")))
        try await wallet.addAccount(unhardenedIndex: 0)
        return try await wallet.fetchAccount(at: 0)
    }

    private func addInput(to account: OpalBase.Account, byte: UInt8 = 0x41) async throws -> OpalBase.Transaction.Output.Unspent {
        let derived = try await account.selectNextDerivedAddress(for: .receiving)
        let value = OpalBase.Transaction.Output.Unspent(value: 20_000, lockingScript: derived.address.lockingScript.data,
            previousTransactionHash: .init(naturalOrder: Data(repeating: byte, count: 32)), previousTransactionOutputIndex: 0)
        await account.addressBook.addUTXOs([value])
        return value
    }

    private func payment(amount: UInt64) throws -> OpalBase.Account.Payment {
        .init(recipients: [.init(address: try .init("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"), amount: try .init(amount))], shouldAllowDustDonation: true)
    }

    private func makePlan() async throws -> (OpalBase.Account, OpalBase.Account.SpendPlan, OpalBase.Transaction.Output.Unspent) {
        let account = try await makeAccount()
        let selected = try await addInput(to: account)
        return (account, try await account.prepareSpend(payment(amount: 10_000)), selected)
    }

    private func makeChain(history: [String: [OpalBase.Network.TransactionHistoryEntry]] = [:]) -> OpalBase.WalletPublicChainOperations {
        let addressReader = OpalBase.Network.AddressReader(fetchBalance: { _, _ in .init(confirmed: 0, unconfirmed: 0) },
            fetchUnspentOutputs: { _, _ in [] }, fetchHistory: { address, _ in history[address] ?? [] },
            fetchFirstUse: { _ in nil }, fetchMempoolTransactions: { _ in [] }, fetchScriptHash: { _ in "" },
            subscribeToAddress: { _ in AsyncThrowingStream { $0.finish() } })
        let transactionClient = OpalBase.Network.TransactionClient(broadcastTransaction: { _ in throw CancellationError() },
            fetchConfirmations: { _ in 6 }, fetchConfirmationStatus: { hash in
                .init(transactionHash: hash, transactionHeight: 5, tipHeight: 10, confirmations: 6)
            })
        return .init(addressReader: addressReader, transactionClient: transactionClient)
    }
}
