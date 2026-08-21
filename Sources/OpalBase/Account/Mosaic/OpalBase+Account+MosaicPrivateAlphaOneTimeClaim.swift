// OpalBase+Account+MosaicPrivateAlphaOneTimeClaim.swift

#if os(macOS)
actor MosaicPrivateAlphaOneTimeClaim {
    private var isClaimed = false

    func claim() throws {
        guard !isClaimed else {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                .oneTimeCapabilityAlreadyClaimed
        }
        isClaimed = true
    }
}
#endif
