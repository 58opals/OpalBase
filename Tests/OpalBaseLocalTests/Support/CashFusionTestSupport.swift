// CashFusionTestSupport.swift

import Foundation
import OpalFusion
import Testing
@testable import OpalBase

enum CashFusionTestSupport {
    static func makeConfiguration() -> OpalFusion.Client.Configuration {
        .init(
            coordinatorHost: "fusion.example.com",
            coordinatorPort: 8787,
            covertChannel: .init(
                entryPath: "/covert",
                maxPayloadBytes: 32 * 1_024,
                requestTimeoutMilliseconds: 15_000
            )
        )
    }

    static func makeJoinPools() -> OpalFusion.ProtocolModel.JoinPools {
        .init(tiers: [100_000], tags: [])
    }

    static func makeSnapshot(
        identifier: String = "round-1",
        phase: OpalFusion.Round.Phase,
        completionStatus: OpalFusion.Round.CompletionStatus? = nil,
        isTerminal: Bool = false,
        isConnected: Bool = true,
        lastError: OpalFusion.Client.Error? = nil
    ) -> OpalFusion.Client.Session.Snapshot {
        .init(
            state: .init(
                isConnected: isConnected,
                round: .init(
                    identifier: .init(rawValue: identifier),
                    phase: phase,
                    participantCount: 3,
                    completionStatus: completionStatus,
                    isTerminal: isTerminal
                )
            ),
            lastError: lastError
        )
    }

    static func makeProposal(
        transaction: OpalBase.Transaction
    ) throws -> OpalFusion.Host.TransactionFinalizationProposal {
        .init(
            serializedUnsignedTransaction: [UInt8](try transaction.encode()),
            expectedInputCount: transaction.inputs.count,
            expectedOutputCount: transaction.outputs.count
        )
    }

    static func makeWalletOwnedUnspentOutput(
        to account: OpalBase.Account,
        value: UInt64,
        tokenData: OpalBase.CashTokens.TokenData? = nil,
        usage: OpalBase.Key.DerivationPath.Usage = .change,
        hashByte: UInt8,
        outputIndex: UInt32 = 0
    ) async throws -> OpalBase.Transaction.Output.Unspent {
        try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: value,
            tokenData: tokenData,
            usage: usage,
            hashByte: hashByte,
            outputIndex: outputIndex
        )
    }

    static func makeTokenData() throws -> OpalBase.CashTokens.TokenData {
        let fixture = try #require(TokenPrefixTestData.validVectors.first)
        let category = try OpalBase.CashTokens.CategoryID(hexFromRPC: fixture.data.category)
        let amount = try parseAmount(from: fixture.data.amount)
        let nonFungibleToken = try fixture.data.nonFungibleToken.map {
            try makeNonFungibleToken(from: $0)
        }
        return OpalBase.CashTokens.TokenData(
            category: category,
            amount: amount,
            nft: nonFungibleToken
        )
    }

    private static func parseAmount(from amountString: String?) throws -> UInt64? {
        guard let amountString else {
            return nil
        }
        guard let amountValue = UInt64(amountString) else {
            throw OpalBase.CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }

    private static func makeNonFungibleToken(
        from fixture: TokenPrefixNonFungibleTokenData
    ) throws -> OpalBase.CashTokens.NFT {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try OpalBase.CashTokens.NFT(
            capability: capability,
            commitment: commitment
        )
    }

    private static func makeNonFungibleCapability(
        from capabilityString: String
    ) throws -> OpalBase.CashTokens.NFT.Capability {
        switch capabilityString {
        case "none":
            return .none
        case "mutable":
            return .mutable
        case "minting":
            return .minting
        default:
            throw OpalBase.CashTokens.Error.invalidTokenPrefixCapability
        }
    }
}

actor CashFusionStateObserverSpy: OpalFusion.Client.StateObserver {
    private var snapshots: [OpalFusion.Client.Session.Snapshot] = []

    func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
        snapshots.append(snapshot)
    }

    func snapshotHistory() -> [OpalFusion.Client.Session.Snapshot] {
        snapshots
    }
}

