// OpalBase+Account+MosaicPrivateAlphaRuntime+FreshHost.swift

#if os(macOS)
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Live wallet host whose exact binding is already durable in its attempt journal.
    @_spi(MosaicPrivateAlpha)
    public struct FreshHost: Sendable {
        /// The sole Fusion transition owner for private deployment and post-manifest execution.
        @_spi(MosaicPrivateAlpha)
        public let privateDeploymentOwner: OpalFusion
            .MosaicPrivateAlphaRuntime.Owner

        private let hostActor: OpalBase.Account.MosaicTransactionHostActor

        init(
            privateDeploymentOwner: OpalFusion.MosaicPrivateAlphaRuntime.Owner,
            transactionHost: OpalBase.Account.MosaicTransactionHostActor
        ) {
            self.privateDeploymentOwner = privateDeploymentOwner
            hostActor = transactionHost
        }

        /// The one stateful host actor for protocol reservation, signing, release, and commit callbacks.
        @_spi(MosaicPrivateAlpha)
        public var transactionHost:
            any OpalFusion.Host.MosaicCompleteTransactionHost {
            hostActor
        }
    }
}
#endif
