// OpalBase+WalletTransactionAuthoringInteractor~CashCode.swift

public extension OpalBase.WalletTransactionAuthoringInteractor {
    /// Selects and reserves account inputs, derives the Cash Code destination,
    /// and returns a bounded-grinding spend plan.
    func prepareCashCodePayment(
        _ request: OpalBase.ReusablePaymentAddress.CashCodePaymentRequest,
        to address: OpalBase.ReusablePaymentAddress,
        expectedNetwork: OpalBase.Network.Environment
    ) async throws -> OpalBase.ReusablePaymentAddress.CashCodeSpendPlan {
        guard address.profile == .cashCodeV1 else {
            throw OpalBase.ReusablePaymentAddress.Error
                .legacyProfileIsReadOnly
        }
        guard address.network == expectedNetwork else {
            throw OpalBase.ReusablePaymentAddress.Error
                .senderNetworkMismatch
        }
        try Task.checkCancellation()

        let placeholderScript = CashCodeDerivation.makeLockingScript(
            for: address.spendPublicKey
        )
        let placeholderAddress = try OpalBase.Address(
            script: OpalBase.Script.decode(lockingScript: placeholderScript),
            format: request.tokenData == nil ? .standard : .tokenAware,
            network: expectedNetwork
        )

        if let tokenData = request.tokenData {
            let transfer = OpalBase.Account.TokenTransfer(
                recipients: [
                    .init(
                        address: placeholderAddress,
                        amount: request.amount,
                        tokenData: tokenData
                    ),
                ],
                feeOverride: request.feeOverride,
                feeContext: request.feeContext,
                shouldAllowDustDonation: request.shouldAllowDustDonation
            )
            let tokenSpendPlan = try await privateAccount.prepareTokenSpend(
                transfer,
                feePolicy: feePolicy
            )
            do {
                return try OpalBase.ReusablePaymentAddress.CashCodeSpendPlan(
                    request: request,
                    address: address,
                    placeholderLockingScript: placeholderScript,
                    tokenSpendPlan: tokenSpendPlan
                )
            } catch {
                try? await tokenSpendPlan.cancelReservation()
                throw error
            }
        }

        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: placeholderAddress,
                    amount: request.amount
                ),
            ],
            feeOverride: request.feeOverride,
            feeContext: request.feeContext,
            shouldAllowDustDonation: request.shouldAllowDustDonation
        )
        let spendPlan = try await privateAccount.prepareSpend(
            payment,
            feePolicy: feePolicy
        )
        do {
            return try OpalBase.ReusablePaymentAddress.CashCodeSpendPlan(
                request: request,
                address: address,
                placeholderLockingScript: placeholderScript,
                spendPlan: spendPlan
            )
        } catch {
            try? await spendPlan.cancelReservation()
            throw error
        }
    }
}