actor CashFusionEventObserverSpy: OpalFusion.Host.EventObserver {
    struct Record: Sendable, Equatable {
        let event: OpalFusion.Host.Event
        let roundIdentifier: OpalFusion.Round.Identifier
    }

    private var records: [Record] = []

    func receive(
        _ event: OpalFusion.Host.Event,
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async {
        records.append(.init(event: event, roundIdentifier: roundIdentifier))
    }

    func recordHistory() -> [Record] {
        records
    }
}

final class CashFusionWrappedSessionCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var session: CashFusionFakeWrappedSession?

    func store(_ session: CashFusionFakeWrappedSession) {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    func load() -> CashFusionFakeWrappedSession? {
        lock.lock()
        let session = session
        lock.unlock()
        return session
    }
}

actor CashFusionFakeWrappedSession: OpalBase.Account.CashFusionWrappedSession {
    private let eventObserver: (any OpalFusion.Host.EventObserver)?
    private let stateObserver: (any OpalFusion.Client.StateObserver)?

    private var startCount = 0
    private var stopCount = 0
    private var currentSnapshot: OpalFusion.Client.Session.Snapshot = .init()

    init(
        eventObserver: (any OpalFusion.Host.EventObserver)?,
        stateObserver: (any OpalFusion.Client.StateObserver)?
    ) {
        self.eventObserver = eventObserver
        self.stateObserver = stateObserver
    }

    func start() async {
        startCount += 1
    }

    func stop() async {
        stopCount += 1
    }

    func snapshot() async -> OpalFusion.Client.Session.Snapshot {
        currentSnapshot
    }

    func emit(snapshot: OpalFusion.Client.Session.Snapshot) async {
        currentSnapshot = snapshot
        await stateObserver?.receive(snapshot)
    }

    func emit(
        event: OpalFusion.Host.Event,
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async {
        await eventObserver?.receive(event, for: roundIdentifier)
    }

    func readStartCount() -> Int {
        startCount
    }

    func readStopCount() -> Int {
        stopCount
    }
}

private enum CashFusionUnlockingScriptDecodingError: Error {
    case truncated
    case unsupportedPushOpcode(UInt8)
    case trailingBytes
}

func decodeCashFusionP2PKHUnlockingScript(
    _ unlockingScript: Data
) throws -> (signatureWithHashType: Data, publicKey: Data) {
    let bytes = Array(unlockingScript)
    var offset = 0
    let signatureWithHashType = try Data(
        readCashFusionPushedElement(from: bytes, offset: &offset)
    )
    let publicKey = try Data(
        readCashFusionPushedElement(from: bytes, offset: &offset)
    )

    guard offset == bytes.count else {
        throw CashFusionUnlockingScriptDecodingError.trailingBytes
    }

    return (signatureWithHashType, publicKey)
}

private func readCashFusionPushedElement(
    from bytes: [UInt8],
    offset: inout Int
) throws -> [UInt8] {
    guard offset < bytes.count else {
        throw CashFusionUnlockingScriptDecodingError.truncated
    }

    let opcode = bytes[offset]
    offset += 1

    let count: Int
    switch opcode {
    case 0 ... 75:
        count = Int(opcode)
    case ScriptOperationCode._PUSHDATA1.rawValue:
        guard offset < bytes.count else {
            throw CashFusionUnlockingScriptDecodingError.truncated
        }
        count = Int(bytes[offset])
        offset += 1
    case ScriptOperationCode._PUSHDATA2.rawValue:
        guard offset + 1 < bytes.count else {
            throw CashFusionUnlockingScriptDecodingError.truncated
        }
        count = Int(UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
        offset += 2
    case ScriptOperationCode._PUSHDATA4.rawValue:
        guard offset + 3 < bytes.count else {
            throw CashFusionUnlockingScriptDecodingError.truncated
        }
        count = Int(
            UInt32(bytes[offset]) |
                (UInt32(bytes[offset + 1]) << 8) |
                (UInt32(bytes[offset + 2]) << 16) |
                (UInt32(bytes[offset + 3]) << 24)
        )
        offset += 4
    default:
        throw CashFusionUnlockingScriptDecodingError.unsupportedPushOpcode(opcode)
    }

    guard offset + count <= bytes.count else {
        throw CashFusionUnlockingScriptDecodingError.truncated
    }

    let element = Array(bytes[offset ..< offset + count])
    offset += count
    return element
}
