// OpalBase+Account+MosaicPrivateAlphaRuntime+PrivateDeploymentRole.swift

#if os(macOS)
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// App-visible authenticated role selected for one roster control identity.
    @_spi(MosaicPrivateAlpha)
    public enum PrivateDeploymentRole: Sendable, Equatable {
        case contributor
        case conductor

        init(
            _ role: OpalFusion.MosaicPrivateAlphaRuntime
                .PrivateDeploymentRole
        ) {
            switch role {
            case .contributor:
                self = .contributor
            case .conductor:
                self = .conductor
            }
        }
    }
}
#endif
