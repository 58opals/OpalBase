// OpalBase+Account+CashFusionReadiness.swift

#if os(macOS)
import Foundation
import OpalDiagnostics

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
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("cash_fusion_readiness_evaluate"),
                OpalDiagnostics.Field.module()
            ]
            let spendableUTXOs = await addressBook.listSpendableUTXOs()
            let classifications = try await classifyCashFusionSelectedInputs(spendableUTXOs)
            let utxoEligibility = classifications.map(\.publicEligibility)
            let accountStatus: OpalBase.Account.CashFusionAccountStatus = classifications.contains(where: \.isEligible)
                ? .ready
                : .blocked(.noEligibleUTXOs)

            OpalDiagnostics.record(
                OpalDiagnostics.Event.cashFusionReadinessEvaluated,
                category: OpalDiagnostics.Category.cashFusion,
                fields: fields + [
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.utxoCount, spendableUTXOs.count),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.status, accountStatus.diagnosticsName)
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
