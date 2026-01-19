import Foundation
import Testing
@testable import OpalBase

@Suite("Extended key derivation", .tags(.unit, .key))
struct ExtendedKeyDerivationTests {
    struct DerivationVector {
        let indices: [UInt32]
        let expectedExtendedPrivateKey: String
        let expectedExtendedPublicKey: String
    }
    
    @Test("derives canonical hierarchical deterministic vectors")
    func testDerivesCanonicalHierarchicalDeterministicVectors() throws {
        let seed = try Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f")
        let rootKey = try PrivateKey.Extended.Root(seed: seed)
        let rootPrivateKey = PrivateKey.Extended(rootKey: rootKey)
        
        let vectors: [DerivationVector] = [
            .init(
                indices: .init(),
                expectedExtendedPrivateKey: "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi",
                expectedExtendedPublicKey: "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"
            ),
            .init(
                indices: [Harden.harden(0)],
                expectedExtendedPrivateKey: "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7",
                expectedExtendedPublicKey: "xpub68Gmy5EdvgibQVfPdqkBBCHxA5htiqg55crXYuXoQRKfDBFA1WEjWgP6LHhwBZeNK1VTsfTFUHCdrfp1bgwQ9xv5ski8PX9rL2dZXvgGDnw"
            ),
            .init(
                indices: [Harden.harden(0), 1],
                expectedExtendedPrivateKey: "xprv9wTYmMFdV23N2TdNG573QoEsfRrWKQgWeibmLntzniatZvR9BmLnvSxqu53Kw1UmYPxLgboyZQaXwTCg8MSY3H2EU4pWcQDnRnrVA1xe8fs",
                expectedExtendedPublicKey: "xpub6ASuArnXKPbfEwhqN6e3mwBcDTgzisQN1wXN9BJcM47sSikHjJf3UFHKkNAWbWMiGj7Wf5uMash7SyYq527Hqck2AxYysAA7xmALppuCkwQ"
            ),
            .init(
                indices: [Harden.harden(0), 1, Harden.harden(2)],
                expectedExtendedPrivateKey: "xprv9z4pot5VBttmtdRTWfWQmoH1taj2axGVzFqSb8C9xaxKymcFzXBDptWmT7FwuEzG3ryjH4ktypQSAewRiNMjANTtpgP4mLTj34bhnZX7UiM",
                expectedExtendedPublicKey: "xpub6D4BDPcP2GT577Vvch3R8wDkScZWzQzMMUm3PWbmWvVJrZwQY4VUNgqFJPMM3No2dFDFGTsxxpG5uJh7n7epu4trkrX7x7DogT5Uv6fcLW5"
            ),
            .init(
                indices: [Harden.harden(0), 1, Harden.harden(2), 2],
                expectedExtendedPrivateKey: "xprvA2JDeKCSNNZky6uBCviVfJSKyQ1mDYahRjijr5idH2WwLsEd4Hsb2Tyh8RfQMuPh7f7RtyzTtdrbdqqsunu5Mm3wDvUAKRHSC34sJ7in334",
                expectedExtendedPublicKey: "xpub6FHa3pjLCk84BayeJxFW2SP4XRrFd1JYnxeLeU8EqN3vDfZmbqBqaGJAyiLjTAwm6ZLRQUMv1ZACTj37sR62cfN7fe5JnJ7dh8zL4fiyLHV"
            ),
            .init(
                indices: [Harden.harden(0), 1, Harden.harden(2), 2, 1_000_000_000],
                expectedExtendedPrivateKey: "xprvA41z7zogVVwxVSgdKUHDy1SKmdb533PjDz7J6N6mV6uS3ze1ai8FHa8kmHScGpWmj4WggLyQjgPie1rFSruoUihUZREPSL39UNdE3BBDu76",
                expectedExtendedPublicKey: "xpub6H1LXWLaKsWFhvm6RVpEL9P4KfRZSW7abD2ttkWP3SSQvnyA8FSVqNTEcYFgJS2UaFcxupHiYkro49S8yGasTvXEYBVPamhGW6cFJodrTHy"
            )
        ]
        
        var parentPublicKey = try PublicKey.Extended(extendedPrivateKey: rootPrivateKey)
        
        for vector in vectors {
            let derivedPrivateKey = try rootPrivateKey.deriveChild(at: vector.indices)
            let derivedPublicKeyFromPrivate = try PublicKey.Extended(extendedPrivateKey: derivedPrivateKey)
            
            #expect(derivedPrivateKey.address == vector.expectedExtendedPrivateKey)
            #expect(derivedPublicKeyFromPrivate.address == vector.expectedExtendedPublicKey)
            
            if let lastIndex = vector.indices.last, !Harden.checkHardened(lastIndex) {
                let derivedPublicKeyFromParent = try parentPublicKey.deriveChild(at: vector.indices)
                #expect(derivedPublicKeyFromParent == derivedPublicKeyFromPrivate)
            }
            
            parentPublicKey = derivedPublicKeyFromPrivate
        }
    }
}
