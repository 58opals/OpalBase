// OpalBase+Account+MosaicPrivateAlphaRuntime.swift

#if os(macOS)
extension OpalBase.Account {
    /// Private-alpha wallet, broadcast, and chain recovery composition.
    ///
    /// Application persistence, keys, finality policy, and physical cleanup remain outside OpalBase.
    @_spi(MosaicPrivateAlpha)
    public enum MosaicPrivateAlphaRuntime {}
}
#endif
