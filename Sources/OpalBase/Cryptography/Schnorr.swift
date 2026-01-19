// Schnorr.swift

import Foundation

public enum Schnorr {
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
            r = Data(raw64.prefix(32))
            s = Data(raw64.suffix(32))
        }
        
        public init(r: Data, s: Data) throws {
            guard r.count == 32, s.count == 32 else {
                throw Error.invalidSignatureLength(actual: r.count + s.count)
            }
            self.r = Data(r)
            self.s = Data(s)
        }
    }
}
