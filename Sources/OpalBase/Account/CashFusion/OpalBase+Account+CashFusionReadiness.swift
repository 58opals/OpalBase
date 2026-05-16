// OpalBase+Account+CashFusionReadiness.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    public struct CashFusionReadiness: Sendable, Equatable {
        public let pilotAvailability: OpalBase.Account.CashFusionPilotAvailability
        public let accountStatus: OpalBase.Account.CashFusionAccountStatus
        public let utxoEligibility: [OpalBase.Account.CashFusionUTXOEligibility]

        public init(
            pilotAvailability: OpalBase.Account.CashFusionPilotAvailability,
            accountStatus: OpalBase.Account.CashFusionAccountStatus,
            utxoEligibility: [OpalBase.Account.CashFusionUTXOEligibility]
        ) {
            self.pilotAvailability = pilotAvailability
            self.accountStatus = accountStatus
            self.utxoEligibility = utxoEligibility
        }
    }
}

extension _OpalBase.Account {
    public func evaluateCashFusionReadiness() async throws -> OpalBase.Account.CashFusionReadiness {
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("cash_fusion_readiness_evaluate"),
                OpalBaseDiagnostics.moduleField()
            ]
            let spendableUTXOs = await addressBook.listSpendableUTXOs()
            let classifications = try await classifyCashFusionSelectedInputs(spendableUTXOs)
            let utxoEligibility = classifications.map(\.publicEligibility)
            let accountStatus: OpalBase.Account.CashFusionAccountStatus = classifications.contains(where: \.isEligible)
                ? .ready
                : .blocked(.noEligibleUTXOs)

            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.cashFusionReadinessEvaluated,
                category: OpalBase.Diagnostics.Categories.cashFusion,
                fields: fields + [
                    OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.utxoCount, spendableUTXOs.count),
                    OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.status, accountStatus.diagnosticsName)
                ]
            )

            return .init(
                pilotAvailability: .available,
                accountStatus: accountStatus,
                utxoEligibility: utxoEligibility
            )
        }
    }
}

private extension OpalBase.Account.CashFusionAccountStatus {
    var diagnosticsName: String {
        switch self {
        case .ready:
            return "ready"
        case .blocked(let reason):
            return "blocked.\(reason.diagnosticsName)"
        }
    }
}

private extension OpalBase.Account.CashFusionBlockedReason {
    var diagnosticsName: String {
        switch self {
        case .noEligibleUTXOs:
            return "no_eligible_utxos"
        case .tokenUTXO:
            return "token_utxo"
        case .unsupportedLockingScript:
            return "unsupported_locking_script"
        }
    }
}
#endif
