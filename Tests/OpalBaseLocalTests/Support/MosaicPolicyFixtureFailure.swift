// MosaicPolicyFixtureFailure.swift

#if os(macOS)
enum MosaicPolicyFixtureFailure: Error {
    case rejected
    case unexpectedFee
}
#endif
