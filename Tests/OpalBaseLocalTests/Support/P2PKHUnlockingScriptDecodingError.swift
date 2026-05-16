// P2PKHUnlockingScriptDecodingError.swift

enum P2PKHUnlockingScriptDecodingError: Error {
    case truncated
    case unsupportedPushOpcode(UInt8)
    case trailingBytes
}
