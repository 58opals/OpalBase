// MosaicBroadcastApprovalProbeActor.swift

#if os(macOS)
@testable import OpalBase

enum MosaicBroadcastApprovalTestSupport {
    static let securityProfile = OpalBase.WalletSecurityProfile(
        secretPersistencePolicy: .acceptProviderOutput,
        networkAccess: .publicChainSyncAndBroadcast,
        signingAccess: .inProcess
    )

    static let approve: OpalBase.Account
        .MosaicTransactionBroadcastCoordinator.RequestApproval = { _ in
            .approved
        }
}

actor MosaicBroadcastApprovalProbeActor {
    typealias Coordinator = OpalBase.Account.MosaicTransactionBroadcastCoordinator

    private var decisions: [Coordinator.ApprovalDecision]
    private var requests: [Coordinator.ApprovalRequest] = []
    private let suspensionProbe: MosaicOperationSuspensionProbeActor?

    init(
        decisions: [Coordinator.ApprovalDecision] = [.approved],
        suspensionProbe: MosaicOperationSuspensionProbeActor? = nil
    ) {
        self.decisions = decisions
        self.suspensionProbe = suspensionProbe
    }

    nonisolated func makeRequester() -> Coordinator.RequestApproval {
        { request in
            try await self.requestApproval(for: request)
        }
    }

    func readRequests() -> [Coordinator.ApprovalRequest] {
        requests
    }

    private func requestApproval(
        for request: Coordinator.ApprovalRequest
    ) async throws -> Coordinator.ApprovalDecision {
        requests.append(request)
        if let suspensionProbe {
            await suspensionProbe.suspend()
        }
        guard !decisions.isEmpty else { return .rejected }
        return decisions.removeFirst()
    }
}
#endif
