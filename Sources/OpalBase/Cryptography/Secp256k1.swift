//  Secp256k1.swift

import Foundation

public enum Secp256k1 {
    public struct Signature: Sendable, Equatable {
        public let r: Data
        public let s: Data
        
        public var raw64: Data {
            r + s
        }
        
        public init(raw64: Data) throws {
            guard raw64.count == 64 else {
                throw Error.invalidSignatureLength(actual: raw64.count)
            }
            let rValue = Data(raw64.prefix(32))
            let sValue = Data(raw64.suffix(32))
            try self.init(r: rValue, s: sValue)
        }
        
        public init(r: Data, s: Data) throws {
            guard r.count == 32, s.count == 32 else {
                throw Error.invalidSignatureLength(actual: r.count + s.count)
            }
            _ = try Self.makeSignatureScalar(from: r)
            _ = try Self.makeSignatureScalar(from: s)
            self.r = Data(r)
            self.s = Data(s)
        }
        
        public func encodeDER() throws -> Data {
            try Secp256k1.DER.encodeSignature(r: r, s: s)
        }
        
        public init(derEncoded: Data) throws {
            let signatureValues = try Secp256k1.DER.decodeSignature(derEncoded)
            try self.init(r: signatureValues.r, s: signatureValues.s)
        }
        
        public func normalizeLowS() -> Signature {
            guard let signatureSScalar = try? Self.makeSignatureScalar(from: s) else {
                return self
            }
            guard signatureSScalar.compare(to: Secp256k1.halfOrderScalar) == .orderedDescending else {
                return self
            }
            let normalizedScalar = signatureSScalar.negateModN()
            return (try? Signature(r: r, s: normalizedScalar.data32)) ?? self
        }
        
        public var isLowS: Bool {
            guard let signatureSScalar = try? Self.makeSignatureScalar(from: s) else {
                return false
            }
            return signatureSScalar.compare(to: Secp256k1.halfOrderScalar) != .orderedDescending
        }
        
        private static func makeSignatureScalar(from data: Data) throws -> Scalar {
            do {
                return try Scalar(data32: data, requireNonZero: true)
            } catch Scalar.Error.zeroNotAllowed {
                throw Error.signatureComponentZero
            } catch {
                throw Error.invalidSignatureScalar
            }
        }
    }
    
    static let halfOrderScalar = Scalar(
        unchecked: UInt256(
            limbs: [
                0xdfe92f46681b20a0,
                0x5d576e7357a4501d,
                0xffffffffffffffff,
                0x7fffffffffffffff
            ]
        )
    )
}
