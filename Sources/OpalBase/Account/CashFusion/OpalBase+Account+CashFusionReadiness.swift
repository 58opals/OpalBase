#if os(macOS)
// OpalBase+Account+CashFusionReadiness.swift

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
        let spendableUTXOs = await addressBook.listSpendableUTXOs()
        let classifications = try await classifyCashFusionSelectedInputs(spendableUTXOs)
        let utxoEligibility = classifications.map(\.publicEligibility)
        let accountStatus: OpalBase.Account.CashFusionAccountStatus = classifications.contains(where: \.isEligible)
            ? .ready
            : .blocked(.noEligibleUTXOs)

        return .init(
            pilotAvailability: .available,
            accountStatus: accountStatus,
            utxoEligibility: utxoEligibility
        )
    }
}
#endif
