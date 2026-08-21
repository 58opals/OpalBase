// OpalBase+Account+MosaicPrivateAlphaRuntime+FreshHost.swift

#if os(macOS)
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Live wallet host whose exact binding is already durable in its attempt journal.
    @_spi(MosaicPrivateAlpha)
    public struct FreshHost: Sendable {
        /// Exact protocol identity shared with the durable application record.
        @_spi(MosaicPrivateAlpha) public let binding: Binding

        /// The sole Fusion transition owner for private deployment and post-manifest execution.
        let privateDeploymentOwner: OpalFusion
            .MosaicPrivateAlphaRuntime.Owner

        private let hostActor: OpalBase.Account.MosaicTransactionHostActor
        let previousOutputSource: OpalBase.Network.TransactionReader
        let sessionOwnerClaim = MosaicPrivateAlphaOneTimeClaim()

        init(
            binding: Binding,
            privateDeploymentOwner: OpalFusion.MosaicPrivateAlphaRuntime.Owner,
            transactionHost: OpalBase.Account.MosaicTransactionHostActor,
            previousOutputSource: OpalBase.Network.TransactionReader
        ) {
            self.binding = binding
            self.privateDeploymentOwner = privateDeploymentOwner
            hostActor = transactionHost
            self.previousOutputSource = previousOutputSource
        }

        /// The one stateful host actor for protocol reservation, signing, release, and commit callbacks.
        var transactionHost:
            any OpalFusion.Host.MosaicCompleteTransactionHost {
            hostActor
        }
    }
}
#endif
