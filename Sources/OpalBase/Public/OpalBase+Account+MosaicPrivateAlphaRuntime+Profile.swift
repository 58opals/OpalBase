// OpalBase+Account+MosaicPrivateAlphaRuntime+Profile.swift

#if os(macOS)
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Base-owned profile identity that keeps OpalFusion types out of application call sites.
    @_spi(MosaicPrivateAlpha)
    public enum Profile: String, Sendable, Equatable {
        case draft1
        case opalV0
        case opalMainnetAlpha

        init(_ profile: OpalFusion.Mosaic.Profile) {
            switch profile {
            case .draft1:
                self = .draft1
            case .opalV0:
                self = .opalV0
            case .opalMainnetAlpha:
                self = .opalMainnetAlpha
            }
        }
    }
}
#endif
