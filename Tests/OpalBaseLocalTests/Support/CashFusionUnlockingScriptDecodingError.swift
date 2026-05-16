// CashFusionUnlockingScriptDecodingError.swift

#if os(macOS)
enum CashFusionUnlockingScriptDecodingError: Error {
    case truncated
    case unsupportedPushOpcode(UInt8)
    case trailingBytes
}
#endif
