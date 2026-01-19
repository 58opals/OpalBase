// PrivateKey~WIF.swift

import Foundation

extension PrivateKey {
    public enum WalletImportFormatCompression: Sendable, Equatable {
        case compressed
        case uncompressed
    }
    
    private static let walletImportFormatMainnetVersionByte: UInt8 = 0x80
    private static let walletImportFormatCompressedPublicKeyFlag: UInt8 = 0x01
    
    func makeWalletImportFormat(compression: WalletImportFormatCompression) -> String {
        var payload = Data([Self.walletImportFormatMainnetVersionByte])
        payload.append(rawData)
        
        if compression == .compressed {
            payload.append(Self.walletImportFormatCompressedPublicKeyFlag)
        }
        
        let checksum = HASH256.computeChecksum(for: payload)
        let walletImportFormatData = payload + checksum
        
        return Base58.encode(walletImportFormatData)
    }
    
    var compressedWalletImportFormat: String {
        makeWalletImportFormat(compression: .compressed)
    }
    
    var wif: String {
        compressedWalletImportFormat
    }
    
    public init(wif: String, expectedCompression: WalletImportFormatCompression = .compressed) throws {
        guard let decoded = Base58.decode(wif) else { throw Error.cannotDecodeWIF }
        guard decoded.count == 37 || decoded.count == 38 else { throw Error.invalidLength }
        
        let payload = decoded.prefix(decoded.count - 4)
        let checksum = decoded.suffix(4)
        let computedChecksum = HASH256.computeChecksum(for: Data(payload))
        
        guard checksum.elementsEqual(computedChecksum) else { throw Error.invalidChecksum }
        guard payload.first == Self.walletImportFormatMainnetVersionByte else { throw Error.invalidVersion }
        
        let keyData = Data(payload.dropFirst().prefix(32))
        guard keyData.count == 32 else { throw Error.invalidLength }
        
        let actualCompression: WalletImportFormatCompression
        switch payload.count {
        case 33:
            actualCompression = .uncompressed
        case 34:
            guard payload.last == Self.walletImportFormatCompressedPublicKeyFlag else { throw Error.invalidFormat }
            actualCompression = .compressed
        default:
            throw Error.invalidLength
        }
        
        guard actualCompression == expectedCompression else { throw Error.invalidFormat }
        
        try self.init(data: keyData)
    }
}
