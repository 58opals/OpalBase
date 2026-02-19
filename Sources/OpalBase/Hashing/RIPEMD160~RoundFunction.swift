// RIPEMD160~RoundFunction.swift

import Foundation

extension RIPEMD160 {
    func rotateLeft(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    func F(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        x ^ y ^ z
    }

    func G(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) | (~x & z)
    }

    func H(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x | ~y) ^ z
    }

    func I(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & z) | (y & ~z)
    }

    func J(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        x ^ (y | ~z)
    }

    func FF(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ F(b, c, d) &+ x
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func GG(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ G(b, c, d) &+ x &+ 0x5a827999
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func HH(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ H(b, c, d) &+ x &+ 0x6ed9eba1
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func II(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ I(b, c, d) &+ x &+ 0x8f1bbcdc
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func JJ(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ J(b, c, d) &+ x &+ 0xa953fd4e
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func FFF(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ F(b, c, d) &+ x
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func GGG(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ G(b, c, d) &+ x &+ 0x7a6d76e9
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func HHH(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ H(b, c, d) &+ x &+ 0x6d703ef3
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func III(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ I(b, c, d) &+ x &+ 0x5c4dd124
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }

    func JJJ(_ a: inout UInt32, _ b: UInt32, _ c: inout UInt32, _ d: UInt32, _ e: UInt32, _ x: UInt32, _ s: UInt32) {
        a = a &+ J(b, c, d) &+ x &+ 0x50a28be6
        a = rotateLeft(a, s) &+ e
        c = rotateLeft(c, 10)
    }
}
