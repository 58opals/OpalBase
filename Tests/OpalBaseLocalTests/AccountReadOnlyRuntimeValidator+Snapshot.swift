// AccountReadOnlyRuntimeValidator+Snapshot.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

extension AccountReadOnlyRuntimeValidator {
    @Test("read-only account hydrates snapshots with public state")
    func verifyReadOnlyAccountHydratesSnapshotPublicState() async throws {
        let privateAccount = try await AccountTestFixtures.makeAccount()
        let reservedAddress = try await privateAccount.reserveNextReceivingDerivedAddress()
        let fundingAddress = try await privateAccount.selectNextDerivedAddress(for: .receiving)
        let fundingHash = AccountTestFixtures.makeHash(byte: 0x41)
        let unspentOutput = Self.makeUnspentOutput(
            address: fundingAddress.address,
            value: 25_000,
            hashByte: 0x41
        )
        let addressBook = await privateAccount.addressBook
        await addressBook.addUTXOs([unspentOutput])
        let historyReader = WalletAddressReaderTestActor(
            historyByAddress: [
                fundingAddress.address.string: [
                    .init(
                        transactionIdentifier: fundingHash.reverseOrder.hexadecimalString,
                        blockHeight: 8,
                        fee: 300
                    )
                ]
            ]
        )
        _ = try await privateAccount.refreshTransactionHistory(
            using: .init(historyReader),
            usage: .receiving
        )

        let privateSnapshot = await privateAccount.makeSnapshot()
        let readOnlyAccount = try await Self.makeReadOnlyAccount(snapshot: privateSnapshot)
        let readOnlySnapshot = await readOnlyAccount.makeSnapshot()

        #expect(privateSnapshot.addressBook.receivingEntries.contains {
            $0.index == reservedAddress.derivationPath.index && $0.isReserved
        })
        #expect(readOnlySnapshot.addressBook.receivingEntries.allSatisfy { !$0.isReserved })
        #expect(Self.listUsedEntryIndexes(in: readOnlySnapshot.addressBook.receivingEntries) == Self.listUsedEntryIndexes(in: privateSnapshot.addressBook.receivingEntries))
        #expect(readOnlySnapshot.addressBook.utxos == privateSnapshot.addressBook.utxos)
        #expect(readOnlySnapshot.addressBook.transactions == privateSnapshot.addressBook.transactions)
    }
}
